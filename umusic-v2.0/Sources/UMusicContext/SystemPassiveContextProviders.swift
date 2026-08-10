import Foundation
import Network
import UMusicDomain
#if os(iOS)
import AVFoundation
#endif

public struct SystemAudioRouteProvider: AudioRouteProviding {
    public init() {}
    public func currentCategory() async -> AudioRouteCategory {
#if os(iOS)
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        if outputs.contains(where: { [.bluetoothA2DP, .bluetoothHFP, .bluetoothLE].contains($0.portType) }) { return .bluetooth }
        if outputs.contains(where: { $0.portType == .airPlay }) { return .airPlay }
        if outputs.contains(where: { $0.portType == .carAudio }) { return .car }
        if outputs.contains(where: { [.headphones, .headsetMic, .usbAudio].contains($0.portType) }) { return .wired }
        if outputs.contains(where: { [.builtInSpeaker, .builtInReceiver].contains($0.portType) }) { return .builtIn }
        return .unknown
#else
        return .unknown
#endif
    }
}

public final class SystemNetworkClassProvider: NetworkClassProviding, @unchecked Sendable {
    public init() {}
    public func currentClass() async -> NetworkClass {
        await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let box = NetworkContinuationBox(monitor: monitor, continuation: continuation)
            monitor.pathUpdateHandler = { path in box.finish(path) }
            monitor.start(queue: DispatchQueue(label: "uk.muzammilpeer.umusic.context.network"))
            Task { try? await Task.sleep(for: .seconds(2)); box.timeout() }
        }
    }
}

private final class NetworkContinuationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NetworkClass, Never>?
    private let monitor: NWPathMonitor
    init(monitor: NWPathMonitor, continuation: CheckedContinuation<NetworkClass, Never>) { self.monitor = monitor; self.continuation = continuation }
    func finish(_ path: NWPath) {
        lock.lock(); guard let continuation else { lock.unlock(); return }; self.continuation = nil; lock.unlock()
        let value: NetworkClass
        if path.status != .satisfied { value = .offline }
        else if path.isExpensive || path.isConstrained { value = .metered }
        else { value = .unmetered }
        monitor.cancel(); continuation.resume(returning: value)
    }
    func timeout() {
        lock.lock(); guard let continuation else { lock.unlock(); return }; self.continuation = nil; lock.unlock()
        monitor.cancel(); continuation.resume(returning: .unknown)
    }
}
