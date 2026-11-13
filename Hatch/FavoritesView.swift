import SwiftUI

/// Список «Избранное» по кнопке ★ в поле ввода (⌘E): избранные папки и команды.
/// Клик по папке — перейти в неё, как `cd`; по команде — запустить в текущей папке.
/// ↑/↓ — выбор, Enter — применить, Esc — закрыть, ★ в строке — убрать из избранного.
/// Порядок меняется перетаскиванием мышью и ⌘↑/⌘↓ — внутри своего раздела (папки или команды).
/// Набор букв фильтрует оба раздела (имя папки, путь, текст команды); Esc сначала очищает фильтр.
struct FavoritesView: View {
    let directories: [String]
    let commands: [String]
    let currentDirectory: String
    let lang: String
    var onGo: (String) -> Void = { _ in }
    var onRun: (String) -> Void = { _ in }
    var onRemoveDirectory: (String) -> Void = { _ in }
    var onRemoveCommand: (String) -> Void = { _ in }
    /// Переставить: откуда, куда (индексы внутри раздела).
    var onMoveDirectory: (Int, Int) -> Void = { _, _ in }
    var onMoveCommand: (Int, Int) -> Void = { _, _ in }

    @State private var selection = 0
    @FocusState private var focused: Bool
    /// Перетаскиваемая строка: раздел, её место до перетаскивания и сдвиг мыши.
    @State private var drag: Drag?
    /// Высота строки с промежутком: на столько соседи расступаются при перетаскивании.
    @State private var rowStep: CGFloat = 46
    /// Набранный фильтр; пока он есть, порядок не меняется (соседи в нём не настоящие).
    @State private var filter = ""

    private enum Item: Hashable {
        case directory(String)
        case command(String)
    }

    private enum Section { case directories, commands }

    private struct Drag: Equatable {
        let section: Section
        let from: Int
        var offset: CGFloat
    }

    private static let rowSpacing: CGFloat = 2

    /// Видимые строки: всё или совпавшее с фильтром, лучшие совпадения выше. `offset` — место в разделе.
    private var shownDirectories: [(offset: Int, element: String)] {
        ListFilter.filter(Array(directories.enumerated()), query: filter,
                          name: { PathBreadcrumbs.folderName(for: $0.element) },
                          extra: { ShellCompletionEngine.normalizeHomePath($0.element) })
            .map { (offset: $0.offset, element: $0.element) }
    }

    private var shownCommands: [(offset: Int, element: String)] {
        ListFilter.filter(Array(commands.enumerated()), query: filter, name: { $0.element })
            .map { (offset: $0.offset, element: $0.element) }
    }

    private var items: [Item] {
        shownDirectories.map { Item.directory($0.element) } + shownCommands.map { Item.command($0.element) }
    }

    private var filtering: Bool { !filter.isEmpty }

