// MotionSampling.swift — CAM-011-R8, R9, R10, R11 (specs/247-cam-011-motion-sensor-modulation, research CAM-011-D1,
// D8): the device-motion sensor behind a protocol, so the coordinator and its tests never need real sensors.
//
// * `CoreMotionSampler`: `CMMotionManager` device motion (`.xArbitraryZVertical`, the main queue) at the requested
//   rate; attitude in radians and user acceleration (gravity removed) in g. Device motion needs no usage description
//   (research CAM-011-D1), so no permission prompt is shown. The only file that imports CoreMotion; nothing here
//   stores, logs or sends a reading (CAM-011-R10).
// * DEBUG `StandInMotionSampler` (`-uitestMotionStandIn`): reports a fixed tilt with a timer, for the simulator, which
//   has no motion sensors (UI tests).
import CoreMotion
import Foundation
import ParameterGraph

/// A source of device-motion samples. Main actor: samples are delivered on the main actor.
@MainActor
protocol MotionSampling: AnyObject {
    /// The device can deliver device motion.
    var isAvailable: Bool { get }
    /// Starts (or restarts at a new rate) delivering samples to `handler`.
    func start(rateHz: Double, handler: @escaping @MainActor (MotionSample) -> Void)
    /// Stops delivering; idempotent.
    func stop()
}

@MainActor
final class CoreMotionSampler: MotionSampling {
    private let manager = CMMotionManager()

    var isAvailable: Bool { manager.isDeviceMotionAvailable }

    func start(rateHz: Double, handler: @escaping @MainActor (MotionSample) -> Void) {
        guard isAvailable, rateHz > 0 else { return }
        manager.stopDeviceMotionUpdates()
        manager.deviceMotionUpdateInterval = 1 / rateHz
        manager.startDeviceMotionUpdates(using: .xArbitraryZVertical, to: .main) { (motion: CMDeviceMotion?, _: Error?) -> Void in
            guard let motion else { return }
            let sample: MotionSample = Self.sample(motion)
            MainActor.assumeIsolated { handler(sample) }   // the main queue
        }
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }

    /// The reading as a plain sample; its time is the sensor's (seconds since boot) in nanoseconds.
    nonisolated static func sample(_ motion: CMDeviceMotion) -> MotionSample {
        let seconds: Double = max(motion.timestamp, 0)
        return MotionSample(pitch: motion.attitude.pitch, roll: motion.attitude.roll, yaw: motion.attitude.yaw,
                            accelerationX: motion.userAcceleration.x, accelerationY: motion.userAcceleration.y,
                            accelerationZ: motion.userAcceleration.z,
                            timeNanoseconds: UInt64((seconds * 1e9).rounded()))
    }
}

#if DEBUG
/// `-uitestMotionStandIn`: a device tilted forward 0.3 rad, sideways −0.2 rad and turned 0.1 rad, held still, reported
/// at the requested rate (research CAM-011-D8). The clock is the system uptime, as the real sensor's.
@MainActor
final class StandInMotionSampler: MotionSampling {
    static let launchArgument = "-uitestMotionStandIn"
    static var isRequested: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }

    private var timer: Timer?
    let isAvailable = true

    func start(rateHz: Double, handler: @escaping @MainActor (MotionSample) -> Void) {
        stop()
        let fire: @MainActor () -> Void = { () -> Void in
            let now: UInt64 = UInt64((ProcessInfo.processInfo.systemUptime * 1e9).rounded())
            handler(MotionSample(pitch: 0.3, roll: -0.2, yaw: 0.1, timeNanoseconds: now))
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1 / max(rateHz, 1), repeats: true) { (_: Timer) -> Void in
            MainActor.assumeIsolated { fire() }
        }
        fire()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
#endif
