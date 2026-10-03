import Foundation
import ImageIO
import os
import UIKit
import UniformTypeIdentifiers

/// Writes every raw measurement line to two places at once: the unified log (`os.Logger`) and a
/// plain-text file in the app's Documents directory, which the host script pulls out of the
/// simulator container with `simctl get_app_container`. The file is what the evidence doc quotes.
final class RunLog: @unchecked Sendable {
    static let shared = RunLog()

    private let logger = Logger(subsystem: "com.screenguard.capturematrix", category: "matrix")
    private let lock = NSLock()
    private var lines: [String] = []

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    func log(_ message: String) {
        logger.notice("\(message, privacy: .public)")
        lock.lock()
        lines.append(message)
        lock.unlock()
    }

    var text: String {
        lock.lock()
        defer { lock.unlock() }
        return lines.joined(separator: "\n")
    }

    @discardableResult
    func writeText(_ name: String) -> URL {
        let url = Self.documents.appendingPathComponent(name)
        try? (text + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    func writePNG(_ image: UIImage, name: String) -> URL? {
        guard let data = image.pngData() else {
            return nil
        }
        let url = Self.documents.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            log("ERROR writing \(name): \(error.localizedDescription)")
            return nil
        }
    }

    /// Writes a `CGImage` as PNG tagged **sRGB**.
    ///
    /// This matters more than it looks. `UIGraphicsImageRenderer` and the layer render both produce
    /// bitmaps in the display's colour space (Display P3 on these devices). `UIImage.pngData()`
    /// carries that profile into the file, so an independent reader that ignores the ICC profile
    /// (or that naively assumes sRGB) sees saturated colours shifted by 20-40 per channel - enough
    /// to flip a verdict. Writing the already-sRGB-normalised image with an explicit sRGB profile
    /// makes the file agree with the in-app analyzer and with any host tool.
    @discardableResult
    func writePNG(_ image: CGImage, name: String) -> URL? {
        let url = Self.documents.appendingPathComponent(name)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL, "public.png" as CFString, 1, nil
        ) else {
            log("ERROR creating PNG destination for \(name)")
            return nil
        }
        let properties: [CFString: Any] = [
            kCGImagePropertyColorModel: kCGImagePropertyColorModelRGB,
            kCGImagePropertyProfileName: "sRGB IEC61966-2.1",
            kCGImageDestinationLossyCompressionQuality: 1.0,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            log("ERROR finalising PNG \(name)")
            return nil
        }
        return url
    }

    @discardableResult
    func writeJSON(_ object: [String: Any], name: String) -> URL? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else {
            return nil
        }
        let url = Self.documents.appendingPathComponent(name)
        do {
            try data.write(to: url)
            return url
        } catch {
            log("ERROR writing \(name): \(error.localizedDescription)")
            return nil
        }
    }
}

/// Wall-clock and CPU helpers. `task_info` is the only public in-process cost source on iOS.
enum Stats {
    static func now() -> Double {
        Double(DispatchTime.now().uptimeNanoseconds) / 1e9
    }

    /// Cumulative CPU seconds (user + system) burned by this process.
    static func cpuSeconds() -> Double {
        var info = task_absolutetime_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_absolutetime_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_ABSOLUTETIME_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return -1
        }
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        let numer = Double(timebase.numer)
        let denom = Double(timebase.denom)
        return (Double(info.total_user) * numer / denom + Double(info.total_system) * numer / denom) / 1e9
    }

    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return -1
        }
        return Double(info.phys_footprint) / 1024 / 1024
    }

    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard !sorted.isEmpty else {
            return -1
        }
        let index = min(sorted.count - 1, max(0, Int((Double(sorted.count - 1) * fraction).rounded())))
        return sorted[index]
    }

    static func fmt(_ value: Double, _ decimals: Int = 2) -> String {
        String(format: "%.\(decimals)f", value)
    }
}
