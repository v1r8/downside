import Foundation

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let date: Date
    let size: Int64

    var id: URL { url }
}

extension FileItem {
    /// Constrói um item a partir de uma URL avulsa (itens de pilha,
    /// que não vêm do monitor de pasta).
    init(url: URL) {
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .contentModificationDateKey,
            .addedToDirectoryDateKey, .fileSizeKey,
        ]
        let values = try? url.resourceValues(forKeys: keys)
        self.init(
            url: url,
            name: url.lastPathComponent,
            isDirectory: values?.isDirectory ?? false,
            date: values?.addedToDirectoryDate ?? values?.contentModificationDate ?? Date(),
            size: Int64(values?.fileSize ?? 0)
        )
    }
}
