// UITestMemoryBallast.swift — DEBUG only (QA-011 PERF-006-T17, 2026-11-21). "memory:fill" on the memory panel
// (`-uitestMemoryPressure`) grows dirty memory in 64 MB steps until the system itself posts
// `UIApplication.didReceiveMemoryWarningNotification` (a real warning: nothing in the app posts it while filling),
// then frees it all. Safety: it never leaves the app less than `floorBytes` of `os_proc_available_memory()`, stops
// after `budgetSeconds`, and frees everything when it ends either way. `devicectl device process sendMemoryWarning`
// fails with "No such file or directory" on iPadOS 27.2 (D2, 2026-11-21), so the device test fills instead.
// The probe `memoryFill` reads "state=<idle|filling|warned|floor|timeout> filledMB=<n> availableMB=<n> seconds=<s>".
// Not compiled into Release builds.
#if DEBUG
import Foundation
import os
import UIKit

@MainActor
@Observable
final class UITestMemoryBallast {
    static let shared = UITestMemoryBallast()
    nonisolated static let stepBytes = 64 * 1_048_576
    nonisolated static let floorBytes = 200 * 1_048_576
    nonisolated static let budgetSeconds: Double = 90
    private(set) var value = "state=idle"
    private var running = false

    func fill() {
        guard !running else { return }
        running = true
        value = "state=filling filledMB=0"
        Task.detached(priority: .userInitiated) {
            let warned = OSAllocatedUnfairLock(initialState: false)
            let observer = NotificationCenter.default.addObserver(
                forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { _ in
                warned.withLock { $0 = true }
            }
            var blocks: [UnsafeMutableRawPointer] = []
            let start = Date()
            var state = "timeout"
            while Date().timeIntervalSince(start) < Self.budgetSeconds {
                if warned.withLock({ $0 }) { state = "warned"; break }
                if os_proc_available_memory() < Self.floorBytes + Self.stepBytes { state = "floor"; break }
                guard let block = malloc(Self.stepBytes) else { state = "floor"; break }
                memset(block, 0xA5, Self.stepBytes)   // dirty pages: compressed or resident, never free
                blocks.append(block)
                let line = Self.line("filling", blocks.count, start)
                await MainActor.run { UITestMemoryBallast.shared.value = line }
                try? await Task.sleep(for: .milliseconds(30))   // gives the warning time to arrive
            }
            // A warning can arrive just after the last step.
            if state != "warned" {
                try? await Task.sleep(for: .milliseconds(500))
                if warned.withLock({ $0 }) { state = "warned" }
            }
            let line = Self.line(state, blocks.count, start)
            for block in blocks { free(block) }
            NotificationCenter.default.removeObserver(observer)
            await MainActor.run {
                UITestMemoryBallast.shared.value = line
                UITestMemoryBallast.shared.running = false
            }
        }
    }

    nonisolated private static func line(_ state: String, _ blocks: Int, _ start: Date) -> String {
        let seconds = String(format: "%.1f", Date().timeIntervalSince(start))
        return "state=\(state) filledMB=\(blocks * 64) availableMB=\(os_proc_available_memory() / 1_048_576) seconds=\(seconds)"
    }
}
#endif
