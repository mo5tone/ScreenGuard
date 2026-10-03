import UIKit

/// One equal-height band per technique, plus harness controls.
///
/// Technique bands (the rows of the verdict table):
///   1 plain colour                     - control: must survive every path, or the harness is broken
///   2 AVSampleBufferDisplayLayer       - the only public iOS capture-blocking API (iOS 13+)
///   3 same layer, preventsCapture=false- control for 2
///   4 secure-layer swap                - the widely copied private trick
///   5 secure UITextField               - known-good control for the *system's* protection
///
/// Control / construction bands (never technique rows):
///   6 same view as 4 with the swap DISABLED - proves band 4's view renders when left alone, so a
///     blank band 4 means "protection", not "the private hack broke the view"
///   7 plain UITextField with the same string - proves this path can resolve text at all, so a blank
///     band 5 means "protection", not "this capture path cannot image glyphs"
///   8 AVSampleBufferDisplayLayer + opaque black shield - the construction the package would ship,
///     which converts "pixels removed" into the literal "region is black"
enum Band: Int, CaseIterable {
    case plainControl
    case sampleBufferProtected
    case sampleBufferControl
    case secureLayerSwap
    case secureTextField
    case secureLayerSwapControl
    case plainTextFieldReference
    case sampleBufferProtectedShielded

    static let secretText = "SECRET-9930"

    var title: String {
        switch self {
        case .plainControl:                  return "1 plain colour (control)"
        case .sampleBufferProtected:         return "2 AVSBDL capture=ON"
        case .sampleBufferControl:           return "3 AVSBDL capture=OFF"
        case .secureLayerSwap:               return "4 secure-layer swap"
        case .secureTextField:               return "5 secure UITextField"
        case .secureLayerSwapControl:        return "6 secure-layer swap DISABLED (control)"
        case .plainTextFieldReference:       return "7 plain UITextField (calibration)"
        case .sampleBufferProtectedShielded: return "8 AVSBDL capture=ON + black shield"
        }
    }

    var isTechnique: Bool {
        switch self {
        case .plainControl, .sampleBufferProtected, .sampleBufferControl,
             .secureLayerSwap, .secureTextField:
            return true
        default:
            return false
        }
    }

    /// What the technique itself paints. Anything else in a capture means the pixels were excluded.
    var expected: (r: Int, g: Int, b: Int) {
        switch self {
        case .plainControl:                  return (229, 25, 25)
        case .sampleBufferProtected:         return (38, 191, 64)
        case .sampleBufferControl:           return (242, 216, 25)
        case .secureLayerSwap:               return (38, 102, 242)
        case .secureTextField:               return (242, 140, 13)
        case .secureLayerSwapControl:        return (38, 102, 242)
        case .plainTextFieldReference:       return (150, 60, 200)
        case .sampleBufferProtectedShielded: return (38, 191, 64)
        }
    }

    var uiColor: UIColor {
        let e = expected
        return UIColor(red: CGFloat(e.r) / 255, green: CGFloat(e.g) / 255, blue: CGFloat(e.b) / 255, alpha: 1)
    }

    /// A text field's own background is transparent by construction, so its colour rect can only
    /// ever report whatever is *behind* the field. Its only usable signal is the text strip;
    /// emitting a colour verdict for it would be inventing a cell.
    var hasText: Bool { self == .secureTextField || self == .plainTextFieldReference }
    var hasColourSignal: Bool { !hasText }

    /// Painted underneath the technique view.
    ///
    /// This is the sentinel's whole purpose. A capture-protection mechanism can remove a layer's
    /// pixels in two very different ways: it can paint them black, or it can drop them from the
    /// composite so whatever is *behind* shows through. Only the second is dangerous, and a band
    /// whose backing matched its technique colour could not tell them apart. So the default backing
    /// is a hue no band uses (magenta 200,0,160).
    ///
    /// Band 8 deliberately overrides it with opaque black: that is the construction the package
    /// ships, and it is what turns "pixels removed" into "region is black".
    var backing: UIColor {
        self == .sampleBufferProtectedShielded ? .black : sentinelColor
    }

    var backingName: String {
        self == .sampleBufferProtectedShielded ? "opaque-black" : "sentinel-magenta"
    }

    var swapEnabled: Bool { self != .secureLayerSwapControl }
}

/// Sentinel painted behind every technique view. No band colour is anywhere near this hue.
let sentinelColor = UIColor(red: 200.0 / 255, green: 0, blue: 160.0 / 255, alpha: 1)
let sentinelRGB: (r: Int, g: Int, b: Int) = (200, 0, 160)

/// Sampling geometry, expressed as fractions of the window so the same numbers apply to every
/// capture image regardless of its pixel size (app render at 1x, ReplayKit at 3x, host screenshot).
///
/// The colour rect sits low-and-right: clear of the top-left label chip, clear of the centred text
/// strip, and clear of the home indicator that floats over the bottom of the last band. Sampling
/// through the label or the text is exactly what produced a false black in the earlier probe.
enum Geometry {
    static var bandCount: Int { Band.allCases.count }
    static func bandTopFraction(_ index: Int) -> Double { Double(index) / Double(bandCount) }
    static var bandHeightFraction: Double { 1.0 / Double(bandCount) }

    static let colorInBand = CGRect(x: 0.76, y: 0.50, width: 0.18, height: 0.22)
    static let textInBand  = CGRect(x: 0.28, y: 0.40, width: 0.44, height: 0.22)

    static func absolute(_ rect: CGRect, band index: Int) -> CGRect {
        let top = bandTopFraction(index)
        let height = bandHeightFraction
        return CGRect(
            x: rect.minX,
            y: top + rect.minY * height,
            width: rect.width,
            height: rect.height * height
        )
    }
}
