import SwiftUI
import AppKit

/// Текущая директория над полем ввода «хлебными крошками»: `~ / tmp / Hatch`.
/// Клик по части — папки того же уровня для перехода (как в VS Code), ⌘-клик — скопировать путь,
/// правый клик — меню папки (избранное, Finder, редактор, «Поделиться», избранные и недавние папки).
struct DirectoryBreadcrumbsView: View {
    let path: String
    let recent: [String]
    var favorites: [String] = []
    let lang: String
    var onNavigate: (String) -> Void = { _ in }
    /// «Добавить в избранное» / «Убрать из избранного» для папки из меню.
    var onToggleFavorite: (String) -> Void = { _ in }

    @State private var copied = false
    @State private var hovered: String?
    /// Часть пути, для которой открыт список папок.
    @State private var openCrumb: Int?
    /// Часть пути, для которой открыто меню папки (правый клик).
    @State private var menuCrumb: Int?

    private var font: Font { .system(size: 12) }

    var body: some View {
        Group {
            if copied {
                Label(L.t("path_copied", lang), systemImage: "checkmark")
                    .font(font)
                    .foregroundStyle(.secondary)
            } else {
                crumbs
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var crumbs: some View {
        // строка пути, как в Finder: папки с синими значками через «›»
        HStack(spacing: 4) {
            let segments = PathBreadcrumbs.segments(for: path)
            ForEach(Array(segments.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.compact.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.quaternary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Tactile.accent.opacity(0.85))
                    Text(crumb.title)
                }
                    .foregroundStyle(hovered == crumb.path ? .primary : .secondary)
                    .onHover { inside in
                        hovered = inside ? crumb.path : (hovered == crumb.path ? nil : hovered)
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            copy(crumb.path)
                        } else {
                            openCrumb = index
                        }
                    }
                    // меню и список папок — свои всплывающие окна, сплошные: системные в macOS 26 стеклянные
                    .hatchPopup(isPresented: Binding(get: { openCrumb == index },
                                                     set: { if !$0, openCrumb == index { openCrumb = nil } })) { _ in
                        PopupCard {
                            FolderPickerView(target: FolderListing.target(for: crumb),
                                             onPick: { folder in
                                                 openCrumb = nil
                                                 onNavigate(folder)
                                             })
                        }
                    }
                    .hatchPopup(isPresented: Binding(get: { menuCrumb == index },
                                                     set: { if !$0, menuCrumb == index { menuCrumb = nil } }),
                                placement: .atMouse,
                                onSecondaryClick: { openCrumb = nil; menuCrumb = index }) { context in
                        MenuCard { menu(for: crumb.path, context: context) }
                    }
                    .help(crumb.path + "\n" + L.t("crumb_hint", lang))
            }
            // текущая папка в избранном — звёздочка после пути
            if favorites.contains(path) {
                KeyIconView(icon: .starOn, size: 10)
                    .foregroundStyle(Tactile.star)
                    .help(L.t("fav_remove", lang) + " (⌘D)")
                    .onTapGesture { onToggleFavorite(path) }
            }
        }
        .font(font)
        .truncationMode(.head)
    }

    // MARK: - Меню папки

    /// Меню папки, как в макете: избранное, Finder, редактор, путь, «Поделиться…»,
    /// затем избранные и недавние папки.
    private func menu(for folder: String, context: PopupContext) -> some View {
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        let isFavorite = favorites.contains(folder)
        let close = { menuCrumb = nil }
        let go = { (dir: String) in close(); onNavigate(dir) }
        var sections: [FolderMenuView.Section] = [
            .init(items: [
                .init(title: L.t(isFavorite ? "fav_remove" : "fav_add", lang), star: isFavorite,
                      detail: folder == path ? "⌘D" : nil) { close(); onToggleFavorite(folder) },
            ]),
            .init(items: [
                .init(title: L.t("open_in_finder", lang)) { close(); NSWorkspace.shared.open(url) },
                .init(title: L.t("open_in_editor", lang), children: Self.installedEditors.map { editor in
                    .init(title: editor.name) {
                        close()
                        NSWorkspace.shared.open([url], withApplicationAt: editor.url, configuration: NSWorkspace.OpenConfiguration())
                    }
                }),
                .init(title: L.t("copy_path", lang), detail: L.t("fav_copy_hint", lang)) { close(); copy(folder) },
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
        let favoriteOthers = favorites.filter { $0 != folder }
        if !favoriteOthers.isEmpty {
            sections.append(.init(header: L.t("fav_section", lang), items: favoriteOthers.map { dir in
                .init(title: PathBreadcrumbs.folderName(for: dir), folder: true,
                      detail: Self.parentPath(dir), help: dir) { go(dir) }
            }))
        }
        let recentOthers = recent.filter { $0 != folder && !favorites.contains($0) }.prefix(Self.recentInMenu)
        if !recentOthers.isEmpty {
            sections.append(.init(header: L.t("recent_section", lang), items: recentOthers.map { dir in
                .init(title: PathBreadcrumbs.folderName(for: dir), folder: true, help: dir) { go(dir) }
            }))
        }
        return FolderMenuView(sections: sections)
    }

    /// Папка, в которой лежит избранная: подсказка справа, чтобы отличать одноимённые.
    private static func parentPath(_ dir: String) -> String {
        ShellCompletionEngine.normalizeHomePath((dir as NSString).deletingLastPathComponent)
    }

    /// Недавних в меню немного: длинный список прячет избранные и само меню.
    private static let recentInMenu = 5

    private func copy(_ folder: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(folder, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.15)) { copied = false }
        }
    }

    /// Редакторы для «Открыть в»: только установленные.
    static let installedEditors: [(name: String, url: URL)] = [
        ("Visual Studio Code", "com.microsoft.VSCode"),
        ("Cursor", "com.todesktop.230313mzl4w4u92"),
        ("Zed", "dev.zed.Zed"),
        ("Xcode", "com.apple.dt.Xcode"),
    ].compactMap { name, bundleID in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { (name, $0) }
    }
}
