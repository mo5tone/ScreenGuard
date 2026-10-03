//
//  ScreenGuardShieldRegressionTests+PixelRead.swift
//  ScreenGuard
//
//  The ordinary layer-tree pixel read, and the private-API trait gate.
//
//  Split out of ScreenGuardShieldRegressionTests.swift to keep that file (and its class body) inside
//  the size limits. The tests are the same tests: an extension adds methods to the same XCTestCase
//  subclass, so the executed test count is unchanged.
//

@testable import ScreenGuard
import UIKit
import XCTest

extension ScreenGuardShieldRegressionTests {
    // MARK: - Ordinary layer-tree pixel read

    /// Renders a view's ordinary layer tree, the way `ScreenGuardDeviceOnlyTests` does.
    static func render(_ view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { context in
            view.layer.render(in: context.cgContext)
        }
    }

    /// One normalised sample as `(r, g, b)` in 0...255, normalised to RGBA8 first: the renderer's
    /// output is 16 bpc, so a raw byte read yields noise (`docs/TOOLING.md` §5).
    static func pixel(in image: UIImage, at normalizedPoint: CGPoint) -> (Int, Int, Int)? {
        guard let cgImage = image.cgImage else {
            return nil
        }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else {
            return nil
        }
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = bytes.withUnsafeMutableBytes({ buffer -> CGContext? in
            CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }) else {
            return nil
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let x = min(width - 1, max(0, Int(normalizedPoint.x * CGFloat(width))))
        let y = min(height - 1, max(0, Int(normalizedPoint.y * CGFloat(height))))
        let offset = (y * width + x) * 4
        return (Int(bytes[offset]), Int(bytes[offset + 1]), Int(bytes[offset + 2]))
    }

    static func components(_ color: UIColor) -> (Int, Int, Int) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    static func channelDistance(_ lhs: (Int, Int, Int), _ rhs: (Int, Int, Int)) -> Int {
        max(abs(lhs.0 - rhs.0), max(abs(lhs.1 - rhs.1), abs(lhs.2 - rhs.2)))
    }

    // MARK: - Trait gate

    /// Skips with the documented reason when the private-API code is not compiled into this build.
    func requirePrivateTrait() throws {
        guard ScreenGuard.PrivateAPI.isCompiledIn else {
            throw XCTSkip(Self.privateTraitReason)
        }
    }
}
