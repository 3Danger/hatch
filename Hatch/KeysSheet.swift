import SwiftUI

/// Шпаргалка по клавишам (⌘/): клавиши того режима, в котором панель сейчас, в том же виде,
/// что подвалы дерева папок и избранного.
struct KeysSheetView: View {
    let mode: InputMode
    /// Сочетание открытия Hatch из настроек («⌥Space»).
    let hotkey: String
    /// Сочетание дерева папок из настроек («⌘T»).
    var tree = "⌘T"
    /// Enter в буфере вставляет в приложение (а ⌘C копирует).
    var pastes = false
    let lang: String

    struct Group: Identifiable {
        let title: String
        let rows: [(key: String, what: String)]
        var id: String { title }
    }

    var body: some View {
        let groups = Self.groups(mode: mode, hotkey: hotkey, tree: tree, pastes: pastes, lang: lang)
        let half = (groups.count + 1) / 2
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.title(mode, lang).uppercased())
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 12)
            HStack(alignment: .top, spacing: 22) {
                column(Array(groups.prefix(half)))
                column(Array(groups.dropFirst(half)))
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 14)
            // подвала «esc закрыть» нет: Esc уже в группе «Везде» — «закрыть слой»
        }
        .fixedSize()
    }

    private func column(_ groups: [Group]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(groups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.title.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.5)
                        .foregroundStyle(.tertiary)
                    ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: 8) {
                            // колонка клавиш одной ширины: длинная («⌥Space») не сдвигает подпись
                            KeyHint(key: row.key).frame(minWidth: Self.keyColumn(groups), alignment: .leading)
                            Text(row.what).font(.system(size: 12))
                        }
                    }
                }
            }
        }
        .fixedSize()
    }

    static func t(_ ru: String, _ en: String, _ lang: String) -> String { lang == "ru" ? ru : en }

    /// Ширина колонки клавиш: по самой длинной клавише колонки, но не уже 44.
    static func keyColumn(_ groups: [Group]) -> CGFloat {
        let longest = groups.flatMap(\.rows).map(\.key.count).max() ?? 0
        return max(44, CGFloat(longest) * 8 + 14)
    }

    static func title(_ mode: InputMode, _ lang: String) -> String {
        switch mode {
        case .command: t("Клавиши · команды", "Keys · commands", lang)
        case .search: t("Клавиши · поиск", "Keys · search", lang)
        case .clipboard: t("Клавиши · буфер", "Keys · clipboard", lang)
        }
    }

    /// Что показать в режиме: только то, что в нём работает.
    static func groups(mode: InputMode, hotkey: String, tree: String = "⌘T", pastes: Bool = false, lang: String) -> [Group] {
        let t = { (ru: String, en: String) in Self.t(ru, en, lang) }
        // клавиши действий — из каталога (те же, что в подсказках кнопок и меню «⋯»)
        let k = { (action: HatchAction) in action.key ?? "" }
        let everywhere = Group(title: t("Везде", "Everywhere"), rows: [
            (k(.modeCommands), t("команды", "commands")), (k(.modeSearch), t("поиск по истории", "search history")),
            (k(.modeClipboard), t("буфер обмена", "clipboard")),
            ("⇧⌘4", t("скриншот в буфер", "screenshot to clipboard")), ("Esc", t("закрыть слой", "close the top layer")),
            (hotkey, t("скрыть Hatch", "hide Hatch")),
        ])
        switch mode {
        case .command:
            return [
                Group(title: t("Поле", "Input"), rows: [
                    ("↩", t("выполнить", "run")), ("Tab", t("дополнить", "complete")),
                    ("→", t("принять подсказку", "accept the suggestion")), ("↑ ↓", t("прошлые команды и блоки", "previous commands and blocks")),
                ]),
                Group(title: t("Выбранный блок", "Selected block"), rows: [
                    (k(.copyOutput), t("копировать вывод", "copy output")), (k(.rerun), t("повторить", "rerun")),
                    (k(.pinClip), t("закрепить", "pin")), (k(.formatOn), t("формат или как есть", "formatted or as is")),
                    (k(.stop), t("прервать", "interrupt")), (k(.deleteClip), t("удалить", "delete")),
                ]),
                Group(title: t("Окна", "Windows"), rows: [
                    (tree, t("дерево папок", "folder tree")), (k(.favorites), t("избранное", "favorites")),
                    ("⌘D", t("папку в избранное", "favorite this folder")), (k(.settings), t("настройки", "settings")),
                    ("⌃L", t("очистить историю", "clear finished blocks")),
                ]),
                everywhere,
            ]
        case .search:
            return [
                Group(title: t("Поиск", "Search"), rows: [
                    ("↑ ↓", t("найденные блоки", "found blocks")), ("↩", t("раскрыть", "expand")),
                    (k(.copyOutput), t("копировать вывод", "copy output")), (k(.rerun), t("повторить", "rerun")),
                    ("Esc", t("выйти из поиска", "leave search")),
                ]),
                everywhere,
            ]
        case .clipboard:
            return [
                Group(title: t("Запись", "Item"), rows: [
                    ("↑ ↓", t("выбрать", "select")),
                ] + (pastes ? [(k(.pasteInto(nil)), t("вставить в приложение", "paste into the app")), (k(.copyClipOnly), t("копировать", "copy"))]
                            : [(k(.copyClipToPaste), t("копировать", "copy"))]) + [
                    (k(.insertClip), t("в поле", "to input")),
                    (k(.previewClip), t("крупно", "preview")), (k(.pinClip), t("закрепить", "pin")), (k(.deleteClip), t("удалить", "delete")),
                    (k(.formatOn), t("формат или как есть", "formatted or as is")),
                ]),
                Group(title: t("Буфер", "Clipboard"), rows: [
                    ("Tab ⇧Tab", t("тип записей", "item type")), ("⌃L", t("очистить, кроме закреплённых", "clear, pinned stay")),
                    ("Esc", t("выйти из буфера", "leave clipboard")),
                ]),
                everywhere,
            ]
        }
    }
}

/// Пустая история: что набрать и что ещё умеет Hatch — по клавише на строку.
struct EmptyHistoryView: View {
    let lang: String

    var body: some View {
        let t = { (ru: String, en: String) in KeysSheetView.t(ru, en, lang) }
        let tips: [(String, String)] = [
            (HatchAction.modeClipboard.key ?? "", t("всё скопированное", "everything you copied")),
            ("⇧⌘4", t("скриншот в буфер", "screenshot to clipboard")),
            ("⌘T", t("дерево папок", "folder tree")), (HatchAction.modeSearch.key ?? "", t("поиск по выводу", "search the output")),
            (HatchAction.favorites.key ?? "", t("избранное", "favorites")), ("⌘/", t("все клавиши", "all shortcuts")),
        ]
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(t("Здесь появятся ваши команды. Наберите любую, например", "Your commands will appear here. Type any, for example"))
                Text("git status")
                    .font(.system(size: 12.5, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Tactile.well, in: RoundedRectangle(cornerRadius: 5))
                KeyHint(key: "↩")
            }
            .font(.system(size: 13))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), alignment: .leading)], alignment: .leading, spacing: 8) {
                ForEach(tips, id: \.0) { key, what in
                    HStack(spacing: 8) {
                        KeyHint(key: key).frame(minWidth: 34, alignment: .leading)
                        Text(what).font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
