// MotionModulationSection.swift — CAM-011-R5, R11, R12, R14 (specs/247-cam-011-motion-sensor-modulation, contract
// motion-sources M5, M9): Settings › Motion, in the performance group (reachable while a scene is locked, research
// CAM-011-D9).
//
// A live readout of the four values (one accessibility element each, "Tilt forward", value "50 percent"; refreshed at
// most 10 times a second by the coordinator), Calibrate, and Range (Narrow, Medium, Wide). While on screen the section
// asks the coordinator for motion (`setReadoutOpen`), so the readout and Calibrate work before any scene uses motion.
// Without motion sensors a note explains it and Calibrate and Range are disabled. Small properties keep the body within
// CI's Xcode 26 type-check budget.
import ParameterGraph
import SwiftUI

struct MotionModulationSection: View {
    @Bindable var coordinator: MotionModulationCoordinator

    private var footerText: String {
        guard coordinator.isAvailable else {
            return MotionModulationCoordinator.unavailableNote + " " + MotionModulationCoordinator.footer
        }
        return MotionModulationCoordinator.footer
    }

    var body: some View {
        Section {
            readoutRows
            calibrateButton
            rangePicker
        } header: {
            Text(MotionModulationCoordinator.sectionTitle)
        } footer: {
            Text(footerText)
        }
        .onAppear { coordinator.setReadoutOpen(true) }
        .onDisappear { coordinator.setReadoutOpen(false) }
    }

    @ViewBuilder private var readoutRows: some View {
        if coordinator.isAvailable {
            ForEach(MotionAxis.allCases, id: \.self) { (axis: MotionAxis) in
                MotionReadoutRow(axis: axis, value: coordinator.readout.value(axis))
            }
        }
    }

    private var calibrateButton: some View {
        Button("Calibrate") { coordinator.calibrate() }
            .disabled(!coordinator.isAvailable)
            .accessibilityIdentifier("motionCalibrateButton")
            .accessibilityHint("Takes how you hold the device now as the middle.")
    }

    private var rangePicker: some View {
        Picker("Range", selection: $coordinator.range) {
            ForEach(MotionRange.allCases, id: \.self) { (range: MotionRange) in
                Text(range.title).tag(range)
            }
        }
        .disabled(!coordinator.isAvailable)
        .accessibilityIdentifier("motionRangePicker")
    }
}

private struct MotionReadoutRow: View {
    let axis: MotionAxis
    let value: Double

    var body: some View {
        let percent: Int = MotionModulationCoordinator.percent(value)
        LabeledContent(axis.inspectorName, value: String(percent) + "%")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(axis.inspectorName)
            .accessibilityValue(String(percent) + " percent")
            .accessibilityIdentifier("motionReadout." + axis.rawValue)
    }
}
