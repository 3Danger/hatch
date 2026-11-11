import Foundation

/// Папки для списка по клику на часть пути над полем ввода.
enum FolderListing {
    /// Какую папку перечислить и какую в ней подсветить.
    struct Target: Equatable {
        let directory: String
        let highlighted: String?
    }

    /// Как в строке пути VS Code: папки того же уровня, кликнутая выделена.
    /// У корня соседей нет — показываем его вложенные папки.
    static func target(for crumb: PathBreadcrumbs.Crumb) -> Target {
        guard crumb.path != "/" else { return Target(directory: "/", highlighted: nil) }
        let url = URL(fileURLWithPath: crumb.path)
        return Target(directory: url.deletingLastPathComponent().path, highlighted: url.lastPathComponent)
    }

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
