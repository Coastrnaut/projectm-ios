# Research: AUD-002 Support common audio containers

Decisions are numbered `AUD-002-D1…`. Findings marked "probe" were measured on the build Mac
(macOS 27.2, Xcode 27.2) on 2026-11-12 with generated files and a scratch Swift program using
`AVAudioFile` and `AudioFileOpenURL`; the committed tests repeat every one of them on the host and
on the iOS simulator.

## AUD-002-D1 What AUD-001 already does per format (audit)

- **Probe**: `AVAudioFile(forReading:)` opens and decodes WAV (16-bit; 8 to 96 kHz), AIFF/AIFF-C,
  M4A with AAC and with Apple Lossless, raw ADTS `.aac`, and MP3, mono and stereo, when the file
  name carries the matching extension. So AUD-001's inspector and playback graph handle all five
  formats; none but WAV (and CAF) was tested.
- **Decision**: keep `AVAudioFile` for validation and playback; no second decode path
  (`ExtAudioFile`, `AVAssetReader`) is needed for any of the five formats.

## AUD-002-D2 The file name steers the system parser

- **Probe**: a WAV named `.mp3` and an AIFF named `.mp3` fail to open (`'dta?'`); an MP3 named
  `.aac` fails (`'layr'`); an ADTS stream named `.mp3` *opens* as MPEG Layer II at 11,025 Hz and
  then cannot be decoded. An M4A named `.wav`, an AIFF named `.wav`, a WAV or ADTS named `.m4a`
  and an M4A without extension open correctly. `AudioFileOpenURL` with an explicit type hint
  overrides the extension, but `AVAudioFile` has no hint parameter.
- **Decision**: recognize the container from the file's leading bytes and give the app's own copy
  the container's canonical extension (`mp3`, `aac`, `m4a`, `wav`, `aiff`) before the decoder ever
  sees it, both in `incoming/` (validation) and in `assets/` (playback).
- **Rationale**: validation and playback then use the same public API with the same name, so what
  was validated is what plays. Renaming our own copy is free (same folder).
- **Alternatives**: `AudioFileOpenURL` with a hint plus `ExtAudioFileWrapAudioFileID` for
  validation (works in the probe, but playback through `AVAudioPlayerNode.scheduleFile` needs an
  `AVAudioFile`, so validation and playback would differ); trusting the extension (the bug).

## AUD-002-D3 Recognition rules and bounds

- **Decision**: `AudioContainer.detect(header:)` is a pure function over at most 8 KiB:
  - `RIFF` + 4 bytes + `WAVE` → `wav`; `FORM` + 4 bytes + `AIFF` or `AIFC` → `aiff`;
    bytes 4…7 `ftyp` → `mpeg4`.
  - `ID3` + version + flags + 4 syncsafe size bytes → skip `10 + size` (+10 with a footer) and
    recognize what follows.
  - MPEG audio header (11 sync bits): layer bits `00` and a plausible ADTS header (sample-rate
    index ≤ 12, frame length ≥ 7) → `aac`; Layer III with a valid bit-rate and sample-rate index →
    `mp3`. At offset 0 one header is enough (a one-frame file is still that format); elsewhere in
    the window the next frame's header must follow at the computed frame length.
  - otherwise nil.
- `detect(at:)` reads the window with `FileHandle`, and for ID3 seeks once to the declared end of
  the tag and reads a second window. Total read ≤ 2 × 8 KiB; no allocation depends on the file.
- **Rationale**: these five signatures are stable and documented in the formats' specifications;
  the two-header rule is the usual guard against a stray `0xFF` byte.
- **Not recognized on purpose**: RF64/BW64, MPEG Layer I/II, CAF, FLAC, Ogg. They are "other":
  the picked extension is kept and the system decoder decides, exactly as in AUD-001.

## AUD-002-D4 Error classification

- **Probe** (`NSError.code` of the thrown error is the Core Audio status): text named `.wav` →
  `'typ?'`; WAV with an unknown format tag → `'fmt?'`; M4A whose sample entry was renamed →
  `'wht?'`; truncated M4A (2%) → `'wht?'`; header-only WAV → opens with length 0; zero-byte file →
  `'wht?'`; ADTS read as MPEG → the read fails with `'fmt?'`.
