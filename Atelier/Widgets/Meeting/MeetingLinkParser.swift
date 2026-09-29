import Foundation

/// Finds a video-call join link in a calendar event's fields -- Foundation
/// only, like `CalendarMath`, so it's testable without EventKit.
///
/// Event notes can contain links from anyone who invited you, so a link is
/// only accepted when it is `https` and its host is a known provider domain
/// or a subdomain of one. `zoom.us.evil.com` and `evilzoom.us` both fail.
/// Provider set informed by leits/MeetingBar's link regexes (Apache-2.0).
enum MeetingLinkParser {
    static let providerDomains = [
        "zoom.us", "zoomgov.com",
        "meet.google.com",
        "teams.microsoft.com", "teams.live.com",
        "webex.com",
    ]

    /// Precedence: the event's `url`, then `location`, then `notes`. The first
    /// *accepted* link wins, so a non-provider `url` falls through.
    static func joinURL(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, let accepted = accept(url) { return accepted }
        for text in [location, notes] {
            if let text, let found = firstAcceptedLink(in: text) { return found }
        }
        return nil
    }

    static func accept(_ url: URL) -> URL? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        for domain in providerDomains where host == domain || host.hasSuffix("." + domain) {
            return url
        }
        return nil
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    private static func firstAcceptedLink(in text: String) -> URL? {
        let range = NSRange(text.startIndex..., in: text)
        for match in detector?.matches(in: text, range: range) ?? [] {
            if let url = match.url, let accepted = accept(url) { return accepted }
        }
        return nil
    }
}
