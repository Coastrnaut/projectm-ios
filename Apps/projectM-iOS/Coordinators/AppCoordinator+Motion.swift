// AppCoordinator+Motion.swift — CAM-011: device tilt and shake feed the bindings and triggers that name them
// (specs/247-cam-011-motion-sensor-modulation, research CAM-011-D6).
//
// A new native spectrum is connected to the motion coordinator beside its LFOs (MOD-007): it reads the tracker's
// values on each evaluated frame and reports whether any binding or trigger reads motion, which starts or stops the
// sensor. Scene activity (`sceneBecame(active:)`) stops the sensor in the background.
import Foundation
import ParameterGraph

extension AppCoordinator {
    func makeMotionModulation(defaults: UserDefaults) -> MotionModulationCoordinator {
        let coordinator = MotionModulationCoordinator(defaults: defaults, sampler: MotionModulationCoordinator.systemSampler())
        coordinator.announce = { [weak self] (text: String) -> Void in self?.announcer.announce(text, kind: .parameter) }   // R14
        coordinator.observePowerChanges()   // R9: PERF-008 profile and Low Power Mode changes re-rate the sensor
        return coordinator
    }

    func connectMotion(_ host: NativeSpectrumHost) {
        motionModulation.connect(host)
    }
}