- **Decision**:

  | Situation | Error |
  |---|---|
  | zero bytes copied | `noAudio` |
  | open fails, container not recognized | `unsupportedFormat` |
  | open fails with `'fmt?'`, container recognized | `unsupportedEncoding` |
  | open fails otherwise, container recognized | `unreadable` |
  | opens, zero frames | `noAudio` |
  | opens, invalid rate or channel count 0 | `unreadable` |
  | more than two channels | `unsupportedChannelCount` (AUD-001) |
  | a decode probe fails with `'fmt?'` | `unsupportedEncoding` |
  | a decode probe fails otherwise, or the start decodes to zero frames | `unreadable` |

- **Limit, stated in the spec's clarifications**: the system reports an unknown MPEG-4 sample entry
  as an unspecified error, so that case is "damaged", not "unsupported encoding". Parsing MP4 boxes
  ourselves to tell them apart would add a parser for untrusted input for a rare case; rejected.

## AUD-002-D5 Truncation: probe the end as well as the start

- **Probe**: a WAV cut at 50% opens with the shorter length and reads to its end; ADTS and MP3
  likewise (their length is counted from the packets present). An AIFF cut at 50% or 90% opens
  with the *full* length and reading the last 2,048 frames fails (`eofErr`). An M4A cut at 50%
  opens and fails on the first read; Apple Lossless cut at 90% decodes the start and fails at the
  end.
- **Decision**: after the start probe, when the file is longer than the probe, seek to
  `length − 2048` and read. An error → `unreadable`. A read that returns no frames without an error
  is accepted (length estimates of compressed streams can overshoot by a packet).
- **Rationale**: catches the truncations the decoder does not absorb, at a cost independent of the
  file's length. Decoding the whole file would be exact but takes time proportional to the track.
- **Known gap**: damage in the middle of a file is not detected at import. During playback the
  system decoder conceals or skips it; the corruption sweep proves this does not crash.

## AUD-002-D6 Unsupported-encoding fixture and what is supported

- **Decision**: supported = whatever the device's decoder decodes inside a recognized container.
  Guaranteed and tested: MP3 (MPEG-1 Layer III), AAC-LC in ADTS and in M4A, linear PCM in WAV
  (8, 16, 24-bit integer and 32-bit float tested) and in AIFF/AIFF-C (16-bit). Tested as accepted:
  Apple Lossless in M4A. Not tested, accepted if the device decodes them: HE-AAC, compressed WAV
  and AIFF-C variants, MPEG-2/2.5 Layer III.
- The unsupported-encoding fixture is a WAV whose format tag is `0x7A21` (no such codec).

## AUD-002-D7 MP3 fixture without an encoder

- **Finding**: `afconvert -hf` lists MP3 for decoding only; `lame`, `ffmpeg`, `sox` are not
  installed, and installing from the network is out of bounds.
- **Decision**: test code (`MP3Fixture`) writes MPEG-1 Layer III frames directly: 32 kbit/s
  constant bit rate, no CRC, no bit reservoir, long blocks, scale factors of zero bits, and a
  Huffman-coded spectrum (table 1) with a single quantized line of magnitude 1 per channel, sign
  alternating per frame, global gain 204. One frequency line `k` of 576 decodes to a tone near
  `(k + 0.5) × rate / 1152` Hz with some amplitude modulation.
- **Probe**: the stream is identified by `afinfo` as MPEG Layer 3 with the exact packet count,
  decodes with `AVAudioFile` at 44.1 and 48 kHz, mono and stereo, peak about 0.36, and line 10 at
  44.1 kHz measures 401 Hz (expected 402).
- **Limit**: it proves a standard-conforming MP3 stream decodes through import and playback. It
  does not exercise variable bit rate, the bit reservoir, joint stereo or tags written by real
  encoders (ID3 skipping is tested separately by prefixing a tag). Those are `{device}` checks with
  the owner's own files.

## AUD-002-D8 Playback-time decode check

- **Finding**: `InAppPlaybackGraph.load` only opened the file and checked its length; an M4A
  truncated after import still opens, so playback started and rendered silence.
- **Decision**: `load` reads up to 4,096 frames from the first handle and resets
  `framePosition = 0`. A failure throws; `AVInAppPlaybackBackend` already maps that to
  `SourceError(.inAppPlaybackFailed)` before activating the session.
- **Cost**: one small decode on the main actor at start, comparable to opening the file.

## AUD-002-D9 Sample-rate and channel conversion

- **Finding**: the player node is connected to the main mixer in the file's processing format and
  the mixer converts to the output format (AUD-001-D7); a mono file is spread to both channels by
  the mixer. No code change is needed; AUD-001 tested one mono 44.1 kHz file at 48 kHz.
- **Decision**: prove it per format and rate by measuring the frequency of each output channel.
