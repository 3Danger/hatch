import SwiftUI
import AppKit

/// Дерево папок у папки пути (клик по ней или ⌘T): соседи папки, она выделена.
/// ↑/↓ — по строкам, → — раскрыть и войти, ← — свернуть, к родителю, на верху — уровнем выше,
/// Space — свернуть/развернуть, буквы — фильтр (Backspace стирает, Esc очищает), Enter — перейти (как `cd`),
/// ⌘←/⌘→ — дерево соседней папки пути, Esc — закрыть. Клик по имени — перейти, по шеврону — раскрыть,
/// ⌘-клик — скопировать путь, правый клик — меню папки (те же действия, что в меню пути, FolderActions).
struct FolderTreeView: View {
    let currentDirectory: String
    let lang: String
    var favorites: [String] = []
    var onToggleFavorite: (String) -> Void = { _ in }
    var onNavigate: (String) -> Void = { _ in }
    /// ⌘←/⌘→: открыть дерево соседней папки пути (−1 — левее, +1 — правее).
    var onSwitchCrumb: (Int) -> Void = { _ in }
    /// Дерево поднялось уровнем выше — в пути подсвечивается эта папка.
    var onCrumbChange: (String) -> Void = { _ in }

    @State private var tree: FolderTree
    @State private var listing = Listing()
    /// Строка под курсором: по ней правый клик открывает меню.
    @State private var hoveredRow: String?
    /// Папка, для которой открыто меню.
    @State private var menuRow: String?
    @State private var copied = false
    @FocusState private var focused: Bool

    private static let rowHeight: CGFloat = 26
    private static let rowSpacing: CGFloat = 1
    private static let maxHeight: CGFloat = 320
    /// Отступ строк от края карточки: скругление строки + отступ = скругление карточки (14).
    private static let padding: CGFloat = 6
    private static let rowRadius: CGFloat = 8

    init(crumb: String, currentDirectory: String, lang: String,
         favorites: [String] = [], onToggleFavorite: @escaping (String) -> Void = { _ in },
         onNavigate: @escaping (String) -> Void = { _ in },
         onSwitchCrumb: @escaping (Int) -> Void = { _ in },
         onCrumbChange: @escaping (String) -> Void = { _ in }) {
        self.currentDirectory = currentDirectory
        self.lang = lang
        self.favorites = favorites
        self.onToggleFavorite = onToggleFavorite
        self.onNavigate = onNavigate
        self.onSwitchCrumb = onSwitchCrumb
        self.onCrumbChange = onCrumbChange
        _tree = State(initialValue: FolderTree(crumb: crumb))
    }

    /// Папки читаются с диска один раз за показ дерева.
    final class Listing {
        private var cache: [String: [String]] = [:]
        func children(_ path: String) -> [String] {
            if let cached = cache[path] { return cached }
            let names = FolderListing.subdirectories(of: path)
            cache[path] = names
            return names
        }
    }

    private var rows: [FolderTree.VisibleRow] { tree.visibleRows(listing.children) }

    /// По числу строк, дальше — прокрутка; без явной высоты окно схлопывается в полоску.
    private var listHeight: CGFloat {
        let content = CGFloat(max(rows.count, 1)) * (Self.rowHeight + Self.rowSpacing) + Self.padding * 2
        return min(content, Self.maxHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            list
            footer
        }
        .frame(width: 340)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        // удержание стрелки — повторы, как в Finder: строки листаются подряд
        .onKeyPress(phases: [.down, .repeat]) { press in handle(press) }
        .onChange(of: tree.crumb) { _, crumb in onCrumbChange(crumb) }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(copied ? L.t("path_copied", lang)
                        : String(format: L.t("tree_in", lang), ShellCompletionEngine.normalizeHomePath(tree.root)))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 8)
            // набранный фильтр и сколько папок совпало
            if !tree.filter.isEmpty {
                FilterChip(text: tree.filter)
                Text(String(format: L.t("filter_count", lang), rows.filter { !$0.isContext }.count,
                            tree.rows(listing.children).count))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(height: 24)
    }

