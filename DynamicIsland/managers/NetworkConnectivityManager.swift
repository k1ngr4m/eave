/*
 * Atoll (DynamicIsland)
 * Copyright (C) 2024-2026 Atoll Contributors
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

import AppKit
import Combine
import EaveStatus
import Foundation

enum ConnectivityHUDState: Equatable {
    case hidden
    case noConnection
    case wifi(name: String)
    case hotspot(name: String)

    var isVisible: Bool {
        self != .hidden
    }

    var isConnectedNetwork: Bool {
        switch self {
        case .wifi, .hotspot:
            return true
        case .hidden, .noConnection:
            return false
        }
    }
}

/// Presents changes from the shared status monitor as short-lived notch HUDs.
@MainActor
final class NetworkConnectivityManager: ObservableObject {
    static let shared = NetworkConnectivityManager()

    @Published private(set) var hudState: ConnectivityHUDState = .hidden

    private var subscription: AnyCancellable?
    private var hasReceivedInitialPath = false
    private var lastConnectionSatisfied = false
    private var lastPathUsedWiFi = false
    private var lastConnectionWasHotspot = false
    private var lastWiFiName: String?
    private var noConnectionDismissed = false
    private var hideWorkItem: DispatchWorkItem?
    init() {}

    func startMonitoring(updates: AnyPublisher<MenuBarNetworkState, Never>? = nil) {
        guard subscription == nil else { return }
        let updates = updates ?? MenuBarStatusManager.shared.controller.networkPublisher
        subscription = updates.removeDuplicates().sink { [weak self] state in
            guard state.connection != .unknown else { return }
            self?.handlePathUpdate(
                isSatisfied: state.isConnected,
                usesWiFi: state.usesWiFi,
                isHotspot: state.isHotspot,
                wiFiName: state.wifiName
            )
        }
    }

    func stopMonitoring() {
        subscription?.cancel()
        subscription = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        hasReceivedInitialPath = false
        lastConnectionSatisfied = false
        lastPathUsedWiFi = false
        lastConnectionWasHotspot = false
        lastWiFiName = nil
        noConnectionDismissed = false
        hudState = .hidden
    }

    func dismissNoConnection() {
        guard hudState == .noConnection else { return }
        noConnectionDismissed = true
        hideWorkItem?.cancel()
        hideWorkItem = nil
        hudState = .hidden
    }

    func openNetworkSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.Network-Settings.extension",
            "x-apple.systempreferences:com.apple.preference.network",
        ]

        for candidate in candidates {
            guard let url = URL(string: candidate) else { continue }
            if NSWorkspace.shared.open(url) {
                break
            }
        }
    }

    private func handlePathUpdate(
        isSatisfied: Bool,
        usesWiFi: Bool,
        isHotspot: Bool,
        wiFiName: String?
    ) {
        dispatchPrecondition(condition: .onQueue(.main))

        let wasInitialUpdate = !hasReceivedInitialPath
        let shouldAnnounceWiFi = !wasInitialUpdate
            && isSatisfied
            && usesWiFi
            && (
                !lastConnectionSatisfied
                    || !lastPathUsedWiFi
                    || isHotspot != lastConnectionWasHotspot
                    || (lastWiFiName != nil && wiFiName != nil && wiFiName != lastWiFiName)
            )

        hasReceivedInitialPath = true

        if !isSatisfied {
            lastConnectionSatisfied = false
            lastPathUsedWiFi = false
            lastConnectionWasHotspot = false
            lastWiFiName = nil
            if !noConnectionDismissed {
                if hudState != .noConnection {
                    showNoConnection()
                }
            } else {
                hideWorkItem?.cancel()
                hideWorkItem = nil
                hudState = .hidden
            }
            return
        }

        noConnectionDismissed = false
        lastConnectionSatisfied = true
        lastPathUsedWiFi = usesWiFi

        if usesWiFi {
            let resolvedName = wiFiName ?? lastWiFiName
            if shouldAnnounceWiFi {
                showConnection(named: resolvedName, isHotspot: isHotspot)
            } else if wasInitialUpdate || wiFiName != nil {
                lastWiFiName = resolvedName
                lastConnectionWasHotspot = isHotspot
                if hudState == .noConnection {
                    hudState = .hidden
                } else if hudState.isConnectedNetwork, let wiFiName {
                    // A late name fills the current banner without announcing a
                    // second connection or extending its dismissal timer.
                    hudState = isHotspot ? .hotspot(name: wiFiName) : .wifi(name: wiFiName)
                }
            }
        } else {
            lastWiFiName = nil
            lastConnectionWasHotspot = false
            hideWorkItem?.cancel()
            hideWorkItem = nil
            hudState = .hidden
        }
    }

    private func showNoConnection() {
        hudState = .noConnection

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.dismissNoConnection()
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 8, execute: workItem)
    }

    private func showConnection(named name: String?, isHotspot: Bool) {
        let displayName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName: String
        if let displayName, !displayName.isEmpty {
            resolvedName = displayName
        } else {
            resolvedName = isHotspot
                ? String(localized: "Personal Hotspot")
                : String(localized: "Wi-Fi Network")
        }
        lastWiFiName = displayName
        lastConnectionWasHotspot = isHotspot
        hudState = isHotspot ? .hotspot(name: resolvedName) : .wifi(name: resolvedName)

        hideWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            guard self.hudState.isConnectedNetwork else { return }
            self.hudState = .hidden
        }
        hideWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5, execute: workItem)
    }
}
