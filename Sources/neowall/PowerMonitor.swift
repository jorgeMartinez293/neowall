import Foundation
import IOKit.ps

/// Reports the power source and Low Power Mode, and calls `onChange` on the
/// main thread when either changes.
final class PowerMonitor {
    var onChange: (() -> Void)?
    private var observer: NSObjectProtocol?

    init() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue().onChange?()
        }, context)?.takeRetainedValue()
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode) }

        observer = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main
        ) { [weak self] _ in self?.onChange?() }
    }

    var onBattery: Bool {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue()
        else { return false }
        return type as String == kIOPSBatteryPowerValue
    }

    var lowPowerMode: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
}