    private var list: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(rows, id: \.row.path) { visible in
                        rowView(visible.row)
                            .opacity(visible.isContext ? 0.45 : 1)
                            .id(visible.row.path)
                    }
                    if rows.isEmpty, !tree.filter.isEmpty {
                        Text(L.t("search_empty", lang))
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                }
                .padding(Self.padding)
            }
            .scrollIndicators(.never)
            .onChange(of: tree.focus) { _, focus in
                if let focus { proxy.scrollTo(focus) }
            }
            .onAppear {
                if let focus = tree.focus {
                    DispatchQueue.main.async { proxy.scrollTo(focus, anchor: .center) }
                }
            }
        }
        .frame(height: listHeight)
        // правый клик по строке — меню папки у курсора; сама папка не открывается
        .hatchPopup(isPresented: Binding(get: { menuRow != nil }, set: { if !$0 { menuRow = nil } }),
                    placement: .atMouse,
                    onSecondaryClick: {
                        guard let row = hoveredRow else { return }
                        tree.select(row)
                        menuRow = row
                    }) { context in
            if let folder = menuRow {
                MenuCard {
                    FolderMenuView(sections: FolderActions.sections(
                        for: folder, currentDirectory: currentDirectory, favorites: favorites, lang: lang,
                        context: context, close: { menuRow = nil }, onToggleFavorite: onToggleFavorite,
                        onCopied: showCopied))
                }
            }
        }
    }

    /// «Путь скопирован» в заголовке дерева — на секунду.
    private func showCopied() {
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.15)) { copied = false }
        }
    }

    /// Подсказки в две строки: в одну при ширине дерева не влезают.
    private var footer: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                hint("→", L.t("tree_enter", lang))
                hint("←", L.t("tree_up", lang))
                hint("↩", L.t("tree_go", lang))
            }
            HStack(spacing: 10) {
                hint("⌘←→", L.t("tree_neighbor", lang))
                hint("esc", L.t("fav_close", lang))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Tactile.groupEdge).frame(height: 1) }
    }

    private func hint(_ key: String, _ text: String) -> some View {
        HStack(spacing: 4) {
            KeyHint(key: key)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func rowView(_ row: FolderTree.Row) -> some View {
        let selected = tree.focus == row.path
        let open = tree.isExpanded(row.path)
        return HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(open ? 90 : 0))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.12)) { tree.toggle(row.path) } }
            FolderGlyph(width: 15, height: 11)
            Text(FilterChip.highlighted(row.name, tree.filter))
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 3)
                .contentShape(Rectangle())
                .onTapGesture {
                    if NSEvent.modifierFlags.contains(.command) {
                        tree.select(row.path)
                        FolderActions.copyPath(row.path)
                        showCopied()
                    } else {
                        onNavigate(row.path)
                    }
                }
            if row.path == currentDirectory {
                Text(L.t("tree_current", lang))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 16 + 4)
        .padding(.trailing, 8)
        .frame(height: Self.rowHeight)
        .background(selected ? Tactile.accent.opacity(0.22) : .clear,
                    in: RoundedRectangle(cornerRadius: Self.rowRadius, style: .circular))
        .overlay(RoundedRectangle(cornerRadius: Self.rowRadius, style: .circular)
            .strokeBorder(selected ? Tactile.accent.opacity(0.55) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hoveredRow = row.path } else if hoveredRow == row.path { hoveredRow = nil }
        }
    }

    // MARK: - Клавиши

    /// Повторяются при удержании только стрелки, в том числе ⌘←/⌘→ (дерево бежит по пути
    /// и останавливается на краю). Enter, Space и буквы — по одному нажатию.
    static func repeats(_ key: KeyEquivalent, modifiers: EventModifiers) -> Bool {
        let arrows: [KeyEquivalent] = [.upArrow, .downArrow, .leftArrow, .rightArrow]
        if modifiers == .command { return key == .leftArrow || key == .rightArrow }
        return arrows.contains(key) && (modifiers.isEmpty || modifiers == .shift)
    }

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let modifiers = press.modifiers.subtracting([.numericPad, .function, .capsLock])
        let isRepeat = press.phase == .repeat
        // Esc: сначала очистить фильтр, потом — закрыть дерево (обычный Esc окна)
        if press.key == .escape, modifiers.isEmpty, !isRepeat {
            return tree.clearFilter() ? .handled : .ignored
        }
        if FilterChip.isErase(press.key), !tree.filter.isEmpty {
            _ = tree.handle(.backspace(all: modifiers.contains(.command)), children: listing.children)
            return .handled
        }
        // повтор не той клавиши поглощаем: иначе он ушёл бы панели (Enter — дважды в папку)
        if isRepeat, !Self.repeats(press.key, modifiers: modifiers) { return .handled }
        if modifiers == .command, press.key == .leftArrow || press.key == .rightArrow {
            onSwitchCrumb(press.key == .leftArrow ? -1 : 1)
            return .handled
        }
        // остальные сочетания (⌘T, ⌘W…) — дальше, панели
        guard modifiers.isEmpty || modifiers == .shift else { return .ignored }
        let key: FolderTree.Key
        switch press.key {
        case .upArrow: key = .up
        case .downArrow: key = .down
        case .rightArrow: key = .right
        case .leftArrow: key = .left
        case .space: key = .space
        case .return:
            if case .navigate(let path) = tree.enter() { onNavigate(path) }
            return .handled
        default:
            guard let character = press.characters.first, press.characters.count == 1,
                  ListFilter.accepts(character, space: false) else { return .ignored }
            key = .character(character)
        }
        // при удержании без анимации: повторы идут чаще, чем она успевает доиграть
        withAnimation(isRepeat ? nil : .easeOut(duration: 0.12)) { _ = tree.handle(key, children: listing.children) }
        return .handled
    }
}
