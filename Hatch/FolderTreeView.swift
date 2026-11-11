import SwiftUI

/// Дерево папок у папки пути (клик по ней или ⌘P): соседи папки, она выделена.
/// ↑/↓ — по строкам, → — раскрыть и войти, ← — свернуть, к родителю, на верху — уровнем выше,
/// Space — свернуть/развернуть, буквы — к папке по имени, Enter — перейти (как `cd`),
/// ⌥←/⌥→ — дерево соседней папки пути, Esc — закрыть. Клик по имени — перейти, по шеврону — раскрыть.
struct FolderTreeView: View {
    let currentDirectory: String
    let lang: String
    var onNavigate: (String) -> Void = { _ in }
    /// ⌥←/⌥→: открыть дерево соседней папки пути (−1 — левее, +1 — правее).
    var onSwitchCrumb: (Int) -> Void = { _ in }
    /// Дерево поднялось уровнем выше — в пути подсвечивается эта папка.
    var onCrumbChange: (String) -> Void = { _ in }

    @State private var tree: FolderTree
    @State private var listing = Listing()
    @State private var showTyped = false
    @State private var typedToken = 0
    @FocusState private var focused: Bool

    private static let rowHeight: CGFloat = 26
    private static let rowSpacing: CGFloat = 1
    private static let maxHeight: CGFloat = 320
    /// Отступ строк от края карточки: скругление строки + отступ = скругление карточки (14).
    private static let padding: CGFloat = 6
    private static let rowRadius: CGFloat = 8

    init(crumb: String, currentDirectory: String, lang: String,
         onNavigate: @escaping (String) -> Void = { _ in },
         onSwitchCrumb: @escaping (Int) -> Void = { _ in },
         onCrumbChange: @escaping (String) -> Void = { _ in }) {
        self.currentDirectory = currentDirectory
        self.lang = lang
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

    private var rows: [FolderTree.Row] { tree.rows(listing.children) }

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
        .onKeyPress(phases: .down) { press in handle(press) }
        .onChange(of: tree.crumb) { _, crumb in onCrumbChange(crumb) }
    }

    private var header: some View {
        HStack(spacing: 4) {
            Text(String(format: L.t("tree_in", lang), ShellCompletionEngine.normalizeHomePath(tree.root)))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 8)
            // набранные буквы — чтобы было видно, что ищется
            if showTyped, !tree.typed.isEmpty {
                Text(tree.typed)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .background(Tactile.accent.opacity(0.35), in: RoundedRectangle(cornerRadius: 5, style: .circular))
                    .overlay(RoundedRectangle(cornerRadius: 5, style: .circular).strokeBorder(Tactile.accent.opacity(0.7)))
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
                    ForEach(rows, id: \.path) { row in
                        rowView(row).id(row.path)
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
                hint("⌥←→", L.t("tree_neighbor", lang))
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
            Text(row.name)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.leading, 3)
                .contentShape(Rectangle())
                .onTapGesture { onNavigate(row.path) }
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
    }

    // MARK: - Клавиши

    private func handle(_ press: KeyPress) -> KeyPress.Result {
        let modifiers = press.modifiers.subtracting([.numericPad, .function, .capsLock])
        if modifiers == .option, press.key == .leftArrow || press.key == .rightArrow {
            onSwitchCrumb(press.key == .leftArrow ? -1 : 1)
            return .handled
        }
        // остальные сочетания (⌘P, ⌘W…) — дальше, панели
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
                  character.isLetter || character.isNumber || "-_.".contains(character) else { return .ignored }
            key = .character(character)
        }
        withAnimation(.easeOut(duration: 0.12)) { _ = tree.handle(key, children: listing.children) }
        if case .character = key { flashTyped() }
        return .handled
    }

    /// Набранные буквы видны, пока набор не сброшен паузой.
    private func flashTyped() {
        showTyped = true
        typedToken += 1
        let token = typedToken
        DispatchQueue.main.asyncAfter(deadline: .now() + FolderTree.typingPause) {
            if typedToken == token { showTyped = false }
        }
    }
}
