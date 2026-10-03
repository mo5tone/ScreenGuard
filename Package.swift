// swift-tools-version: 6.1
// SPDX-License-Identifier: MIT
// ScreenGuard — keep sensitive content out of screenshots, recordings and the app-switcher snapshot.
//
//  Package.swift
//  ScreenGuard
//
//  iOS-only, zero-dependency, drop-in capture-protection package.
//
//  Build and test with `xcodebuild` ONLY. `swift build` / `swift test` resolve the macOS SDK and
//  fail with `unable to resolve module dependency: 'UIKit'` for this iOS-only package — see
//  `docs/TOOLING.md` §1.
//
//      xcodebuild build -scheme ScreenGuard \
//        -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
//        -derivedDataPath .build/dd
//
//      xcodebuild test -scheme ScreenGuard \
//        -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.2' \
//        -derivedDataPath .build/dd
//
//  Tools version is 6.1 because package traits require it (docs/api-contract.md §9.4, §13 A1).
//  The target pins `.swiftLanguageMode(.v5)` so raising the tools version does NOT force the Swift 6
//  language mode onto the source; migrating the source to Swift 6 is separate, deferred work.
//

import PackageDescription

let package = Package(
    name: "ScreenGuard",
    // iOS 15.0 is the deployment floor. No macOS / tvOS / watchOS / visionOS support is claimed or
    // tested (docs/api-contract.md §2).
    platforms: [
        .iOS(.v15)
    ],
    // NOTE: `products:` must precede `traits:` or the manifest fails to parse with
    // "argument 'products' must precede argument 'traits'".
    products: [
        // EXACTLY ONE library product, one module. A consumer writes `import ScreenGuard` and
        // nothing else (docs/api-contract.md §1 rule 1).
        .library(
            name: "ScreenGuard",
            targets: ["ScreenGuard"]
        )
    ],
    // ESCAPE HATCH — keep the private-API class name out of your binary.
    //
    // The `PrivateAPI` trait is deliberately NOT enabled by default, so the private-API code is not
    // compiled at all unless a consumer asks for it. This is consumer-actionable in one line of the
    // consumer's OWN manifest, with no fork and no second dependency:
    //
    //     .package(url: "…/ScreenGuard.git", from: "1.0.0", traits: ["PrivateAPI"])   // opt IN
    //
    // Verified: a default build contains 0 occurrences of `_UITextLayoutCanvasView` in ANY file of
    // its build products — including the generated `.swiftdoc` — and the linked binary; with the
    // trait enabled the name is present. The trait gates the code at compile time, which is what
    // matters, because App Review exposure is a COMPILE-TIME property (docs/api-contract.md §9.3) —
    // a runtime flag cannot remove a string that is already compiled in.
    //
    // Author-side note: building from a checkout (fork / vendored / CI) may additionally exclude
    // `Shield/ScreenGuardPrivateSecureLayer.swift` — but only while the trait is OFF. That mechanism
    // is NOT available to a normal SPM consumer, because `exclude:` and `swiftSettings:` exist only
    // on a package's own target declarations (docs/api-contract.md §9.4).
    traits: [
        .trait(
            name: "PrivateAPI",
            description: "Compile in the opt-in private secure-layer path. Private API: non-contract, App Review risk."
        ),
        .default(enabledTraits: [])
    ],
    // ZERO third-party dependencies. System frameworks only (docs/api-contract.md §1 rule 2).
    dependencies: [],
    targets: [
        .target(
            name: "ScreenGuard",
            path: "Sources/ScreenGuard",
            swiftSettings: [
                // Keep Swift 5 semantics: raising the tools version to 6.1 otherwise enables the
                // Swift 6 language mode, which surfaces pre-existing concurrency findings unrelated
                // to this change (docs/TOOLING.md §6.7).
                .swiftLanguageMode(.v5),
                // The ONLY thing that compiles the private-API code in.
                .define("SCREENGUARD_PRIVATE_API", .when(traits: ["PrivateAPI"]))
            ]
        ),
        .testTarget(
            name: "ScreenGuardTests",
            dependencies: ["ScreenGuard"],
            path: "Tests/ScreenGuardTests",
            swiftSettings: [
                // Same reason as the library target: keep Swift 5 semantics so raising the tools
                // version to 6.1 does not impose the Swift 6 language mode on the tests either.
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)

