import SwiftUI
import EventKit

public enum SettingsPermissionState: Equatable {
    case granted, notDetermined, denied, restricted, limited, unknown

    public var title: String {
        switch self {
        case .granted: "Access Granted"
        case .notDetermined: "Not Requested"
        case .denied: "Access Required"
        case .restricted: "Restricted"
        case .limited: "Limited Access"
        case .unknown: "Checked When Used"
        }
    }

    public var canRequest: Bool { self == .notDetermined || self == .limited }
}

/// A persistent permission status and one context-appropriate action.
public struct SettingsPermissionRow: View {
    private let title: String
    private let message: String
    private let state: SettingsPermissionState
    private let request: (() -> Void)?
    private let openSettings: () -> Void

    public init(title: String, message: String, state: SettingsPermissionState,
                request: (() -> Void)? = nil, openSettings: @escaping () -> Void) {
        self.title = title
        self.message = message
        self.state = state
        self.request = request
        self.openSettings = openSettings
    }

    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state == .granted ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(state == .granted ? Color.green : Color.secondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(LocalizedStringKey(title))
                Text(LocalizedStringKey(message))
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Text(LocalizedStringKey(state.title))
                .font(.caption)
                .foregroundStyle(state == .granted ? Color.green : Color.secondary)
            Button {
                if state.canRequest, let request { request() } else { openSettings() }
            }
            label: { Text(LocalizedStringKey(state.canRequest && request != nil ? "Grant Access" : "Open System Settings")) }
            .buttonStyle(.bordered)
            .disabled(state == .restricted)
        }
        .padding(.vertical, 4)
    }
}

/// Location permission is shared by weather and Wi-Fi names.
@MainActor
public struct LocationSettingsPermissionRow: View {
    @StateObject private var permission = SettingsLocationPermission()
    private let message: String

    public init(message: String) { self.message = message }

    public var body: some View {
        SettingsPermissionRow(title: "Location", message: message, state: permission.state,
                              request: { permission.manager.requestWhenInUseAuthorization() },
                              openSettings: {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
                NSWorkspace.shared.open(url)
            }
        })
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            permission.refresh()
        }
    }
}

import CoreLocation
import AppKit

@MainActor
private final class SettingsLocationPermission: NSObject, ObservableObject, CLLocationManagerDelegate {
    let manager = CLLocationManager()
    @Published var state: SettingsPermissionState = .unknown

    override init() {
        super.init()
        manager.delegate = self
        refresh()
    }

    func refresh() {
        state = switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: .granted
        case .notDetermined: .notDetermined
        case .denied: .denied
        case .restricted: .restricted
        @unknown default: .unknown
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.refresh() }
    }
}

extension SettingsPermissionState {
    public init(calendar status: EKAuthorizationStatus) {
        switch status {
        case .authorized, .fullAccess: self = .granted
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .restricted: self = .restricted
        case .writeOnly: self = .limited
        @unknown default: self = .unknown
        }
    }
}

