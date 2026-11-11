import SwiftUI

/// Список «Избранное» по кнопке ★ в поле ввода (⌘E): избранные папки и команды.
/// Клик по папке — перейти в неё, как `cd`; по команде — запустить в текущей папке.
/// ↑/↓ — выбор, Enter — применить, Esc — закрыть, ★ в строке — убрать из избранного.
struct FavoritesView: View {
    let directories: [String]
    let commands: [String]
    let currentDirectory: String
    let lang: String
    var onGo: (String) -> Void = { _ in }
    var onRun: (String) -> Void = { _ in }
    var onRemoveDirectory: (String) -> Void = { _ in }
    var onRemoveCommand: (String) -> Void = { _ in }

    @State private var selection = 0
    @FocusState private var focused: Bool

    private enum Item: Hashable {
        case directory(String)
        case command(String)
    }

    private var items: [Item] { directories.map(Item.directory) + commands.map(Item.command) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            section(L.t("fav_dirs", lang), hint: L.t("fav_dirs_hint", lang))
            if directories.isEmpty { empty(L.t("fav_dirs_empty", lang)) }
            ForEach(Array(directories.enumerated()), id: \.element) { index, path in
                row(selected: selection == index, remove: { onRemoveDirectory(path) }) {
                    FolderGlyph()
                    labels(title: PathBreadcrumbs.folderName(for: path),
                           subtitle: ShellCompletionEngine.normalizeHomePath(path), mono: false)
                }
                .onTapGesture { onGo(path) }
            }

            divider
            section(L.t("fav_cmds", lang), hint: L.t("fav_cmds_hint", lang))
            if commands.isEmpty { empty(L.t("fav_cmds_empty", lang)) }
            ForEach(Array(commands.enumerated()), id: \.element) { offset, command in
                let index = directories.count + offset
                row(selected: selection == index, remove: { onRemoveCommand(command) }) {
                    Text("›")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(width: 18)
                    labels(title: command,
                           subtitle: String(format: L.t("fav_run_in", lang), PathBreadcrumbs.folderName(for: currentDirectory)),
                           mono: true)
                }
                .onTapGesture { onRun(command) }
            }

            divider
            // подвал как в макете: клавиши в лунках и что они делают
            HStack(spacing: 12) {
                hint(["↑", "↓"], L.t("fav_select", lang))
                hint(["↩"], L.t("fav_apply", lang))
                hint(["esc"], L.t("fav_close", lang))
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
        .onKeyPress(.downArrow) { move(1) }
        .onKeyPress(.upArrow) { move(-1) }
        .onKeyPress(.return) { apply() }
        .onChange(of: items.count) { _, count in selection = min(selection, max(count - 1, 0)) }
    }

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
            Text(title)
                .font(mono ? .system(size: 12, weight: .medium, design: .monospaced) : .system(size: 13, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
            Text(subtitle)
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
