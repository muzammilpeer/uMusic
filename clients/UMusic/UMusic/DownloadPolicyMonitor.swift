import Network
import SwiftUI
#if os(iOS)
import UIKit
#elseif os(macOS)
import IOKit.ps
#endif

@MainActor
final class DownloadPolicyMonitor: ObservableObject {
    @Published private(set) var usesWiFi = false
    @Published private(set) var networkAvailable = false
    @Published private(set) var connectionName = "Checking connection…"
    @Published private(set) var isCharging = true
    private let monitor = NWPathMonitor()
    #if os(macOS)
    private var powerTimer: Timer?
    #endif

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                self.networkAvailable = path.status == .satisfied
                #if os(macOS)
                self.usesWiFi = path.usesInterfaceType(.wifi)
                    || path.usesInterfaceType(.wiredEthernet)
                if path.usesInterfaceType(.wiredEthernet) {
                    self.connectionName = "Ethernet"
                } else if path.usesInterfaceType(.wifi) {
                    self.connectionName = "Wi-Fi"
                } else {
                    self.connectionName = path.status == .satisfied ? "Other network" : "Offline"
                }
                #else
                self.usesWiFi = path.usesInterfaceType(.wifi)
                self.connectionName = path.usesInterfaceType(.wifi)
                    ? "Wi-Fi" : path.status == .satisfied ? "Mobile network" : "Offline"
                #endif
            }
        }
        monitor.start(queue: DispatchQueue(label: "app.umusic.network-policy"))
        #if os(iOS)
        UIDevice.current.isBatteryMonitoringEnabled = true
        isCharging = [.charging, .full].contains(UIDevice.current.batteryState)
        #elseif os(macOS)
        isCharging = Self.macIsConnectedToPower()
        powerTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) {
            [weak self] _ in
            Task { @MainActor in self?.isCharging = Self.macIsConnectedToPower() }
        }
        #endif
    }

    func allows(_ preferences: OfflinePreferences) -> Bool {
        networkAvailable && (!preferences.wifiOnly || usesWiFi)
            && (!preferences.chargingOnly || isCharging)
    }

    #if os(macOS)
    private static func macIsConnectedToPower() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue()
                as? [CFTypeRef] else { return true }
        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                  let state = description[kIOPSPowerSourceStateKey] as? String else { continue }
            if state == kIOPSACPowerValue { return true }
            if state == kIOPSBatteryPowerValue { return false }
        }
        return true
    }
    #endif
}
