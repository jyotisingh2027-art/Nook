import Foundation
import IOKit.ps

/// Tells the app when the Mac is on battery or in Low Power Mode so effects can be reduced.
final class PowerMonitor {
    static let shared = PowerMonitor()
    static let didChange = Notification.Name("NookPowerDidChange")

    private(set) var isOnBattery = false
    private(set) var isLowPowerMode = false
    var shouldSaveEnergy: Bool { isOnBattery || isLowPowerMode }

    private var timer: Timer?

    func start() {
        refresh(force: true)
        NotificationCenter.default.addObserver(forName: .NSProcessInfoPowerStateDidChange, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        // Checking the power source is very cheap; every 20 s is plenty.
        let t = Timer(timeInterval: 20, repeats: true) { [weak self] _ in self?.refresh() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func refresh(force: Bool = false) {
        var battery = false
        if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let type = IOPSGetProvidingPowerSourceType(blob)?.takeUnretainedValue() {
            battery = (type as String) == kIOPSBatteryPowerValue
        }
        let low = ProcessInfo.processInfo.isLowPowerModeEnabled
        if force || battery != isOnBattery || low != isLowPowerMode {
            isOnBattery = battery
            isLowPowerMode = low
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: PowerMonitor.didChange, object: self)
            }
        }
    }
}
