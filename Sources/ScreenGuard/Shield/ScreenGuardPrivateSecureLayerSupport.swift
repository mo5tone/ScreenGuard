//
//  ScreenGuardPrivateSecureLayerSupport.swift
//  ScreenGuard
//
//  The seam that lets the private-API file be LEFT OUT of the build without breaking it.
//
//  docs/api-contract.md §9.4 requires a consumer-actionable escape hatch: a consumer who must not ship
//  the private class-name string must be able to keep it out of their binary without forking. That is
//  delivered by the SPM package trait `PrivateAPI`, which is NOT enabled by default. The promise is
//  only real if nothing else in the module names the private type — and `ScreenGuardShieldView` has to
//  be able to engage it. This file is the indirection that makes both true.
//
//  The protocol is declared here (always compiled). The factory has exactly one definition in each
//  configuration:
//
//    * trait ENABLED  → `ScreenGuardPrivateSecureLayerFactory` builds the real engine
//      (`ScreenGuardPrivateSecureLayer.swift`, guarded by `#if SCREENGUARD_PRIVATE_API`).
//    * trait ABSENT   → the `#if` branch below returns `nil`, and the shield reports
//      `protectionFailure = .privateSecureLayerUnavailable` and degrades to the LABELLED
//      detection-and-overlay fallback.
//
//  `SCREENGUARD_PRIVATE_API` is defined by `Package.swift` via
//  `.define("SCREENGUARD_PRIVATE_API", .when(traits: ["PrivateAPI"]))`, so enabling the trait is the
//  single act that compiles the private code in.
//

import UIKit

// MARK: - The public opt-in flag

public extension ScreenGuard {
    /// The explicit, **off-by-default** opt-in gate for the private-API path.
    ///
    /// Two independent acts are required to reach `ScreenGuardNoLeakStrategy.privateSecureLayer`, and
    /// this is the second:
    ///
    /// 1. Name the strategy at the call site — `ScreenGuardShieldView(strategy: .privateSecureLayer)`.
    /// 2. Enable it here — `ScreenGuard.PrivateAPI.isEnabled = true`.
    ///
    /// Neither alone is enough. Naming the strategy does not enable it, and enabling it does not
    /// select it. That is deliberate: a private API that a stray strategy assignment could switch on
    /// is exactly the silent-failure mode this package is written to avoid.
    ///
    /// - Important: This flag only affects **runtime** gating. It does **not** change the compile-time
    ///   App Review exposure of the private class-name string, which is present in the binary whenever
    ///   `Shield/ScreenGuardPrivateSecureLayer.swift` is compiled in, regardless of this flag
    ///   (`docs/api-contract.md` §9.3). To remove the string, exclude that file (§9.4).
    ///
    /// - Warning: The private path is **non-contract, fragile across iOS releases, an App Review risk,
    ///   and never a security guarantee.** It must never be described as secure, guaranteed, safe,
    ///   recommended, production-ready, or App-Store-safe (`docs/api-contract.md` §9.5).
    enum PrivateAPI {
        /// Whether the private path is permitted to engage. Default `false`.
        ///
        /// Set it once, early, and document the App Review decision at the call site:
        ///
        /// ```swift
        /// // Requires an explicit App Review decision — see ScreenGuard.PrivateAPI.
        /// ScreenGuard.PrivateAPI.isEnabled = true
        /// let shield = ScreenGuardShieldView(strategy: .privateSecureLayer)
        /// ```
        ///
        /// Reading it also tells you whether the code is even present: when the `PrivateAPI` trait is
        /// not enabled (the default) there is no implementation, so `ScreenGuardShieldView` reports
        /// `protectionFailure = .privateSecureLayerUnavailable` and degrades to the labelled
        /// detection-and-overlay fallback however this flag is set.
        public static var isEnabled: Bool = false

