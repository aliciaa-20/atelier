import Foundation

/// Short, one-line jokes for the Calendar tab, a pool per weekday in a mix
/// of tones (dry, cozy, student-chaos). Pure and static -- no network, no
/// timers. Keep each line under ~44 characters so it fits one line at the
/// tab's 11pt font; the panel reserves exactly one line for it.
enum WeekdayQuips {
    /// `weekday` is `Calendar`'s 1...7 (1 = Sunday). `seed` picks within the
    /// pool: stable for a given value, so the line doesn't flicker on
    /// re-render, but callers vary it per date and per launch.
    static func quip(forWeekday weekday: Int, seed: Int) -> String {
        let pool = lines[(weekday - 1 + 7) % 7]
        return pool[abs(seed) % pool.count]
    }

    private static let lines: [[String]] = [
        // Sunday
        [
            "Sunday scaries loading… 47%",
            "Blankets, snacks, zero obligations.",
            "Do the reading. Or don't. Tomorrow-you deals.",
            "Today's forecast: horizontal.",
            "Somewhere, a deadline is quietly waiting.",
        ],
        // Monday
        [
            "Monday. The week's opening bid.",
            "Coffee first, personality second.",
            "Fresh week, same unread emails.",
            "You can do it. Probably. After a nap.",
            "New week, new excuses. Let's go.",
        ],
        // Tuesday
        [
            "Tuesday: Monday's slightly smug sequel.",
            "Still early enough to pretend you're ahead.",
            "You're doing fine. Statistically.",
            "Hydrate, then panic. In that order.",
            "Second day, first real crisis.",
        ],
        // Wednesday
        [
            "Wednesday: the week's awkward middle child.",
            "Halfway there. Snack as a reward.",
            "Hump day. Hump gently.",
            "Peak \"why is it still Wednesday\".",
            "You're 50% done. Be proud, be tired.",
        ],
        // Thursday
        [
            "Thursday: basically Friday's understudy.",
            "One deadline closer to a nap.",
            "Almost there. Don't look at the clock.",
            "Thursday energy: hopeful, mildly haunted.",
            "Fake Friday is here. Enjoy responsibly.",
        ],
        // Friday
        [
            "Friday: you made it. Snacks are on you.",
            "Close the tabs. Close the laptop. Go.",
            "Brain has left the building.",
            "Weekend mode: 87% loaded.",
            "Be kind to yourself. Order the good food.",
        ],
        // Saturday
        [
            "Saturday: nothing is due except joy.",
            "Permission to do absolutely nothing.",
            "Sleep in. The assignments will wait.",
            "Today's agenda: vibes.",
            "Touch grass, then touch the couch.",
        ],
    ]
}
