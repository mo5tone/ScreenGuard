//
//  ScreenGuardEventMapperTests.swift
//  ScreenGuardTests
//
//  Pure event-type mapping from capture state. No window, no simulator capture, no timing — this is
//  the "event-type mapping from capture state" surface the package is required to test.
//

import XCTest
@testable import ScreenGuard

final class ScreenGuardEventMapperTests: XCTestCase {

    // MARK: - Transition table

    /// Every (previous, current) pair, asserted explicitly. Exhaustive on purpose: a `default` in the
    /// mapper would hide a future case, and a `default` here would hide a regression.
    func testEveryTransitionProducesTheContractualKind() {
        let cases: [(from: ScreenGuardCaptureState, to: ScreenGuardCaptureState, expected: ScreenGuardEvent.Kind?)] = [
            // Same state — idempotent, never an event.
            (.unspecified, .unspecified, nil),
            (.inactive, .inactive, nil),
            (.active, .active, nil),

            // Capture began.
            (.unspecified, .active, .captureBegan),
            (.inactive, .active, .captureBegan),

            // Capture ended — only when the previous state was a substantiated `.active`.
            (.active, .inactive, .captureEnded),

            // Never claim an end we cannot substantiate: losing the ability to determine the state is
            // not evidence that capture stopped.
            (.active, .unspecified, nil),
            (.unspecified, .inactive, nil),
            (.inactive, .unspecified, nil)
        ]

        for (from, to, expected) in cases {
            XCTAssertEqual(
                ScreenGuardEventMapper.eventKind(from: from, to: to),
                expected,
                "eventKind(from: .\(from.rawValue), to: .\(to.rawValue)) must be \(String(describing: expected))"
            )
        }
    }

    /// The transition table must cover all nine ordered pairs, so a new state cannot be added without
    /// this test failing.
    func testTransitionTableIsComplete() {
        let states: [ScreenGuardCaptureState] = [.unspecified, .inactive, .active]
        let covered = 9
        XCTAssertEqual(
            states.count * states.count,
            covered,
            "ScreenGuardCaptureState has \(states.count) cases; update this test when the enum grows."
        )

        // And each pair is reachable without trapping.
        for from in states {
            for to in states {
                _ = ScreenGuardEventMapper.eventKind(from: from, to: to)
            }
        }
    }

    /// Repeated identical signals must not spam the host.
    func testRepeatedSignalsEmitNothing() {
        XCTAssertNil(ScreenGuardEventMapper.eventKind(from: .active, to: .active))
        XCTAssertNil(ScreenGuardEventMapper.eventKind(from: .inactive, to: .inactive))
        XCTAssertNil(ScreenGuardEventMapper.eventKind(from: .unspecified, to: .unspecified))
    }

    /// A capture that begins, ends, then begins again yields exactly begin/end/begin.
    func testCaptureCycleProducesBeginEndBegin() {
        var state = ScreenGuardCaptureState.inactive
        var kinds: [ScreenGuardEvent.Kind] = []
        for next in [ScreenGuardCaptureState.active, .inactive, .active] {
            if let kind = ScreenGuardEventMapper.eventKind(from: state, to: next) { kinds.append(kind) }
            state = next
        }
        XCTAssertEqual(kinds, [.captureBegan, .captureEnded, .captureBegan])
    }

    // MARK: - Raw-value normalisation

    /// The iOS 17+ trait path. `UISceneCaptureState` is `unspecified = 0`, `inactive = 1`, `active = 2`.
    func testSceneCaptureStateRawValueMapping() {
        XCTAssertEqual(ScreenGuardEventMapper.captureState(sceneCaptureStateRawValue: 0), .unspecified)
        XCTAssertEqual(ScreenGuardEventMapper.captureState(sceneCaptureStateRawValue: 1), .inactive)
        XCTAssertEqual(ScreenGuardEventMapper.captureState(sceneCaptureStateRawValue: 2), .active)
    }

    /// A future OS value must degrade to `.unspecified`, never crash and never be misread as "active".
    func testUnknownSceneCaptureStateRawValueDegradesToUnspecified() {
        for rawValue in [-1, 3, 4, 99, Int.max, Int.min] {
            XCTAssertEqual(
                ScreenGuardEventMapper.captureState(sceneCaptureStateRawValue: rawValue),
                .unspecified,
                "raw value \(rawValue) must degrade to .unspecified"
            )
        }
    }

    /// The iOS 15/16 legacy path is a coarse boolean with no "unknown" case, so `false` is a known
    /// non-captured state, not `.unspecified`.
    func testLegacyBooleanMapping() {
        XCTAssertEqual(ScreenGuardEventMapper.captureState(isCaptured: true), .active)
        XCTAssertEqual(ScreenGuardEventMapper.captureState(isCaptured: false), .inactive)
    }

    /// The mapping is what makes "no double-reporting" true: the legacy `false` reading of a screen
    /// that was already `.inactive` produces no event.
    func testLegacyFalseAfterInactiveIsSilent() {
        let previous = ScreenGuardEventMapper.captureState(isCaptured: false)
        XCTAssertNil(ScreenGuardEventMapper.eventKind(from: previous, to: .inactive))
    }
}
