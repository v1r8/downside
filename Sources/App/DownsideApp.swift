import SwiftUI

@main
struct DownsideApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Downside", systemImage: "tray.and.arrow.down.fill") {
            MenuBarContent()
        }

        Settings {
            SettingsView()
        }
    }
}

struct MenuBarContent: View {
    var body: some View {
        Button("Mostrar painel") {
            AppState.shared.showPanel()
        }
        .keyboardShortcut("d", modifiers: [.command, .shift])

        Divider()

        Button("Verificar atualizações…") {
            AppState.shared.updater.checkForUpdates()
        }

        SettingsLink {
            Text("Configurações…")
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button("Sair do Downside") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
    }
}
