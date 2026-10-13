// Compile with the production driver; window contents are stubs because these
// checks exercise lifecycle callbacks without opening an application window.
import Sparkle
import SwiftUI

struct UpdateFoundView: View {
    let state: UpdateUIState
    var body: some View { EmptyView() }
}
struct UpdateNotFoundView: View {
    let state: UpdateUIState
    var body: some View { EmptyView() }
}
struct UpdateErrorView: View {
    let state: UpdateUIState
    var body: some View { EmptyView() }
}
struct UpdateProgressView: View {
    let state: UpdateUIState
    var body: some View { EmptyView() }
}

@main
struct UpdaterChecks {
    @MainActor static func main() {
        let comparator = SUStandardVersionComparator.default
        assert(comparator.compareVersion("0.1.0", toVersion: "0.1.1") == .orderedAscending)
        assert(comparator.compareVersion("0.1.0", toVersion: "0.1.0") == .orderedSame)
        assert(comparator.compareVersion("0.10.0", toVersion: "0.9.9") == .orderedDescending)

        let state = UpdateUIState()
        var installs = 0
        state.updateReply = { choice in
            assert(choice == .install)
            installs += 1
        }
        state.chooseUpdate(.install)
        state.chooseUpdate(.install)
        assert(installs == 1, "Repeated taps must not start a second installation")
        state.progress = 0.8
        state.downloadedBytes = 80
        state.totalBytes = 100
        state.releaseNotesHTML = "previous release"
        state.errorMessage = "previous failure"
        state.cancelAction = {}
        state.retryAction = {}
        state.reset()
        assert(state.progress == 0 && state.downloadedBytes == 0 && state.totalBytes == 0)
        assert(state.releaseNotesHTML == nil && state.errorMessage == nil)
        assert(state.cancelAction == nil && state.retryAction == nil && state.updateReply == nil)

        let driver = EaveUserDriver()
        driver.showReady(toInstallAndRelaunch: { choice in
            assert(choice == .install)
            installs += 1
        })
        assert(installs == 2, "Ready callback must proceed without another confirmation")
        print("Sparkle version comparison, state reset and one-click installation checks passed.")
    }
}
