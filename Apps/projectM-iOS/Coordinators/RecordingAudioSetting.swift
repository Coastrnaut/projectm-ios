// RecordingAudioSetting.swift — REC-004: "Include microphone audio" for recordings (REC-004-R3, R13;
// specs/134-rec-004-recording-audio, data-model "Recording audio setting", ADR-0051).
//
// One device-local Bool, key `settings.recording.includeMicrophone`, default off (absent or not a Bool →
// off). It is a consent: it is left out of the library backup (it never travels to another device), erased
// with the Settings category like the other device switches, and removed by `-uitestResetNotice`. Turning
// it on never asks for the microphone permission (Microphone mode asks at its point of use, FILE-013).
import Foundation
import Observation

@MainActor
@Observable
final class RecordingAudioSetting {
    static let includeMicrophoneKey = "settings.recording.includeMicrophone"
    static let toggleTitle = "Include microphone audio"
    static let footer = "When the source is the microphone and you allow microphone access, recordings include the sound the microphone hears. App audio from your library is always included. Other apps' audio is never recorded."

    @ObservationIgnored private let defaults: UserDefaults

    var includeMicrophone: Bool {
        didSet { defaults.set(includeMicrophone, forKey: Self.includeMicrophoneKey) }
    }

    init(defaults: UserDefaults) {
        self.defaults = defaults
        includeMicrophone = (defaults.object(forKey: Self.includeMicrophoneKey) as? Bool) ?? false
    }
}
