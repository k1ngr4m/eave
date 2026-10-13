"""Run: python3 tests/test_monitoring_shortcut.py (requires swiftc)."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
app = (root / "DynamicIsland/DynamicIslandApp.swift").read_text()
handler = app.split("        KeyboardShortcuts.onKeyDown(for: .openMonitoring)", 1)[1]
handler = "KeyboardShortcuts.onKeyDown(for: .openMonitoring)" + handler.split("\n\n        KeyboardShortcuts.", 1)[0]

source = r'''
import Foundation
import CoreGraphics
enum Key { case enableShortcuts, enableStatsFeature, showOnAllDisplays }
enum Defaults {
    static var values: [Key: Bool] = [:]
    static subscript(key: Key) -> Bool { values[key] ?? false }
}
struct NSScreen: Hashable {
    let frame: CGRect
    static let screens = [NSScreen(frame: CGRect(x: 0, y: 0, width: 100, height: 100))]
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.frame == rhs.frame }
    func hash(into hasher: inout Hasher) { hasher.combine(frame.origin.x) }
}
enum NSEvent { static let mouseLocation = CGPoint(x: 50, y: 50) }
enum Tab { case home, stats }
final class Coordinator { var currentView = Tab.home }
final class ViewModel {
    enum State { case closed, open }
    var notchState = State.closed
    let coordinator: Coordinator
    init(_ coordinator: Coordinator) { self.coordinator = coordinator }
    func open(target: Tab) { notchState = .open; coordinator.currentView = target }
}
enum KeyboardShortcuts {
    enum Name { case openMonitoring }
    static var handler: (() -> Void)?
    static func onKeyDown(for name: Name, action: @escaping () -> Void) { handler = action }
}
final class Harness {
    let coordinator = Coordinator()
    lazy var vm = ViewModel(coordinator)
    lazy var screenVM = ViewModel(coordinator)
    lazy var viewModels = [NSScreen.screens[0]: screenVM]
    var autoClosePending = true
    func cancelPendingNotchAutoClose() { autoClosePending = false }
    func register() {
''' + handler + r'''
    }
}
for shortcuts in [false, true] {
    for monitoring in [false, true] {
        for multipleDisplays in [false, true] {
            for alreadyOpen in [false, true] {
                let app = Harness()
                Defaults.values = [.enableShortcuts: shortcuts, .enableStatsFeature: monitoring,
                                   .showOnAllDisplays: multipleDisplays]
                let target = multipleDisplays ? app.screenVM : app.vm
                target.notchState = alreadyOpen ? .open : .closed
                app.register()
                KeyboardShortcuts.handler!()
                let enabled = shortcuts && monitoring
                assert(app.coordinator.currentView == (enabled ? .stats : .home))
                assert(target.notchState == (enabled || alreadyOpen ? .open : .closed))
                assert(app.autoClosePending == !enabled)
                if multipleDisplays { assert(app.vm.notchState == .closed) }
                KeyboardShortcuts.handler!()
                assert(target.notchState == (enabled || alreadyOpen ? .open : .closed))
            }
        }
    }
}
print("Monitoring shortcut: feature gates, display routing, opening and repeated presses passed.")
'''
with tempfile.TemporaryDirectory() as directory:
    main = Path(directory) / "main.swift"
    main.write_text(source)
    binary = Path(directory) / "check"
    subprocess.run(["swiftc", str(main), "-o", str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