    var body: some View {
        let dirs = shownDirectories
        let cmds = shownCommands
        return VStack(alignment: .leading, spacing: Self.rowSpacing) {
            if filtering { filterBar(found: dirs.count + cmds.count) }
            if !filtering || !dirs.isEmpty {
                section(L.t("fav_dirs", lang), hint: L.t("fav_dirs_hint", lang))
            }
            if directories.isEmpty { empty(L.t("fav_dirs_empty", lang)) }
            ForEach(Array(dirs.enumerated()), id: \.element.element) { shownIndex, entry in
                let index = entry.offset
                let path = entry.element
                row(selected: selection == shownIndex, remove: { onRemoveDirectory(path) }) {
                    FolderGlyph()
                    labels(title: PathBreadcrumbs.folderName(for: path),
                           subtitle: ShellCompletionEngine.normalizeHomePath(path), mono: false)
                }
                .reorderable(drag: drag(for: .directories, at: index, count: directories.count),
                             gesture: dragGesture(.directories, index: index, count: directories.count), enabled: !filtering)
                .onTapGesture { onGo(path) }
            }

            if !filtering { divider }
            if !filtering || !cmds.isEmpty {
                section(L.t("fav_cmds", lang), hint: L.t("fav_cmds_hint", lang))
            }
            if commands.isEmpty { empty(L.t("fav_cmds_empty", lang)) }
            ForEach(Array(cmds.enumerated()), id: \.element.element) { shownOffset, entry in
                let offset = entry.offset
                let command = entry.element
                let index = dirs.count + shownOffset
                row(selected: selection == index, remove: { onRemoveCommand(command) }) {
                    Text("›")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18)
                    labels(title: command,
                           subtitle: String(format: L.t("fav_run_in", lang), PathBreadcrumbs.folderName(for: currentDirectory)),
                           mono: true)
                }
                .reorderable(drag: drag(for: .commands, at: offset, count: commands.count),
                             gesture: dragGesture(.commands, index: offset, count: commands.count), enabled: !filtering)
                .onTapGesture { onRun(command) }
            }
            if filtering, dirs.isEmpty, cmds.isEmpty {
                Text(L.t("search_empty", lang))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }

            divider
            // подвал: клавиши в лунках и что они делают — в две строки, в одну не влезают
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 12) {
                    hint(["↑", "↓"], L.t("fav_select", lang))
                    hint(["⌘↑↓"], L.t("fav_reorder", lang))
                }
                HStack(spacing: 12) {
                    hint(["↩"], L.t("fav_apply", lang))
                    hint(["esc"], L.t("fav_close", lang))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
        }
        .padding(6)
        .frame(width: 380)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        // удержание стрелки — повторы: выбор бежит по строкам, с ⌘ — строка едет по разделу
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
            let delta = press.key == .upArrow ? -1 : 1
            return press.modifiers.contains(.command) ? reorder(delta) : move(delta)
        }
        .onKeyPress(.return) { apply() }
        // набор букв фильтрует; Backspace стирает, Esc сначала очищает фильтр (затем — закрыть список)
        .onKeyPress(phases: [.down, .repeat]) { press in type(press) }
        .onChange(of: filter) { _, _ in selection = 0 }
        .onChange(of: items.count) { _, count in selection = min(selection, max(count - 1, 0)) }
    }

    // MARK: - Перестановка

    /// Сдвиг строки при перетаскивании: сама строка — за мышью, соседи между старым
    /// и новым местом расступаются на одну строку.
    private func drag(for section: Section, at index: Int, count: Int) -> (offset: CGFloat, lifted: Bool) {
        guard let drag, drag.section == section else { return (0, false) }
        if index == drag.from { return (drag.offset, true) }
        let target = Self.target(from: drag.from, offset: drag.offset, step: rowStep, count: count)
        if drag.from < index, index <= target { return (-rowStep, false) }
        if target <= index, index < drag.from { return (rowStep, false) }
        return (0, false)
    }

    /// Куда встанет строка: на сколько целых строк её сдвинули, в пределах раздела.
    static func target(from: Int, offset: CGFloat, step: CGFloat, count: Int) -> Int {
        guard step > 0, count > 0 else { return from }
        return min(max(from + Int((offset / step).rounded()), 0), count - 1)
    }

    private func dragGesture(_ section: Section, index: Int, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                if drag == nil {
                    selection = (section == .directories ? 0 : directories.count) + index
                }
                drag = Drag(section: section, from: index, offset: value.translation.height)
            }
            .onEnded { value in
                let to = Self.target(from: index, offset: value.translation.height, step: rowStep, count: count)
                // без анимации: строки уже стоят на новых местах, иначе они дёрнулись бы обратно
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    drag = nil
                    commitMove(section, from: index, to: to)
                }
            }
    }

    /// ⌘↑/⌘↓: выбранная строка на одно место выше или ниже, внутри своего раздела.
    private func reorder(_ delta: Int) -> KeyPress.Result {
        // в отфильтрованном списке соседи не настоящие — порядок не трогаем
        guard !filtering, items.indices.contains(selection) else { return .handled }
        let (section, index, count) = selection < directories.count
            ? (Section.directories, selection, directories.count)
            : (Section.commands, selection - directories.count, commands.count)
        let to = index + delta
        guard (0..<count).contains(to) else { return .handled } // на краю раздела — стоп
        withAnimation(.easeOut(duration: 0.15)) { commitMove(section, from: index, to: to) }
        return .handled
    }

    private func commitMove(_ section: Section, from: Int, to: Int) {
        guard from != to else { return }
        switch section {
        case .directories:
            onMoveDirectory(from, to)
            selection = to
        case .commands:
            onMoveCommand(from, to)
            selection = directories.count + to
        }
    }

    // MARK: - Фильтр

    private func type(_ press: KeyPress) -> KeyPress.Result {
        let modifiers = press.modifiers.subtracting([.shift, .capsLock, .numericPad, .function])
        if press.key == .escape, modifiers.isEmpty {
            guard filtering else { return .ignored } // фильтра нет — Esc закрывает список
            filter = ""
            return .handled
        }
        if FilterChip.isErase(press.key) {
            guard filtering else { return .ignored }
            if modifiers.contains(.command) { filter = "" } else { filter.removeLast() }
            return .handled
        }
        guard modifiers.isEmpty, press.characters.count == 1, let character = press.characters.first,
              ListFilter.accepts(character, space: true) else { return .ignored }
        filter.append(character)
        return .handled
    }

    /// Над списком: набранное плашкой и сколько нашлось.
    private func filterBar(found: Int) -> some View {
        HStack(spacing: 8) {
            FilterChip(text: filter)
            Spacer()
            Text(String(format: L.t("filter_count", lang), found, directories.count + commands.count))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    // MARK: - Вид

    private func hint(_ keys: [String], _ text: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { KeyHint(key: $0) }
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .fixedSize()
                .padding(.leading, 1)
        }
    }

    private func section(_ title: String, hint: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.6)
                .foregroundStyle(.secondary)
            Spacer()
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .padding(.bottom, 2)
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
    }

    private var divider: some View {
        Rectangle().fill(Tactile.groupEdge).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 4)
    }

    private func labels(title: String, subtitle: String, mono: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(FilterChip.highlighted(title, filter))
                .font(mono ? .system(size: 12, weight: .medium, design: .monospaced) : .system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(FilterChip.highlighted(subtitle, filter))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    private func row<Content: View>(selected: Bool, remove: @escaping () -> Void,
                                    @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 10) {
            content()
            Spacer(minLength: 4)
            Button(action: remove) {
                KeyIconView(icon: .starOn, size: 13)
                    .foregroundStyle(Tactile.star)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L.t("fav_remove", lang))
        }
        .padding(.leading, 10)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(selected ? Tactile.accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Tactile.accent.opacity(0.55) : .clear))
        .contentShape(Rectangle())
        // все строки одной высоты: по ней считается, на сколько мест сдвинули перетаскиваемую
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowStep = $0 + Self.rowSpacing }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !items.isEmpty else { return .handled }
        selection = (selection + delta + items.count) % items.count
        return .handled
    }

    private func apply() -> KeyPress.Result {
        guard items.indices.contains(selection) else { return .ignored }
        switch items[selection] {
        case .directory(let path): onGo(path)
        case .command(let command): onRun(command)
        }
        return .handled
    }
}

