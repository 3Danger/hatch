import SwiftUI
import AppKit

/// Кнопка «Приложение…» со списком установленных приложений: набор фильтрует
/// (`tel`, а в русской раскладке `еуд` — то же), ↑/↓ — выбор, Enter или клик — выбрать, Esc — очистить фильтр,
/// затем закрыть. Вместо системного меню на сотню с лишним приложений.
struct AppPickerButton: View {
    let title: String
    var apps: [AppEntry]
    var enabled = true
    let lang: String
    var onPick: (AppEntry) -> Void

    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            HStack(spacing: 3) {
                Text(title)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(.system(size: 12.5))
            .foregroundStyle(enabled ? Tactile.accent : Color.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .fixedSize()
        .hatchPopup(isPresented: $open) { _ in
            PopupCard {
                AppPickerView(apps: apps, lang: lang) { app in
                    open = false
                    onPick(app)
                }
            }
        }
    }
}

struct AppPickerView: View {
    let apps: [AppEntry]
    let lang: String
    var onPick: (AppEntry) -> Void

    @State private var filter = ""
    @State private var selection = 0
    @FocusState private var focused: Bool

    private static let rowHeight: CGFloat = 28
    private static let maxHeight: CGFloat = 320

    private var shown: [AppEntry] {
        // «Терминал» находится и по-русски, и как Terminal: оба имени равноправны
        ListFilter.filter(apps, query: filter, names: \.names)
    }

    var body: some View {
        let list = shown
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if filter.isEmpty {
                    Text(L.t("picker_type", lang)).font(.system(size: 11)).foregroundStyle(.tertiary)
                } else {
                    FilterChip(text: filter)
                }
                Spacer()
                Text(String(format: L.t("filter_count", lang), list.count, apps.count))
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            if list.isEmpty {
                Text(L.t("search_empty", lang))
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(list.enumerated()), id: \.element.identifier) { index, app in
                                row(app, selected: index == selection)
                                    .id(app.identifier)
                                    .onTapGesture { onPick(app) }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .scrollIndicators(.automatic)
                    .frame(height: min(CGFloat(list.count) * (Self.rowHeight + 1), Self.maxHeight))
                    .onChange(of: selection) { _, index in
                        if list.indices.contains(index) { proxy.scrollTo(list[index].identifier) }
                    }
                }
            }
        }
        .padding(.bottom, 6)
        .frame(width: 300)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
            guard !list.isEmpty else { return .handled }
            selection = min(max(selection + (press.key == .upArrow ? -1 : 1), 0), list.count - 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard list.indices.contains(selection) else { return .handled }
            onPick(list[selection])
            return .handled
        }
        .onKeyPress(phases: [.down, .repeat]) { press in type(press) }
        .onChange(of: filter) { _, _ in selection = 0 }
    }

    private func row(_ app: AppEntry, selected: Bool) -> some View {
        HStack(spacing: 8) {
            AppIconView(app: app, size: 18)
            Text(FilterChip.highlighted(app.title, filter))
                .font(.system(size: 13))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .frame(height: Self.rowHeight)
        .background(selected ? Tactile.accent.opacity(0.22) : .clear, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Tactile.accent.opacity(0.55) : .clear))
        .contentShape(Rectangle())
    }

    /// Набор — в фильтр; Backspace стирает; Esc сначала очищает фильтр, затем закрывает список.
    private func type(_ press: KeyPress) -> KeyPress.Result {
        let modifiers = press.modifiers.subtracting([.shift, .capsLock, .numericPad, .function])
        if press.key == .escape, modifiers.isEmpty {
            guard !filter.isEmpty else { return .ignored }
            filter = ""
            return .handled
        }
        if FilterChip.isErase(press.key) {
            guard !filter.isEmpty else { return .ignored }
            if modifiers.contains(.command) { filter = "" } else { filter.removeLast() }
            return .handled
        }
        guard modifiers.isEmpty, press.characters.count == 1, let character = press.characters.first,
              ListFilter.accepts(character, space: true) else { return .ignored }
        filter.append(character)
        return .handled
    }
}
