import AppKit
import Combine

/// Observa uma pasta via DispatchSource (kqueue) e publica a lista de
/// arquivos ordenada do mais recente para o mais antigo.
@MainActor
final class FolderMonitor: ObservableObject {
    /// Limite de itens exibidos para manter o painel leve mesmo
    /// em pastas gigantes.
    static let displayLimit = 300

    @Published private(set) var items: [FileItem] = []
    @Published private(set) var isTruncated = false

    private(set) var folderURL: URL
    private var source: DispatchSourceFileSystemObject?
    private var pendingReload: DispatchWorkItem?

    init(folderURL: URL) {
        self.folderURL = folderURL
        startWatching()
        reload()
    }

    func update(folderURL: URL) {
        guard folderURL != self.folderURL else { return }
        stopWatching()
        self.folderURL = folderURL
        startWatching()
        reload()
    }

    func reload() {
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .contentModificationDateKey,
            .addedToDirectoryDateKey, .fileSizeKey,
        ]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        var loaded: [FileItem] = urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
            return FileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: values.isDirectory ?? false,
                date: values.addedToDirectoryDate ?? values.contentModificationDate ?? .distantPast,
                size: Int64(values.fileSize ?? 0)
            )
        }
        loaded.sort { $0.date > $1.date }

        isTruncated = loaded.count > Self.displayLimit
        items = Array(loaded.prefix(Self.displayLimit))
    }

    private func startWatching() {
        let fd = open(folderURL.path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            self?.scheduleReload()
        }
        source.setCancelHandler {
            close(fd)
        }
        source.activate()
        self.source = source
    }

    private func stopWatching() {
        source?.cancel()
        source = nil
    }

    /// Coalesce de eventos: downloads geram rajadas de notificações.
    private func scheduleReload() {
        pendingReload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.reload()
        }
        pendingReload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }
}
