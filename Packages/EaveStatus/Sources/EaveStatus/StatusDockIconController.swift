import AppKit
import Combine

/// Draws Eave's existing status scene into its own Dock tile. Eave owns activation policy.
@MainActor
public final class StatusDockIconController {
    private let iconPresentation: IconPresentationViewModel
    private let restoreStaticIcon: () -> Void
    private let applyIcon: @MainActor (NSImage) -> Void
    private let appearance = SystemIconAppearanceMonitor()
    private let coalescer = IconRenderCoalescer()
    private var subscription: AnyCancellable?
    private var renderCache = DockIconRenderCache()
    private let images = DockIconImageCache()
    private var latestScene: IconSceneState
    private var enabled = false

    public convenience init(status: MenuBarStatusController, restoreStaticIcon: @escaping () -> Void) {
        self.init(iconPresentation: status.iconPresentation, restoreStaticIcon: restoreStaticIcon)
    }

    init(iconPresentation: IconPresentationViewModel, restoreStaticIcon: @escaping () -> Void,
         applyIcon: @escaping @MainActor (NSImage) -> Void = { NSApp.applicationIconImage = $0 }) {
        self.iconPresentation = iconPresentation
        self.restoreStaticIcon = restoreStaticIcon
        self.applyIcon = applyIcon
        latestScene = iconPresentation.output.scene
    }

    public func setEnabled(_ enabled: Bool) {
        guard self.enabled != enabled else { return }
        self.enabled = enabled
        guard enabled else {
            subscription = nil
            appearance.onChange = nil
            appearance.stop()
            coalescer.cancel()
            renderCache.reset()
            images.reset()
            restoreStaticIcon()
            return
        }

        latestScene = iconPresentation.output.scene
        render()
        subscription = iconPresentation.$output
            .map(\.scene)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] scene in
                guard let self else { return }
                latestScene = scene
                coalescer.submit { [weak self] in self?.render() }
            }
        appearance.onChange = { [weak self] _ in self?.render() }
        appearance.start()
    }

    public func stop() { setEnabled(false) }

    func flushPendingPresentationForTesting() { coalescer.flushPending() }

    private func render() {
        guard enabled else { return }
        let background = DockIconBackgroundResolver.style(
            for: .system, theme: SystemIconAppearanceReader.current(),
            isDarkAppearance: NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        )
        let key = DockIconRenderKey(scene: latestScene, backgroundStyle: background,
                                    pixelLength: DockIconRenderer.pixelSize)
        guard renderCache.needsRender(key) else { return }
        let image = images.image(for: key) ?? DockIconRenderer.image(scene: latestScene, backgroundStyle: background)
        guard let image else { return }
        images.store(image, for: key)
        renderCache.recordSuccessfulRender(key)
        applyIcon(image)
    }
}
