import SwiftUI
import AppKit

/// Текущая директория над полем ввода «хлебными крошками»: `~ / tmp / Hatch`.
/// Клик по части или ⌘1 — дерево папок (как хлебные крошки VS Code), ⌘-клик — скопировать путь,
/// правый клик — меню папки (избранное, Finder, редактор, «Поделиться», избранные и недавние папки).
struct DirectoryBreadcrumbsView: View {
    let path: String
    let recent: [String]
    var favorites: [String] = []
    let lang: String
    var onNavigate: (String) -> Void = { _ in }
    /// «Добавить в избранное» / «Убрать из избранного» для папки из меню.
    var onToggleFavorite: (String) -> Void = { _ in }
    /// Каждое увеличение — ⌘1: дерево у текущей (последней) папки, повторно — закрыть.
    var treeRequest = 0

    @State private var copied = false
    @State private var hovered: String?
    /// Часть пути, для которой открыт список папок.
    @State private var openCrumb: Int?
    /// Часть пути, для которой открыто меню папки (правый клик).
    @State private var menuCrumb: Int?
    /// Папка, к которой сейчас относится открытое дерево (после ← на верху — уровнем выше).
    @State private var treeCrumb: String?
    /// Растёт при каждом открытии дерева: ⌘→ обратно к той же папке пути (после ← дерево ушло
    /// выше) открывает дерево заново, а не оставляет его уровнем выше в том же окне.
    @State private var treeGeneration = 0

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
        .onChange(of: treeRequest) { _, _ in
            let last = PathBreadcrumbs.segments(for: path).count - 1
            openTree(openCrumb == last ? nil : last)
        }
        // перешли в другую папку — дерево закрывается
        .onChange(of: path) { _, _ in openTree(nil) }
    }

    /// ⌘←/⌘→: дерево соседней папки пути. Соседи считаются от папки, к которой дерево относится
    /// сейчас: после ← на верхнем уровне это уже папка выше, а не та, у которой дерево открыли.
    private func switchTree(by delta: Int, from opened: Int) {
        let segments = PathBreadcrumbs.segments(for: path)
        let current = Self.treeIndex(of: treeCrumb, in: segments.map(\.path)) ?? opened
        let target = min(max(current + delta, 0), segments.count - 1)
        if target != current || treeCrumb != segments[target].path { openTree(target) }
    }

    /// Место папки дерева в пути. Дерево могло подняться выше начала пути (выше `~`) —
    /// тогда это «левее первой», и ⌘→ ведёт к первой папке пути.
    static func treeIndex(of crumb: String?, in paths: [String]) -> Int? {
        guard let crumb else { return nil }
        if let index = paths.firstIndex(of: crumb) { return index }
        if let first = paths.first, first.hasPrefix(crumb == "/" ? "/" : crumb + "/") { return -1 }
        return nil
    }

    private func openTree(_ index: Int?) {
        let segments = PathBreadcrumbs.segments(for: path)
        menuCrumb = nil
        openCrumb = index
        treeGeneration += 1
        treeCrumb = index.flatMap { segments.indices.contains($0) ? segments[$0].path : nil }
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
                let lit = openCrumb != nil && treeCrumb == crumb.path
                HStack(spacing: 4) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(Tactile.accent.opacity(0.85))
                    Text(crumb.title)
                }
                    .foregroundStyle(lit || hovered == crumb.path ? .primary : .secondary)
                    // папка, к которой относится открытое дерево, подсвечена
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(lit ? Tactile.accent.opacity(0.25) : .clear,
                                in: RoundedRectangle(cornerRadius: 5, style: .circular))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .circular)
                        .strokeBorder(lit ? Tactile.accent.opacity(0.6) : .clear))
                    .padding(.horizontal, -4)
                    .onHover { inside in
                        hovered = inside ? crumb.path : (hovered == crumb.path ? nil : hovered)
                        if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                    }
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            copy(crumb.path)
                        } else {
                            openTree(openCrumb == index ? nil : index)
                        }
                    }
                    // меню и список папок — свои всплывающие окна, сплошные: системные в macOS 26 стеклянные
                    .hatchPopup(isPresented: Binding(get: { openCrumb == index },
                                                     set: { if !$0, openCrumb == index { openTree(nil) } })) { _ in
                        PopupCard {
                            FolderTreeView(crumb: crumb.path, currentDirectory: path, lang: lang,
                                           favorites: favorites, onToggleFavorite: onToggleFavorite,
                                           onNavigate: { folder in
                                               openTree(nil)
                                               onNavigate(folder)
                                           },
                                           onSwitchCrumb: { delta in switchTree(by: delta, from: index) },
                                           onCrumbChange: { treeCrumb = $0 })
                            .id(treeGeneration)
                        }
                    }
                    .hatchPopup(isPresented: Binding(get: { menuCrumb == index },
                                                     set: { if !$0, menuCrumb == index { menuCrumb = nil } }),
                                placement: .atMouse,
                                onSecondaryClick: { openTree(nil); menuCrumb = index }) { context in
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

    /// Меню папки: общие действия с папкой (FolderActions), затем избранные и недавние папки.
    private func menu(for folder: String, context: PopupContext) -> some View {
        let close = { menuCrumb = nil }
        let go = { (dir: String) in close(); onNavigate(dir) }
        var sections = FolderActions.sections(for: folder, currentDirectory: path, favorites: favorites, lang: lang,
                                              context: context, close: close, onToggleFavorite: onToggleFavorite,
                                              onCopied: showCopied)
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
        FolderActions.copyPath(folder)
        showCopied()
    }

    /// «Путь скопирован» на месте пути — на секунду.
    private func showCopied() {
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.15)) { copied = false }
        }
    }
}
