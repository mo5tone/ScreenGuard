//
//  ScreenGuardCapabilityTests.swift
//  ScreenGuardTests
//
//  The capability registry must not drift from docs/api-contract.md §4. This test is the mechanism
//  that enforces it: it asserts the exact row count, the exact order, and the exact status of every
//  row, so a change to the package's promises fails the build rather than the review.
//

@testable import ScreenGuard
import XCTest

final class ScreenGuardCapabilityTests: XCTestCase {
    /// §4 has exactly ten rows. The enum must have exactly ten cases, in the same order.
    func testRegistryHasExactlyTheTenContractRowsInOrder() {
        let expected: [ScreenGuardCapability] = [
            .screenshotDetection,
            .captureStateDetection,
            .noLeakSecureTextEntry,
            .noLeakPublicPreventsCapture,
            .noLeakPrivateSecureLayer,
            .noLeakRecordingPath,
            .watermark,
            .appSwitcherSnapshotProtection,
            .preventUserScreenshot,
            .preventUserRecording,
        ]

        XCTAssertEqual(ScreenGuardCapability.allCases, expected)
        XCTAssertEqual(ScreenGuardCapability.allCases.count, 10, "§4 has exactly 10 rows")
        XCTAssertEqual(ScreenGuard.capabilityStatuses.map(\.capability), expected)
        XCTAssertEqual(ScreenGuard.capabilityStatuses.count, 10)
    }

    /// The status of every row, exactly as §4 states it.
    func testEveryStatusMatchesTheContract() {
        let expected: [ScreenGuardCapability: ScreenGuardVerificationStatus] = [
            .screenshotDetection: .devicePending,
            .captureStateDetection: .devicePending,
            .noLeakSecureTextEntry: .measured,
            .noLeakPublicPreventsCapture: .devicePending,
            .noLeakPrivateSecureLayer: .measured,
            .noLeakRecordingPath: .notMeasured,
            .watermark: .notMeasured,
            .appSwitcherSnapshotProtection: .devicePending,
            .preventUserScreenshot: .notPossible,
            .preventUserRecording: .notPossible,
        ]

        for (capability, status) in expected {
            XCTAssertEqual(
                ScreenGuard.status(of: capability),
                status,
                "\(capability.rawValue) must be .\(status.rawValue)"
            )
        }
        XCTAssertEqual(expected.count, 10)
    }

    /// §5 names three statuses explicitly. They are the honesty floor of the package.
    func testTheThreeContractuallyNamedStatuses() {
        XCTAssertEqual(
            ScreenGuard.status(of: .preventUserScreenshot), .notPossible,
            "iOS does not permit an app to block a screenshot"
        )
        XCTAssertEqual(
            ScreenGuard.status(of: .preventUserRecording), .notPossible,
            "iOS does not permit an app to block a recording"
        )
        XCTAssertEqual(
            ScreenGuard.status(of: .noLeakRecordingPath), .notMeasured,
            "no recording-path verdict may be claimed from Simulator data"
        )
        XCTAssertEqual(
            ScreenGuard.status(of: .screenshotDetection), .devicePending,
            "the screenshot event was never observed end-to-end"
        )
    }

    /// Only two capabilities may claim `measured`, and they are the two the evidence earns.
    func testOnlyTheTwoMeasuredCapabilitiesClaimMeasured() {
        let measured = ScreenGuard.capabilityStatuses
            .filter { $0.status == .measured }
            .map(\.capability)
        XCTAssertEqual(Set(measured), [.noLeakSecureTextEntry, .noLeakPrivateSecureLayer])
    }

    /// The public arbitrary-content path must never claim `measured`: on Simulator the layer paints
    /// nothing at all, so the result is unearned (capability-matrix.md §4).
    func testThePublicArbitraryContentPathDoesNotClaimMeasured() {
        XCTAssertNotEqual(ScreenGuard.status(of: .noLeakPublicPreventsCapture), .measured)
        XCTAssertEqual(ScreenGuard.status(of: .noLeakPublicPreventsCapture), .devicePending)
    }

    /// Every record carries a non-empty summary and a non-empty evidence citation — a status with no
    /// evidence would be an assertion, which is what this package exists to avoid.
    func testEveryRecordCarriesASummaryAndEvidence() {
        for record in ScreenGuard.capabilityStatuses {
            XCTAssertFalse(
                record.summary.isEmpty,
                "\(record.capability.rawValue) must carry a summary"
            )
            XCTAssertFalse(
                record.evidence.isEmpty,
                "\(record.capability.rawValue) must cite evidence"
            )
        }
    }

    /// The convenience lookup and the full record must agree.
    func testStatusLookupAgreesWithTheFullRecord() {
        for record in ScreenGuard.capabilityStatuses {
            XCTAssertEqual(ScreenGuard.status(of: record.capability), record.status)
            XCTAssertEqual(ScreenGuard.capabilityStatus(for: record.capability), record)
        }
    }

    /// Status raw values are the vocabulary defined in §4, and are what a host renders.
    func testStatusRawValuesMatchTheVocabulary() {
        XCTAssertEqual(ScreenGuardVerificationStatus.measured.rawValue, "measured")
        XCTAssertEqual(ScreenGuardVerificationStatus.devicePending.rawValue, "devicePending")
        XCTAssertEqual(ScreenGuardVerificationStatus.notMeasured.rawValue, "notMeasured")
        XCTAssertEqual(ScreenGuardVerificationStatus.notPossible.rawValue, "notPossible")
    }

    /// Capability raw values are stable identifiers a host app may persist.
    func testCapabilityRawValuesAreStableIdentifiers() {
        XCTAssertEqual(ScreenGuardCapability.screenshotDetection.rawValue, "screenshotDetection")
        XCTAssertEqual(ScreenGuardCapability.captureStateDetection.rawValue, "captureStateDetection")
        XCTAssertEqual(ScreenGuardCapability.noLeakSecureTextEntry.rawValue, "noLeakSecureTextEntry")
        XCTAssertEqual(
            ScreenGuardCapability.noLeakPublicPreventsCapture.rawValue,
            "noLeakPublicPreventsCapture"
        )
        XCTAssertEqual(ScreenGuardCapability.noLeakPrivateSecureLayer.rawValue, "noLeakPrivateSecureLayer")
        XCTAssertEqual(ScreenGuardCapability.noLeakRecordingPath.rawValue, "noLeakRecordingPath")
        XCTAssertEqual(ScreenGuardCapability.watermark.rawValue, "watermark")
        XCTAssertEqual(
            ScreenGuardCapability.appSwitcherSnapshotProtection.rawValue,
            "appSwitcherSnapshotProtection"
        )
        XCTAssertEqual(ScreenGuardCapability.preventUserScreenshot.rawValue, "preventUserScreenshot")
        XCTAssertEqual(ScreenGuardCapability.preventUserRecording.rawValue, "preventUserRecording")
    }

    func testVersionIsSemantic() {
        let components = ScreenGuard.version.split(separator: ".")
        XCTAssertEqual(components.count, 3, "version must be semantic (major.minor.patch)")
        for component in components {
            XCTAssertNotNil(Int(component), "version component '\(component)' must be numeric")
        }
    }
}
