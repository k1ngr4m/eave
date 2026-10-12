// Adapted from Status Trio tests for Eave (2026-10-12), Apache-2.0.
import AppKit
import CoreGraphics
@testable import EaveStatus

/// Domain fixtures for raster tests that assert independent geometry or color
/// conventions. Product mapping is still exercised through the canonical mapper;
/// these helpers contain no selection or drawing rules.
@MainActor
func renderMenuBarFixture(
    snapshot: StatusSnapshot,
    size: CGFloat,
    scale: CGFloat,
    foreground: CGColor,
    criticalColor: CGColor? = nil,
    options: BatteryIconOptions = .standard,
    connectionOptions: ConnectionIconOptions = .standard,
    volumeOptions: VolumeIconOptions = .standard,
    bluetoothAudioOptions: BluetoothAudioIconOptions = .standard,
    inputs: IconPresentationInputs? = nil,
    phase: ChargingEffectPhase? = nil
) -> CGImage? {
    let configuration = IconPresentationConfiguration(
        battery: options,
        connection: connectionOptions,
        volume: volumeOptions,
        bluetooth: bluetoothAudioOptions
    )
    let resolvedInputs = inputs ?? IconPresentationResourceResolver.inputs(snapshot: snapshot)
    let scene = IconPresentationMapper.scene(inputs: resolvedInputs, configuration: configuration)
    return StatusIconRenderer.render(
        scene: scene,
        environment: StatusIconRenderEnvironment(
            size: size,
            scale: scale,
            foreground: foreground,
            criticalColor: criticalColor ?? StatusIconRenderer.defaultCriticalColor
        ),
        phase: phase
    )
}
