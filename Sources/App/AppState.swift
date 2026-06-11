import AppKit

/// Objeto raiz que conecta as peças do app: monitor da pasta,
/// detector de canto ativo, painel flutuante e atualizador.
@MainActor
final class AppState {
    static let shared = AppState()

    let folderMonitor: FolderMonitor
    let panelController: PanelController
    let hotCorner = HotCornerMonitor()
    let updater = UpdaterManager()

    private var lastFolderPath: String

    private init() {
        let url = Prefs.folderURL
        lastFolderPath = url.path
        folderMonitor = FolderMonitor(folderURL: url)
        panelController = PanelController(folderMonitor: folderMonitor)
    }

    func start() {
        // Canto ativo alterna: abre se fechado, fecha se aberto.
        // Durante um arrasto nunca fecha — abre para receber o drop.
        hotCorner.onTrigger = { screen, corner in
            Task { @MainActor in
                let controller = AppState.shared.panelController
                let dragging = NSEvent.pressedMouseButtons != 0
                if controller.isVisible {
                    if !dragging {
                        controller.hide()
                    }
                } else {
                    controller.show(on: screen, corner: corner)
                }
            }
        }
        hotCorner.start()

        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                AppState.shared.applySettingsChanges()
            }
        }
    }

    func showPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }
        panelController.show(on: screen)
    }

    private func applySettingsChanges() {
        let url = Prefs.folderURL
        if url.path != lastFolderPath {
            lastFolderPath = url.path
            folderMonitor.update(folderURL: url)
        }
        panelController.refreshAppearance()
    }
}
