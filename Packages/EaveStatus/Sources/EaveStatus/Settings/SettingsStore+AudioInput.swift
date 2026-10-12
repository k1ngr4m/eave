import Foundation

extension SettingsStore {
    /// Phase 1 forcibly hid input controls; offer them once, then preserve the user's choice.
    func introduceAudioInputSection(defaults: UserDefaults) {
        let key = "eave.audioInputSectionIntroduced.v1"
        guard !defaults.bool(forKey: key) else { return }
        setPopupSection(.audioInput, enabled: true)
        defaults.set(true, forKey: key)
    }
}
