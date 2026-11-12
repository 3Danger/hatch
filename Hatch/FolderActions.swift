import AppKit

/// Действия с папкой — общие для меню пути над полем ввода и меню папки в дереве:
/// избранное, Finder, редактор, путь, «Поделиться…». Новый пункт появляется в обоих меню сразу.
enum FolderActions {
    /// Две группы пунктов для папки.
    /// - Parameters:
    ///   - currentDirectory: текущая папка Hatch — у неё к «В избранное» подписано ⌘D;
    ///   - close: закрыть меню (вызывается перед действием);
    ///   - onCopied: путь уже в буфере — показать, что скопирован.
    static func sections(for folder: String, currentDirectory: String, favorites: [String], lang: String,
                         context: PopupContext, close: @escaping () -> Void,
                         onToggleFavorite: @escaping (String) -> Void,
                         onCopied: @escaping () -> Void) -> [FolderMenuView.Section] {
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        let isFavorite = favorites.contains(folder)
        return [
            .init(items: [
                .init(title: L.t(isFavorite ? "fav_remove" : "fav_add", lang), star: isFavorite,
                      detail: folder == currentDirectory ? "⌘D" : nil) { close(); onToggleFavorite(folder) },
            ]),
            .init(items: [
                .init(title: L.t("open_in_finder", lang)) { close(); NSWorkspace.shared.open(url) },
                .init(title: L.t("open_in_editor", lang), children: installedEditors.map { editor in
                    .init(title: editor.name) {
                        close()
                        NSWorkspace.shared.open([url], withApplicationAt: editor.url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }),
                .init(title: L.t("copy_path", lang), detail: L.t("fav_copy_hint", lang)) {
                    close(); copyPath(folder); onCopied()
                },
                .init(title: L.t("share", lang)) {
                    let anchor = context.anchorView
                    close()
                    // системное окно «Поделиться» (его вид задаёт macOS)
                    DispatchQueue.main.async {
                        NSSharingServicePicker(items: [url]).show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
                    }
                },
            ]),
        ]
    }

    static func copyPath(_ folder: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(folder, forType: .string)
    }

    /// Редакторы для «Открыть в редакторе»: только установленные.
    static let installedEditors: [(name: String, url: URL)] = [
        ("Visual Studio Code", "com.microsoft.VSCode"),
        ("Cursor", "com.todesktop.230313mzl4w4u92"),
        ("Zed", "dev.zed.Zed"),
        ("Xcode", "com.apple.dt.Xcode"),
    ].compactMap { name, bundleID in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { (name, $0) }
    }
}
