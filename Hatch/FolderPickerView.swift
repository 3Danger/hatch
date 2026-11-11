import SwiftUI

/// Список папок по клику на часть пути — как в строке пути VS Code, только папки:
/// папки того же уровня (кликнутая выделена), шеврон раскрывает вложенные деревом.
/// Клик по имени — перейти; ↑/↓ — выбор, →/← — раскрыть/свернуть, Enter — перейти.
struct FolderPickerView: View {
    let target: FolderListing.Target
    var onPick: (String) -> Void = { _ in }

    @State private var expanded: Set<String> = []
    @State private var children: [String: [String]]
    @State private var selection: Int
    @FocusState private var focused: Bool

    /// Высота строки фиксирована: высота списка считается по числу строк.
    private static let rowHeight: CGFloat = 22
    private static let maxHeight: CGFloat = 300
    private static let padding: CGFloat = 4

    init(target: FolderListing.Target, onPick: @escaping (String) -> Void = { _ in }) {
        self.target = target
        self.onPick = onPick
        // папки читаем сразу: у всплывающего окна с первого кадра верная высота
        let names = FolderListing.subdirectories(of: target.directory)
        _children = State(initialValue: [target.directory: names])
        _selection = State(initialValue: target.highlighted.flatMap { names.firstIndex(of: $0) } ?? 0)
    }

    /// По числу строк, дальше — прокрутка; без явной высоты окно схлопывается в полоску.
    private var listHeight: CGFloat {
        let content = CGFloat(max(rows.count, 1)) * (Self.rowHeight + 1) + Self.padding * 2
        return min(content, Self.maxHeight)
    }

    private struct Row: Hashable {
        let path: String
        let name: String
        let depth: Int
    }

    /// Дерево, развёрнутое в строки: раскрытые папки — со своими вложенными под ними.
    private var rows: [Row] {
        var result: [Row] = []
        func append(_ directory: String, depth: Int) {
            for name in children[directory] ?? [] {
                let path = (directory as NSString).appendingPathComponent(name)
                result.append(Row(path: path, name: name, depth: depth))
                if expanded.contains(path) { append(path, depth: depth + 1) }
            }
        }
        append(target.directory, depth: 0)
        return result
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(Array(rows.enumerated()), id: \.element) { index, row in
                        rowView(row, selected: index == selection)
                            .id(index)
                            .onTapGesture {
                                selection = index
                                onPick(row.path)
                            }
                    }
                }
                .padding(Self.padding)
            }
            .onChange(of: selection) { _, index in proxy.scrollTo(index) }
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo(selection, anchor: .center) }
                focused = true
            }
        }
        .frame(width: 260, height: listHeight)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.rightArrow) { setExpanded(true) }
        .onKeyPress(.leftArrow) { setExpanded(false) }
        .onKeyPress(.return) {
            guard rows.indices.contains(selection) else { return .ignored }
            onPick(rows[selection].path)
            return .handled
        }
    }

    private func rowView(_ row: Row, selected: Bool) -> some View {
        let isOpen = expanded.contains(row.path)
        return HStack(spacing: 4) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
                .onTapGesture { toggle(row.path) }
            Text(row.name)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(row.depth) * 14 + 2)
        .padding(.trailing, 6)
        .frame(height: Self.rowHeight)
        .background(selected ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5)
            .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 1))
        .contentShape(Rectangle())
    }

    private func load(_ directory: String) {
        if children[directory] == nil {
            children[directory] = FolderListing.subdirectories(of: directory)
        }
    }

    private func toggle(_ path: String) {
        if expanded.contains(path) {
            expanded.remove(path)
        } else {
            load(path)
            expanded.insert(path)
        }
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        guard !rows.isEmpty else { return .handled }
        selection = min(max(selection + delta, 0), rows.count - 1)
        return .handled
    }

    private func setExpanded(_ open: Bool) -> KeyPress.Result {
        guard rows.indices.contains(selection) else { return .handled }
        let path = rows[selection].path
        if open != expanded.contains(path) { toggle(path) }
        return .handled
    }
}
