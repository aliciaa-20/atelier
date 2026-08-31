import Foundation

/// Runs a fixed AppleScript source, off the main thread — `NSAppleScript` is
/// synchronous and can block for the duration of an Apple Event round trip
/// (including a first-run permission prompt), so callers must not run it on
/// the main actor.
enum AppleScriptRunner {
    static func run(_ source: String) -> String? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            print("AppleScriptRunner error: \(errorInfo)")
            return nil
        }
        return result.stringValue
    }
}
