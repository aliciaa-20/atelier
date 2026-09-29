import Foundation
import Testing
@testable import Atelier

struct MeetingLinkParserTests {
    private func url(_ s: String) -> URL { URL(string: s)! }

    @Test func acceptsProviderLinkInURLField() {
        let u = url("https://us02web.zoom.us/j/123456789?pwd=abc")
        #expect(MeetingLinkParser.joinURL(url: u, location: nil, notes: nil) == u)
    }

    @Test func recognisesEachProvider() {
        for s in [
            "https://zoom.us/j/1",
            "https://meet.google.com/abc-defg-hij",
            "https://teams.microsoft.com/l/meetup-join/xyz",
            "https://teams.live.com/meet/9876",
            "https://acme.webex.com/meet/room",
        ] {
            #expect(MeetingLinkParser.accept(url(s)) != nil, "should accept \(s)")
        }
    }

    @Test func rejectsLookalikeHosts() {
        #expect(MeetingLinkParser.accept(url("https://zoom.us.evil.com/j/1")) == nil)
        #expect(MeetingLinkParser.accept(url("https://evilzoom.us/j/1")) == nil)
        #expect(MeetingLinkParser.accept(url("https://meet.google.com.evil.io/x")) == nil)
    }

    @Test func rejectsNonHTTPS() {
        #expect(MeetingLinkParser.accept(url("http://zoom.us/j/1")) == nil)
        #expect(MeetingLinkParser.accept(url("zoommtg://zoom.us/join?confno=1")) == nil)
    }

    @Test func hostMatchIsCaseInsensitive() {
        #expect(MeetingLinkParser.accept(url("https://ZOOM.US/j/1")) != nil)
    }

    @Test func precedenceIsURLThenLocationThenNotes() {
        let fromURL = url("https://zoom.us/j/1")
        let result = MeetingLinkParser.joinURL(
            url: fromURL,
            location: "https://meet.google.com/aaa-bbbb-ccc",
            notes: "https://acme.webex.com/meet/room")
        #expect(result == fromURL)

        let fromLocation = MeetingLinkParser.joinURL(
            url: nil,
            location: "https://meet.google.com/aaa-bbbb-ccc",
            notes: "https://acme.webex.com/meet/room")
        #expect(fromLocation == url("https://meet.google.com/aaa-bbbb-ccc"))
    }

    // Review Focus 2: a non-provider url must fall through, not block.
    @Test func nonProviderURLFallsThroughToNotes() {
        let result = MeetingLinkParser.joinURL(
            url: url("https://wiki.example.com/standup"),
            location: nil,
            notes: "Agenda: https://wiki.example.com/a\nJoin: https://zoom.us/j/555")
        #expect(result == url("https://zoom.us/j/555"))
    }

    @Test func picksFirstProviderLinkAmongManyInNotes() {
        let notes = "Doc https://docs.google.com/d/1 then https://teams.microsoft.com/l/meetup-join/a and https://zoom.us/j/2"
        #expect(MeetingLinkParser.joinURL(url: nil, location: nil, notes: notes)
            == url("https://teams.microsoft.com/l/meetup-join/a"))
    }

    @Test func returnsNilWhenNoProviderLink() {
        #expect(MeetingLinkParser.joinURL(url: nil, location: "Room 4B", notes: "see https://example.com") == nil)
        #expect(MeetingLinkParser.joinURL(url: nil, location: nil, notes: nil) == nil)
    }
}
