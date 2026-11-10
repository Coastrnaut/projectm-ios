# App Store screenshots and app previews (T112)

Captured 2026-11-10 on simulators (Xcode 27.2): iPhone 17 Pro Max and iPad Pro 13-inch (M5). The
files here are exactly what was uploaded to App Store Connect: iPhone 1206 x 2622 (scaled from the
simulator's 1320 x 2868, see below), iPad 2064 x 2752. Debug build launched with `-autostart inAppPlayback -lastPresetID
<preset>`; status bar overridden to 9:41, full battery. Each screenshot is taken 30 s into the
reference track (its 20-40 s beat section, so the indicator reads "Active audio"; 10-20 s is
deliberate silence). Simulator footage is marketing material only, never test evidence.

| File | Preset (`Apps/ProjectMiOS/Resources/Presets/frontend-uwp/`) |
|------|--------|
| `iphone-1-mega-spectrum.png`, `ipad-1-mega-spectrum.png` | ORB - Mega Spectrum |
| `iphone-2-reaction-diffusion.png` | NeW Adam Master Mashup FX 2 Geiss and Zylot - Reaction Diffusion 3 (Overload Mix 2) AMAZING MASUP |
| `iphone-3-more-cherished-desires.png`, `ipad-2-more-cherished-desires.png` | Rovastar & StudioMusic - More Cherished Desires |
| `iphone-4-mega-swirl.png`, `ipad-3-mega-swirl.png` | Geiss - Mega Swirl 3 |
| `ipad-4-tides.png` | Stahlregen & flexi + Geiss + martin + Rovastar - Tides (martin's metallics) |

## App previews (no audio)

Not kept in the repository (about 60 MB; owner decision 2026-11-10); they live in App Store Connect
and can be recreated as follows. iPhone 886 x 1920 and iPad 1200 x 1600: ORB - Mega Spectrum, recorded with `xcrun simctl io <udid> recordVideo --codec=h264` from 19 s into
the reference track, then cut to 25.0 s at 30 fps, H.264, video track only (owner decision: no
audio), by `swift scripts/make_app_preview.swift <raw.mov> <out.mp4> <width> <height> 1 25`.

## Uploaded to App Store Connect (2026-11-10)

App Store Connect's iPhone slot is "iPhone with Dynamic Island (medium display)" (6.1"/6.3"), which
takes 1206 x 2622 screenshots; the simulator captures (1320 x 2868) were scaled with
`sips -z 2622 1206 <file>` (the aspect ratios differ by less than 0.1%), and only the scaled files
are kept. iPad PNGs went up as is (2064 x 2752). Order as numbered. The two previews were uploaded by the owner (over the browser tool's 10 MB
limit); App Store Connect then showed 1 preview and 4 screenshots for each device.
