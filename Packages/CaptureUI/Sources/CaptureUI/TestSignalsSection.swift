// TestSignalsSection.swift — the chooser's Diagnostics section and the Test Signals list (AUD-016-T18;
// AUD-016-R13, R14, R16; specs/011-aud-016-reference-tone-suite/contracts/ui-strings.md).
//
// A list section after the sources and "Your Audio" with one row that opens the list of generated
// test signals (ReferenceToneCatalog). Nothing plays until a signal is tapped; the app starts it as
// In-App Playback and stores nothing about the choice. The list says what the signals are (generated
// on the device, not music) and to lower the volume first.
#if canImport(SwiftUI)
import AudioCore
import SwiftUI

/// The Diagnostics section of the source chooser: one navigation row to the Test Signals list.
public struct TestSignalsSection: View {
    public let fixtures: [ReferenceToneFixture]
    public let onPlay: (ReferenceToneFixture) -> Void

    public init(fixtures: [ReferenceToneFixture] = ReferenceToneCatalog.fixtures, onPlay: @escaping (ReferenceToneFixture) -> Void) {
        self.fixtures = fixtures
        self.onPlay = onPlay
    }

    public var body: some View {
        Section {
            NavigationLink {
                TestSignalListView(fixtures: fixtures, onPlay: onPlay)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label(UIStrings.testSignals, systemImage: "waveform.path")
                        .font(.headline)
                    Text(UIStrings.testSignalsRowDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(UIStrings.testSignals))
            .accessibilityHint(Text(UIStrings.testSignalsRowDetail))
            .accessibilityIdentifier("testSignals")
        } header: {
            Text(UIStrings.diagnostics)
        }
    }
}

/// The generated test signals; a tap plays one.
public struct TestSignalListView: View {
    public let fixtures: [ReferenceToneFixture]
    public let onPlay: (ReferenceToneFixture) -> Void

    public init(fixtures: [ReferenceToneFixture], onPlay: @escaping (ReferenceToneFixture) -> Void) {
        self.fixtures = fixtures
        self.onPlay = onPlay
    }

    public var body: some View {
        List {
            Section {
                ForEach(fixtures) { fixture in
                    Button {
                        onPlay(fixture)
                    } label: {
                        TestSignalRow(fixture: fixture)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(Text(fixture.name))
                    .accessibilityHint(Text("\(fixture.summary) \(UIStrings.testSignalHint)"))
                    .accessibilityIdentifier("testSignal.\(fixture.id)")
                }
            } footer: {
                Text(UIStrings.testSignalsFooter)
            }
        }
        .navigationTitle(UIStrings.testSignals)
    }
}

/// One signal: its name and what it plays.
public struct TestSignalRow: View {
    public let fixture: ReferenceToneFixture

    public init(fixture: ReferenceToneFixture) {
        self.fixture = fixture
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(fixture.name)
                .font(.headline)
            Text(fixture.summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
#endif
