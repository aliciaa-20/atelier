import Foundation

/// Runs a fixed AppleScript source, off the main thread — `NSAppleScript` is
/// synchronous and can block for the duration of an Apple Event round trip
/// (including a first-run permission prompt), so callers must not run it on
/// the main actor.
enum AppleScriptRunner {
    static func run(_ source: String) -> String? {
        runDescriptor(source)?.stringValue
    }

    /// Same execution as `run(_:)`, but hands back the raw descriptor instead
    /// of coercing to a string — needed for results that aren't plain text,
    /// like an AppleScript list of mixed types or raw artwork `data`.
    static func runDescriptor(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            print("AppleScriptRunner error: \(errorInfo)")
            return nil
        }
        return result
    }
}
