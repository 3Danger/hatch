import SwiftUI
import AppKit

/// Текущая директория над полем ввода «хлебными крошками»: `~ / tmp / Hatch`.
/// Клик по части — папки того же уровня для перехода (как в VS Code), ⌘-клик — скопировать путь,
/// правый клик — меню папки (Finder, редактор, «Поделиться», недавние папки).
struct DirectoryBreadcrumbsView: View {
    let path: String
    let recent: [String]
    let lang: String
    var onNavigate: (String) -> Void = { _ in }

    @State private var copied = false
    @State private var hovered: String?
    /// Часть пути, для которой открыт список папок.
    @State private var openCrumb: Int?

    private var font: Font { .system(size: 11, weight: .medium, design: .monospaced) }

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
        HStack(spacing: 3) {
            let segments = PathBreadcrumbs.segments(for: path)
            ForEach(Array(segments.enumerated()), id: \.offset) { index, crumb in
                if index > 0 && segments[index - 1].title != "/" {
                    Text("/").foregroundStyle(.quaternary)
                }
                Text(crumb.title)
                    .foregroundStyle(hovered == crumb.path ? .secondary : .tertiary)
                    .underline(hovered == crumb.path)
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
                    .contextMenu { menu(for: crumb.path) }
                    .popover(isPresented: Binding(get: { openCrumb == index },
                                                  set: { if !$0, openCrumb == index { openCrumb = nil } }),
                             arrowEdge: .bottom) {
                        FolderPickerView(target: FolderListing.target(for: crumb),
                                         onPick: { folder in
                                             openCrumb = nil
                                             onNavigate(folder)
                                         })
                    }
                    .help(crumb.path + "\n" + L.t("crumb_hint", lang))
            }
        }
        .font(font)
        .truncationMode(.head)
    }

    // MARK: - Меню папки

    @ViewBuilder
    private func menu(for folder: String) -> some View {
        let url = URL(fileURLWithPath: folder, isDirectory: true)
        Button(L.t("copy_path", lang)) { copy(folder) }
        Button(L.t("open_in_finder", lang)) { NSWorkspace.shared.open(url) }
        let editors = Self.installedEditors
        if !editors.isEmpty {
            Menu(L.t("open_in", lang)) {
                ForEach(editors, id: \.name) { editor in
                    Button(editor.name) {
                        NSWorkspace.shared.open([url], withApplicationAt: editor.url,
                                                configuration: NSWorkspace.OpenConfiguration())
                    }
                }
            }
        }
        ShareLink(item: url) { Text(L.t("share", lang)) }
        let others = recent.filter { $0 != path }
        if !others.isEmpty {
            Divider()
            Menu(L.t("recent_dirs", lang)) {
                ForEach(others, id: \.self) { dir in
                    Button(ShellCompletionEngine.normalizeHomePath(dir)) { onNavigate(dir) }
                }
            }
        }
    }

    private func copy(_ folder: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(folder, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.15)) { copied = false }
        }
    }

    /// Редакторы для «Открыть в»: только установленные.
    private static let installedEditors: [(name: String, url: URL)] = [
        ("Visual Studio Code", "com.microsoft.VSCode"),
        ("Cursor", "com.todesktop.230313mzl4w4u92"),
        ("Zed", "dev.zed.Zed"),
        ("Xcode", "com.apple.dt.Xcode"),
    ].compactMap { name, bundleID in
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map { (name, $0) }
    }
}
