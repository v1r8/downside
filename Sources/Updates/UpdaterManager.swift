import AppKit
import Sparkle

/// Encapsula o Sparkle. O feed (appcast) é publicado nos releases do
/// GitHub pelo workflow de release — ver SUFeedURL no Info.plist.
final class UpdaterManager {
    private let controller: SPUStandardUpdaterController

    var updater: SPUUpdater { controller.updater }

    init() {
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
