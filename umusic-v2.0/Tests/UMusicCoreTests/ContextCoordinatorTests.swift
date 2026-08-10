import Foundation
import Testing
import UMusicContext
import UMusicDomain

private actor ContextCallCounter {
    var samples = 0, starts = 0, stops = 0, locations = 0
    func sample() { samples += 1 }
    func start() { starts += 1 }
    func stop() { stops += 1 }
    func locate() { locations += 1 }
}

private struct TestMotion: MotionActivitySampling {
    let availability: SignalAvailability
    let counter: ContextCallCounter
    let result: ActivityClassification?
    func sample(for seconds: Double) async throws -> ActivityClassification? { await counter.sample(); return result }
    func stop() async { await counter.stop() }
}
private struct FailingMotion: MotionActivitySampling {
    let availability = SignalAvailability.available
    func sample(for seconds: Double) async throws -> ActivityClassification? { throw CancellationError() }
    func stop() async {}
}
private struct TestWorkout: WorkoutContextCollecting {
    let availability: SignalAvailability
    let counter: ContextCallCounter
    func start(activity: ListeningActivity) async throws { await counter.start() }
    func stop() async { await counter.stop() }
}
private struct TestPlace: CoarsePlaceClassifying {
    let availability: SignalAvailability
    let counter: ContextCallCounter
    func classifyOnce() async throws -> CoarsePlaceClass { await counter.locate(); return .outdoors }
    func stop() async { await counter.stop() }
}

private func contextURL() -> URL { FileManager.default.temporaryDirectory.appending(path: "umusic-context-tests/\(UUID().uuidString).json") }

@Test("Manual activity always works while denied motion remains inactive")
func manualActivityAndDeniedMotion() async throws {
    let counter = ContextCallCounter()
    let coordinator = ContextCoordinator(settingsURL: contextURL(), motion: TestMotion(availability: .denied, counter: counter, result: .init(activity: .running, confidence: 0.9)))
    await coordinator.selectActivity(.focus)
    await coordinator.setSignal(.motion, enabled: true)
    #expect((await coordinator.settings()).selectedActivity == .focus)
    #expect(!(await coordinator.settings()).motionEnabled)
    #expect(try await coordinator.sampleActivityNow() == nil)
    #expect(await counter.samples == 0)
}

@Test("Motion sampling is user-triggered, returns a suggestion, and stops")
func explicitMotionSample() async throws {
    let counter = ContextCallCounter()
    let expected = ActivityClassification(activity: .walking, confidence: 0.8)
    let coordinator = ContextCoordinator(settingsURL: contextURL(), motion: TestMotion(availability: .available, counter: counter, result: expected))
    await coordinator.setSignal(.motion, enabled: true)
    #expect(await counter.samples == 0)
    #expect(try await coordinator.sampleActivityNow() == expected)
    #expect(await counter.samples == 1)
    #expect(await counter.stops == 1)
    #expect((await coordinator.settings()).selectedActivity == .unknown)
}

@Test("Indoor sessions use no location; outdoor sessions classify once; finish cleans up")
func locationPolicyAndCleanup() async {
    let placeCounter = ContextCallCounter(), workoutCounter = ContextCallCounter()
    let coordinator = ContextCoordinator(settingsURL: contextURL(), workout: TestWorkout(availability: .available, counter: workoutCounter), place: TestPlace(availability: .available, counter: placeCounter))
    await coordinator.setSignal(.coarseLocation, enabled: true)
    await coordinator.setSignal(.workout, enabled: true)
    await coordinator.selectActivity(.gym)
    await coordinator.beginListeningContext()
    #expect(await placeCounter.locations == 0)
    await coordinator.endListeningContext()
    await coordinator.selectActivity(.running)
    await coordinator.beginListeningContext()
    #expect(await placeCounter.locations == 1)
    await coordinator.endListeningContext()
    #expect(await workoutCounter.starts == 2)
    #expect(await workoutCounter.stops >= 2)
    #expect(await placeCounter.stops >= 2)
}

@Test("Low Energy mode defaults on and platform-independent sources never block context start")
func contextDefaultsAndMissingSignals() async {
    let coordinator = ContextCoordinator(settingsURL: contextURL())
    #expect((await coordinator.settings()).lowEnergyMode)
    await coordinator.beginListeningContext()
    await coordinator.endListeningContext()
}

@Test("Restricted sources cannot be enabled and revocation stops an active adapter")
func restrictedAndRevokedSources() async {
    let restrictedCounter = ContextCallCounter()
    let restricted = ContextCoordinator(settingsURL: contextURL(), motion: TestMotion(availability: .restricted, counter: restrictedCounter, result: nil))
    await restricted.setSignal(.motion, enabled: true)
    #expect(!(await restricted.settings()).motionEnabled)

    let activeCounter = ContextCallCounter()
    let active = ContextCoordinator(settingsURL: contextURL(), motion: TestMotion(availability: .available, counter: activeCounter, result: nil))
    await active.setSignal(.motion, enabled: true)
    await active.setSignal(.motion, enabled: false)
    #expect(!(await active.settings()).motionEnabled)
    #expect(await activeCounter.stops == 1)
}

@Test("Sensor cancellation or timeout leaves manual activity available")
func sensorTimeoutFallback() async {
    let coordinator = ContextCoordinator(settingsURL: contextURL(), motion: FailingMotion())
    await coordinator.selectActivity(.relaxation)
    await coordinator.setSignal(.motion, enabled: true)
    await #expect(throws: CancellationError.self) { try await coordinator.sampleActivityNow() }
    #expect((await coordinator.settings()).selectedActivity == .relaxation)
}
