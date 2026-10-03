//
//  ScreenGuardMonitorTests.swift
//  ScreenGuardTests
//
//  The monitor's lifecycle, event delivery and configuration honouring.
//
//  These assert STATE and DELIVERY, never pixels: the pixel behaviour of a capture path is
//  device-pending and is skipped with an explicit reason in `ScreenGuardDeviceOnlyTests.swift`.
//

@testable import ScreenGuard
import XCTest

@MainActor
final class ScreenGuardMonitorTests: XCTestCase {
    /// Collects events through the delegate seam.
    private final class Recorder: ScreenGuardDelegate {
        var events: [ScreenGuardEvent] = []

        func screenGuard(_: ScreenGuardMonitor, didDetect event: ScreenGuardEvent) {
            events.append(event)
        }
    }

    // MARK: - Lifecycle

    func testStartStopIsIdempotent() {
        let monitor = ScreenGuardMonitor()
        XCTAssertFalse(monitor.isMonitoring)

        monitor.start()
        XCTAssertTrue(monitor.isMonitoring)

        monitor.start()
        XCTAssertTrue(monitor.isMonitoring, "start() must be idempotent")

        monitor.stop()
        XCTAssertFalse(monitor.isMonitoring)

        monitor.stop()
        XCTAssertFalse(monitor.isMonitoring, "stop() must be idempotent")
    }

    /// A stopped monitor must forget its state rather than reporting a stale capture.
    func testStopClearsTheState() {
        let monitor = ScreenGuardMonitor()
        monitor.start()
        monitor.stop()

        XCTAssertEqual(monitor.state.captureState, .unspecified)
        XCTAssertNil(monitor.state.detectionSource)
        XCTAssertFalse(monitor.state.isMonitoring)
    }

    /// The monitor's `deinit` must not require manual cleanup, and a monitor deallocated while
    /// running must not leave observers behind. If it did, this would leak and eventually crash.
    func testDeallocatingARunningMonitorIsSafe() {
        for _ in 0 ..< 20 {
            let monitor = ScreenGuardMonitor()
            monitor.start()
            monitor.stop()
        }
        for _ in 0 ..< 20 {
            let monitor = ScreenGuardMonitor()
            monitor.start()
            _ = monitor
        }
    }

    /// **Regression test for a reproduced crash.** A started monitor released from a background thread
    /// must not trap.
    ///
    /// The natural way to clean up in `deinit` is
    /// `deinit { MainActor.assumeIsolated { observer.stop() } }`, and it is wrong: `assumeIsolated`
    /// asserts the current executor already is the main actor, and `@MainActor` on the class does not
    /// control which thread performs the final `release`. Measured, that pattern aborted the test
    /// process outright. Cleanup is therefore owned by `ScreenGuardObserverTokenStore`, which removes
    /// notification tokens directly (thread-safe) and hops for the main-actor-isolated part.
    ///
    /// If this test crashes the process rather than failing, the trap is back.
    func testDeallocatingARunningMonitorOffTheMainThreadDoesNotTrap() {
        let done = expectation(description: "released off the main thread")

        DispatchQueue.global(qos: .userInitiated).async {
            var monitor: ScreenGuardMonitor?
            DispatchQueue.main.sync {
                monitor = ScreenGuardMonitor()
                monitor?.start()
            }
            // The last strong reference is dropped HERE, on a background thread.
            monitor = nil
            done.fulfill()
        }

        wait(for: [done], timeout: 30)
    }