private extension View {
    /// Строка, которую можно перетащить: за мышью она приподнята (тень, поверх соседей),
    /// соседи плавно расступаются.
    func reorderable<G: Gesture>(drag: (offset: CGFloat, lifted: Bool), gesture: G, enabled: Bool) -> some View {
        self
            .background(drag.lifted ? Tactile.menu : .clear, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(drag.lifted ? 0.45 : 0), radius: 10, y: 6)
            .scaleEffect(drag.lifted ? 1.02 : 1)
            .offset(y: drag.offset)
            .zIndex(drag.lifted ? 1 : 0)
            .animation(drag.lifted ? nil : .easeOut(duration: 0.15), value: drag.offset)
            .gesture(gesture, including: enabled ? .all : .subviews)
    }
}

/// Сообщение внизу панели: что произошло и, если можно, «Отменить». Само исчезает через 5 секунд.
struct PanelToast: Equatable {
    let id = UUID()
    var text: String
    var undo: (() -> Void)?

    static let duration: TimeInterval = 5

    static func == (a: PanelToast, b: PanelToast) -> Bool { a.id == b.id }
}

struct PanelToastView: View {
    let toast: PanelToast
    let lang: String
    var onUndo: () -> Void = {}
    @State private var drained = false

    var body: some View {
        HStack(spacing: 12) {
            Text(toast.text)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
            if toast.undo != nil {
                Button(action: onUndo) {
                    Text(L.t("undo", lang))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Tactile.keyText)
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                }
                .buttonStyle(KeyCapButtonStyle(cornerRadius: 7))
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, toast.undo == nil ? 14 : 8)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .circular).fill(Tactile.toast)
                .shadow(color: .black.opacity(0.5), radius: 10, y: 6)
        }
        .overlay(RoundedRectangle(cornerRadius: 10, style: .circular).strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
        // полоска внизу тает за 5 секунд: столько времени есть на «Отменить»
        .overlay(alignment: .bottomLeading) {
            Capsule().fill(.white.opacity(0.25))
                .frame(height: 2)
                .scaleEffect(x: drained ? 0 : 1, anchor: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 3)
        }
        .onAppear { withAnimation(.linear(duration: PanelToast.duration)) { drained = true } }
    }
}

/// Набранный фильтр плашкой (как набранные буквы в дереве папок) и подсветка совпадения.
struct FilterChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .background(Tactile.accent.opacity(0.35), in: RoundedRectangle(cornerRadius: 5, style: .circular))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .circular).strokeBorder(Tactile.accent.opacity(0.7)))
            .lineLimit(1)
    }

    /// Клавиша Delete стирает букву фильтра. На Mac она приходит символом U+007F (DEL), а не
    /// `.delete` SwiftUI (U+0008) — сравнение только с `.delete` её не ловит. Fn+Delete тоже стирает.
    static func isErase(_ key: KeyEquivalent) -> Bool {
        key == .delete || key == .deleteForward || key.character == "\u{7F}"
    }

    /// Текст с подсвеченным совпадением фильтра.
    static func highlighted(_ text: String, _ query: String) -> AttributedString {
        var result = AttributedString(text)
        guard let range = ListFilter.matchRange(query, in: text),
              let lower = AttributedString.Index(range.lowerBound, within: result),
              let upper = AttributedString.Index(range.upperBound, within: result) else { return result }
        result[lower..<upper].backgroundColor = Tactile.accent.opacity(0.45)
        result[lower..<upper].foregroundColor = .white
        return result
    }
}
