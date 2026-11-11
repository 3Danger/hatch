import Foundation

/// Папки для дерева по клику на часть пути над полем ввода.
enum FolderListing {
    /// Вложенные папки по имени, в порядке Finder; скрытые — только по запросу.
    static func subdirectories(of path: String, includeHidden: Bool = false) -> [String] {
        let url = URL(fileURLWithPath: path, isDirectory: true)
        let options: FileManager.DirectoryEnumerationOptions = includeHidden ? [] : [.skipsHiddenFiles]
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: options)) ?? []
        return items
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}