        /// Whether the private-API implementation is compiled into this build.
        ///
        /// `false` unless the consumer enabled the `PrivateAPI` package trait
        /// (`docs/api-contract.md` §9.4). A host app can assert on this to prove the class-name string
        /// is not in its binary.
        @MainActor public static var isCompiledIn: Bool {
            ScreenGuardPrivateSecureLayerFactory.isCompiledIn
        }
    }
}

// MARK: - The seam

/// The behaviour `ScreenGuardShieldView` needs from the opt-in private path.
///
/// Declared separately from its implementation so the shield never names the private type, which is
/// what makes the file-exclusion escape hatch work.
///
/// - Warning: Conformances of this protocol use a private UIKit class name. See
///   `ScreenGuardPrivateSecureLayer.swift`.
@MainActor
protocol ScreenGuardPrivateSecureLayerEngaging: AnyObject {
    /// Why engagement failed, when it did.
    var failure: ScreenGuardProtectionFailure? { get }

    /// Whether the swap is currently applied.
    ///
    /// The shield's `isProtecting` / `shieldMode` are required to agree with this value — a success
    /// reported as a failure is the same honesty defect as a failure reported as a success.
    var isEngaged: Bool { get }

    /// Engages the swap for `host`.
    ///
    /// - Parameter host: The view whose content must be excluded from captures.
    /// - Returns: `true` when the swap was applied.
    func engage(on host: UIView) -> Bool

    /// Restores the host's layer arrangement. Idempotent.
    func disengage()
}

// MARK: - Teardown-safe ownership

/// Owns the engaged private-path engine and releases it when the owner is deallocated.
///
/// Not actor-isolated, for the same reason `ScreenGuardObserverTokenStore` is not: a `deinit` cannot
/// assume it is running on the main actor, and `MainActor.assumeIsolated` inside a `deinit` **traps
/// (SIGABRT)** when the last release lands off-main — reproduced in this package. So this type does
/// the same thing that store does: run the teardown synchronously when it is already on the main
/// thread, and otherwise hand it to the main queue with its own strong captures, so nothing dangles
/// while the hop is in flight.
///
/// Held by `ScreenGuardShieldView`, which means the protection a host engaged is released when the
/// shield is released — the package can promise to *undo* what it did, not only to do it.
final class ScreenGuardPrivateLayerOwner {
    private var engine: (any ScreenGuardPrivateSecureLayerEngaging)?

    /// Adopts `engine`, releasing any previously adopted one first.
    func adopt(_ engine: any ScreenGuardPrivateSecureLayerEngaging) {
        release()
        self.engine = engine
    }

    /// Whether an engaged engine is currently owned.
    ///
    /// `@MainActor` because the seam it reads is (`docs/api-contract.md` §10: every public and
    /// private-path type is main-actor isolated). The owner itself deliberately is not.
    @MainActor var isEngaged: Bool {
        engine?.isEngaged ?? false
    }

    /// Restores the arrangement now and gives up ownership. Safe to call repeatedly.
    func release() {
        guard let engine else {
            return
        }
        self.engine = nil
        Self.disengage(engine)
    }

    deinit {
        if let engine {
            Self.disengage(engine)
        }
    }

    /// Calls `disengage()` on the main actor, without assuming the current executor is main.
    private static func disengage(_ engine: any ScreenGuardPrivateSecureLayerEngaging) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { engine.disengage() }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { engine.disengage() }
            }
        }
    }
}

#if !SCREENGUARD_PRIVATE_API

/// The factory used when the private-API file has been excluded from the build.
///
/// It always returns `nil`, so the private strategy degrades to the labelled fallback exactly as
/// `docs/api-contract.md` §9.4 requires, and no private class-name string exists in the binary.
@MainActor
enum ScreenGuardPrivateSecureLayerFactory {
    /// Whether the private path is compiled into this build at all.
    static let isCompiledIn = false

    /// - Returns: Always `nil` in this configuration.
    static func make() -> (any ScreenGuardPrivateSecureLayerEngaging)? {
        nil
    }
}

#endif
