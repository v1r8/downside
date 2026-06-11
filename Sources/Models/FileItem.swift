import Foundation

struct FileItem: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let date: Date
    let size: Int64

    var id: URL { url }
}
