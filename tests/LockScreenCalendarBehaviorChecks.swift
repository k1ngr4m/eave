// swiftc DynamicIsland/components/Settings/LockScreenCalendarBehavior.swift tests/LockScreenCalendarBehaviorChecks.swift -o /tmp/eave-calendar-checks && /tmp/eave-calendar-checks
@main
struct LockScreenCalendarBehaviorChecks {
    static func main() {
        // Legacy preferences may have both flags set; runtime gives entire duration priority.
        assert(LockScreenCalendarBehavior(entireDuration: true, afterStartEnabled: true) == .untilEnd)
        assert(LockScreenCalendarBehavior(entireDuration: true, afterStartEnabled: false) == .untilEnd)
        assert(LockScreenCalendarBehavior(entireDuration: false, afterStartEnabled: true) == .briefly)
        assert(LockScreenCalendarBehavior(entireDuration: false, afterStartEnabled: false) == .next)
        for behavior in LockScreenCalendarBehavior.allCases {
            assert(LockScreenCalendarBehavior(entireDuration: behavior.entireDuration,
                                               afterStartEnabled: behavior.afterStartEnabled) == behavior)
        }
        print("Lock screen calendar behavior checks passed")
    }
}
