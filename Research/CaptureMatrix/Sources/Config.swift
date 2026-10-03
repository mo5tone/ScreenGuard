import Foundation

/// Which lab to run. Selected with `-Mode matrix|feasibility|renderSanity` at launch.
enum RunMode: String {
    /// Technique x capture-path verdict matrix (the load-bearing measurement).
    case matrix
    /// Can an `AVSampleBufferDisplayLayer` with `preventsCapture = true` host arbitrary content?
    case feasibility
    /// Diagnostic: does `preventsCapture = true` stop the layer painting on screen at all?
    case renderSanity
    /// Diagnostic: why does the system capture pipeline deliver no frames?
    case replayKit
}

enum Config {
    static var arguments: [String] { ProcessInfo.processInfo.arguments }

    static func value(for key: String) -> String? {
        let args = arguments
        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static var mode: RunMode {
        RunMode(rawValue: value(for: "-Mode") ?? "matrix") ?? .matrix
    }

    static var runID: String { value(for: "-RunID") ?? "adhoc" }
}
