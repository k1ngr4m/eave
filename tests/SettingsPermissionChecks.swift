import EventKit
import UserNotifications

@main
struct SettingsPermissionChecks {
    static func main() {
        let calendarStates: [(EKAuthorizationStatus, SettingsPermissionState, Bool)] = [
            (.notDetermined, .notDetermined, true),
            (.denied, .denied, false),
            (.restricted, .restricted, false),
            (.writeOnly, .limited, true),
            (.fullAccess, .granted, false)
        ]
        for (status, expected, canRequest) in calendarStates {
            let state = SettingsPermissionState(calendar: status)
            assert(state == expected)
            assert(state.canRequest == canRequest)
        }
        let notificationStates: [(UNAuthorizationStatus, SettingsPermissionState, Bool)] = [
            (.notDetermined, .notDetermined, true),
            (.denied, .denied, false),
            (.authorized, .granted, false),
            (.provisional, .granted, false)
        ]
        for (status, expected, canRequest) in notificationStates {
            let state = SettingsPermissionState(notification: status)
            assert(state == expected)
            assert(state.canRequest == canRequest)
        }
        assert(!SettingsPermissionState.unknown.canRequest)
        // Granting one entity must not change how the other entity is presented.
        assert(SettingsPermissionState(calendar: .fullAccess) == .granted)
        assert(SettingsPermissionState(calendar: .denied) == .denied)
        print("Settings permission state checks passed")
    }
}
