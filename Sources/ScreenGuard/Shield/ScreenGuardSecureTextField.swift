//
//  ScreenGuardSecureTextField.swift
//  ScreenGuard
//
//  The one measured, public, unconfounded no-leak primitive. See docs/api-contract.md §3.2.1 / §6.5.
//
//  MEASURED (docs/evidence/capability-matrix.md §3 row 5, with the row 7 calibration control):
//  a `UITextField` with `isSecureTextEntry = true` produced TEXT-BLANKED 0/1068 dark pixels in
//  `drawHierarchy` while the same field's dots were visible on the display (19.02% dark). The
//  plain-field calibration band proves that path CAN image text (205/1068), so the blank is
//  protection and not an inability to resolve glyphs.
//
//  SCOPE LIMIT — it protects THE FIELD'S OWN TEXT ONLY, never other views. It is not a
//  general-purpose shield and must not be presented as one. It also MASKS ON SCREEN: the user sees
//  dots, not the real value. It is therefore suitable for secrets the user ENTERS (PIN, password,
//  one-time code) — NOT for displaying an account number the user must read.
//
//  No networking, no telemetry. The text never leaves the process through this class.
//

import UIKit

/// A `UITextField` hardened for secrets the user **enters** (PIN, password, one-time code).
///
/// This is the only mechanism in the package that is simultaneously public API, measured, and
/// unconfounded: its text is blanked in the app-side capture path while the field's dots remain
/// visible on the display.
///
/// ```swift
/// let pin = ScreenGuardSecureTextField()
/// pin.placeholder = "PIN"
/// pin.keyboardType = .numberPad
/// pin.onTextChanged = { audit.log("pin length \($0.count)") }
/// ```
///
/// - Important: SCOPE LIMIT — it protects **the field's own text only**, never other views, and the
///   on-screen presentation is masked (dots). Do not use it to display a value the user must read.
///   For a value the user must read, use `ScreenGuardShieldView`, and read its documented status
///   first: the public path is device-pending.
///
/// iOS 15-compatible — no availability guard is required.
@MainActor
open class ScreenGuardSecureTextField: UITextField {
    // MARK: - Secure entry

    /// Enforced `true`. Assigning `false` is ignored; use a plain `UITextField` if you need that.
    ///
    /// This is enforced rather than merely defaulted because silently allowing a caller to turn the
    /// protection off is exactly the "silent failure" this package is written to avoid. The refusal is
    /// recorded in `refusedInsecureEntryAttempts` so a caller (and the package's own tests) can prove
    /// the assignment did not take effect, instead of having to trust it.
    override public var isSecureTextEntry: Bool {
        get { super.isSecureTextEntry }
        set {
            guard newValue else {
                refusedInsecureEntryAttempts += 1
                return
            }
            super.isSecureTextEntry = true
        }
    }

    /// How many times a caller tried to set `isSecureTextEntry = false` and was refused.
    ///
    /// Non-zero means a call site believes it disabled capture protection when it did not — worth
    /// asserting on in a host app's own tests.
    public private(set) var refusedInsecureEntryAttempts: Int = 0

    // MARK: - Copy protection

    /// When `true` (default), copy / cut / paste / selection menus and the text-selection loupe are
    /// disabled, so the secret cannot be exfiltrated through the editing UI.
    ///
    /// A secure field already excludes its text from captures; this closes the separate,
    /// user-driven route of copying the value out by hand. It is read dynamically by
    /// `canPerformAction(_:withSender:)`, so toggling it takes effect immediately with no re-wiring.
    public var isCopyProtected: Bool = true

    // MARK: - Change observation

    /// Called on the main actor whenever the field's text changes.
    ///
    /// The text is passed as an argument rather than read back from `text` so a caller cannot
    /// accidentally retain it by capturing the field.
    ///
    /// The callback is driven by UIKit's own text-change notifications rather than by the
    /// `.editingChanged` control action. Measured: a `UITextField` that is not in a window and is not
    /// first responder fires **no** `.editingChanged` action — not even a plain `UITextField` with a
    /// test-owned target does, so `sendActions(for: .editingChanged)` is not a usable seam. UIKit
    /// posts `textDidChangeNotification` on every text mutation, including programmatic ones, which is
    /// both the reliable route and the one that matches what a caller means by "the text changed".
    public var onTextChanged: ((String) -> Void)?

    // MARK: - Init

    /// Creates a hardened secure field.
    ///
    /// - Parameter frame: The initial frame.
    override public init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    /// Creates a hardened secure field from a nib or storyboard.
    ///
    /// - Parameter coder: The decoder.
    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        super.isSecureTextEntry = true
        autocorrectionType = .no
        autocapitalizationType = .none
        spellCheckingType = .no
        smartDashesType = .no
        smartQuotesType = .no
        textContentType = .password
        // UIKit posts this for every text mutation, programmatic or user-driven. The `.editingChanged`
        // control action does not fire for a field that is not first responder, so it is not usable.
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleTextDidChange),
            name: UITextField.textDidChangeNotification,
            object: self
        )
    }

    @objc
    private func handleTextDidChange() {
        onTextChanged?(text ?? "")
    }

    // MARK: - UIResponder

    /// Suppresses copy / cut / paste / selection while `isCopyProtected` is `true`.
    ///
    /// - Parameters:
    ///   - action: The action being queried.
    ///   - sender: The sender of the action.
    /// - Returns: `false` for editing actions when copy protection is on.
    override public func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        guard isCopyProtected else {
            return super.canPerformAction(action, withSender: sender)
        }
        return false
    }
}