    /// The same for the app-switcher shield, whose `uninstall()` is the documented manual path but
    /// whose deallocation must also be safe off-main.
    func testDeallocatingAnInstalledAppSwitcherShieldOffTheMainThreadDoesNotTrap() {
        let done = expectation(description: "shield released off the main thread")

        DispatchQueue.global(qos: .userInitiated).async {
            var shield: ScreenGuardAppSwitcherShield?
            var window: UIWindow?
            DispatchQueue.main.sync {
                let keyWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 240))
                window = keyWindow
                shield = ScreenGuardAppSwitcherShield()
                shield?.install(on: keyWindow)
            }
            shield = nil
            window = nil
            done.fulfill()
        }

        wait(for: [done], timeout: 30)
    }

    /// The monitor must not retain its delegate — a retain cycle here would be invisible until the
    /// host leaked every screen.
    func testDelegateIsHeldWeakly() {
        let monitor = ScreenGuardMonitor()
        do {
            let recorder = Recorder()
            monitor.delegate = recorder
            XCTAssertNotNil(monitor.delegate)
        }
        XCTAssertNil(monitor.delegate, "the delegate must be held weakly")
    }

    // MARK: - Configuration

    func testDefaultConfigurationEnablesTheThreeDetectors() {
        let configuration = ScreenGuardConfiguration()
        XCTAssertTrue(configuration.isScreenshotDetectionEnabled)
        XCTAssertTrue(configuration.isCaptureStateDetectionEnabled)
        XCTAssertTrue(configuration.isAppSwitcherShieldEnabled)
        XCTAssertEqual(configuration.noLeakStrategy, .publicPreventsCaptureLayer)
    }

    func testConfigurationIsAValueType() {
        var first = ScreenGuardConfiguration()
        first.isScreenshotDetectionEnabled = false
        let second = first

        first.isScreenshotDetectionEnabled = true

        XCTAssertFalse(second.isScreenshotDetectionEnabled, "configuration must be a value type")
    }

    /// The private path must never be reachable by default, from either entry point.
    func testPrivateStrategyIsNeverADefault() {
        XCTAssertEqual(ScreenGuardConfiguration().noLeakStrategy, .publicPreventsCaptureLayer)
        XCTAssertEqual(
            ScreenGuardMonitor(configuration: ScreenGuardConfiguration()).configuration.noLeakStrategy,
            .publicPreventsCaptureLayer
        )
    }

    // MARK: - Shared monitor

    func testSharedMonitorIsASingletonAndStartsIdempotently() {
        let first = ScreenGuard.start()
        let second = ScreenGuard.start()
        XCTAssertIdentical(first, second, "ScreenGuard.shared must be a single monitor")
        ScreenGuard.stop()
        XCTAssertFalse(first.isMonitoring)
    }

    /// `start(delegate:)` installs the delegate and returns the same shared monitor.
    func testStartWithDelegateInstallsIt() {
        let recorder = Recorder()
        let monitor = ScreenGuard.start(delegate: recorder)
        XCTAssertIdentical(monitor, ScreenGuard.shared)
        XCTAssertNotNil(monitor.delegate)
        ScreenGuard.stop()
    }

    // MARK: - Event delivery

    /// The delegate is the first seam, and the closure runs after it — the documented order.
    func testDelegateRunsBeforeTheClosureSeam() {
        // Records into a shared, externally-owned list so both seams can be compared in order.
        final class OrderRecorder: ScreenGuardDelegate {
            let order: OrderList

            init(order: OrderList) {
                self.order = order
            }

            func screenGuard(_: ScreenGuardMonitor, didDetect _: ScreenGuardEvent) {
                order.values.append("delegate")
            }
        }
        final class OrderList { var values: [String] = [] }

        let order = OrderList()
        let monitor = ScreenGuardMonitor()
        let recorder = OrderRecorder(order: order)

        monitor.delegate = recorder
        monitor.onEvent = { _ in order.values.append("closure") }

        monitor.reportProtectionFailure(.privateSecureLayerUnavailable)

        XCTAssertEqual(order.values, ["delegate", "closure"])
    }

    /// A protection failure is reportable through the unified event type, so a degraded shield is
    /// never silent.
    func testProtectionFailureIsReportedAsAUnifiedEvent() {
        let monitor = ScreenGuardMonitor()
        var events: [ScreenGuardEvent] = []
        monitor.onEvent = { events.append($0) }

        monitor.reportProtectionFailure(.privateSecureLayerUnavailable)

        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].kind, .protectionDegraded(reason: .privateSecureLayerUnavailable))
    }

    func testBothProtectionFailureReasonsRoundTrip() {
        let monitor = ScreenGuardMonitor()
        var events: [ScreenGuardEvent] = []
        monitor.onEvent = { events.append($0) }

        monitor.reportProtectionFailure(.privateSecureLayerUnavailable)
        monitor.reportProtectionFailure(.privateSecureLayerSwapFailed)

        XCTAssertEqual(events.map(\.kind), [
            .protectionDegraded(reason: .privateSecureLayerUnavailable),
            .protectionDegraded(reason: .privateSecureLayerSwapFailed),
        ])
    }

    // MARK: - Event value semantics

    func testEventCarriesItsTimestampAndSource() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let event = ScreenGuardEvent(
            kind: .screenshotTaken,
            captureState: .inactive,
            detectionSource: .screenshotNotification,
            timestamp: date
        )
        XCTAssertEqual(event.timestamp, date)
        XCTAssertEqual(event.detectionSource, .screenshotNotification)
        XCTAssertEqual(event.captureState, .inactive)
    }

    func testEventIsEquatableAcrossAllKinds() {
        let kinds: [ScreenGuardEvent.Kind] = [
            .screenshotTaken,
            .captureBegan,
            .captureEnded,
            .protectionDegraded(reason: .privateSecureLayerUnavailable),
        ]
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        for kind in kinds {
            let first = ScreenGuardEvent(
                kind: kind, captureState: .active, detectionSource: .sceneCaptureState, timestamp: date
            )
            let second = ScreenGuardEvent(
                kind: kind, captureState: .active, detectionSource: .sceneCaptureState, timestamp: date
            )
            XCTAssertEqual(first, second)
        }
        XCTAssertNotEqual(
            ScreenGuardEvent.Kind.captureBegan,
            ScreenGuardEvent.Kind.captureEnded
        )
    }

    /// The display trap (docs/api-contract.md §6.9): these types are String-backed so a consumer can
    /// write `Text(state.rawValue)`. Assert the raw values are what a UI renders.
    func testDisplayRawValuesAreStable() {
        XCTAssertEqual(ScreenGuardCaptureState.unspecified.rawValue, "unspecified")
        XCTAssertEqual(ScreenGuardCaptureState.inactive.rawValue, "inactive")
        XCTAssertEqual(ScreenGuardCaptureState.active.rawValue, "active")

        XCTAssertEqual(ScreenGuardDetectionSource.sceneCaptureState.rawValue, "sceneCaptureState")
        XCTAssertEqual(ScreenGuardDetectionSource.screenIsCaptured.rawValue, "screenIsCaptured")
        XCTAssertEqual(
            ScreenGuardDetectionSource.screenshotNotification.rawValue,
            "screenshotNotification"
        )

        XCTAssertEqual(
            ScreenGuardProtectionFailure.privateSecureLayerUnavailable.rawValue,
            "privateSecureLayerUnavailable"
        )
        XCTAssertEqual(
            ScreenGuardProtectionFailure.privateSecureLayerSwapFailed.rawValue,
            "privateSecureLayerSwapFailed"
        )
    }

    func testStateDefaultsDescribeAStoppedNeverDetectedMonitor() {
        let state = ScreenGuardState()
        XCTAssertEqual(state.captureState, .unspecified)
        XCTAssertNil(state.detectionSource)
        XCTAssertNil(state.lastScreenshotAt)
        XCTAssertFalse(state.isMonitoring)
    }
}
