import AppKit
import SwiftUI
import XCTest
import EaveNetworkStats
@testable import EaveStatus

@MainActor
final class BatteryPanelAppearanceTests: XCTestCase {
    func testPanelUsesOrdinaryLabelColorsInsideVibrantPopover() throws {
        _ = NSApplication.shared
        let monitor = BatteryMonitor()
        let host = NSHostingView(rootView: BatteryPanel(monitor: monitor).environment(\.colorScheme, .dark))
        host.appearance = NSAppearance(named: .vibrantDark)
        host.frame = NSRect(origin: .zero, size: monitor.panelSize)
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(monitor.panel.isDescendant(of: host))
        XCTAssertEqual(monitor.panel.effectiveAppearance.name, .darkAqua)
        monitor.panel.effectiveAppearance.performAsCurrentDrawingAppearance {
            XCTAssertGreaterThan(NSColor.secondaryLabelColor.usingColorSpace(.deviceRGB)!.redComponent, 0.9)
        }

        host.appearance = NSAppearance(named: .vibrantLight)
        host.rootView = BatteryPanel(monitor: monitor).environment(\.colorScheme, .light)
        host.layoutSubtreeIfNeeded()
        XCTAssertEqual(monitor.panel.effectiveAppearance.name, .aqua)
    }
}
