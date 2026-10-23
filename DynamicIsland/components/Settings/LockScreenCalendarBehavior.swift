/// The three existing combinations of the lock-screen calendar preferences.
enum LockScreenCalendarBehavior: String, CaseIterable {
    case untilEnd = "Keep until the event ends"
    case briefly = "Keep for a while"
    case next = "Switch to the next event"

    init(entireDuration: Bool, afterStartEnabled: Bool) {
        self = entireDuration ? .untilEnd : (afterStartEnabled ? .briefly : .next)
    }

    var entireDuration: Bool { self == .untilEnd }
    var afterStartEnabled: Bool { self == .briefly }
}
