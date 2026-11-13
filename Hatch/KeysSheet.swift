import SwiftUI

/// Шпаргалка по клавишам (⌘/): клавиши того режима, в котором панель сейчас, в том же виде,
/// что подвалы дерева папок и избранного.
struct KeysSheetView: View {
    let mode: InputMode
    /// Сочетание открытия Hatch из настроек («⌥Space»).
    let hotkey: String
    let lang: String

    struct Group: Identifiable {
        let title: String
        let rows: [(key: String, what: String)]
        var id: String { title }
    }

    var body: some View {
        let groups = Self.groups(mode: mode, hotkey: hotkey, lang: lang)
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
            .padding(.vertical, 10)
            Divider().opacity(0.4)
            HStack(spacing: 6) {
                KeyHint(key: "esc")
                Text(Self.t("закрыть", "close", lang))
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
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
                            KeyHint(key: row.key).frame(minWidth: 44, alignment: .leading)
                            Text(row.what).font(.system(size: 12))
                        }
                    }
                }
            }
        }
        .fixedSize()
    }

    static func t(_ ru: String, _ en: String, _ lang: String) -> String { lang == "ru" ? ru : en }

    static func title(_ mode: InputMode, _ lang: String) -> String {
        switch mode {
        case .command: t("Клавиши · команды", "Keys · commands", lang)
        case .search: t("Клавиши · поиск", "Keys · search", lang)
        case .clipboard: t("Клавиши · буфер", "Keys · clipboard", lang)
        }
    }

    /// Что показать в режиме: только то, что в нём работает.
    static func groups(mode: InputMode, hotkey: String, lang: String) -> [Group] {
        let t = { (ru: String, en: String) in Self.t(ru, en, lang) }
        let everywhere = Group(title: t("Везде", "Everywhere"), rows: [
            ("⌘F", t("поиск по истории", "search history")), ("⌘4", t("буфер обмена", "clipboard")),
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
                    ("⌘C", t("копировать вывод", "copy output")), ("⌘R", t("повторить", "rerun")),
                    ("⌘S", t("закрепить", "pin")), ("⇧⌘R", t("формат или как есть", "formatted or as is")),
                    ("⌃C", t("прервать", "interrupt")),
                ]),
                Group(title: t("Окна", "Windows"), rows: [
                    ("⌘1", t("дерево папок", "folder tree")), ("⌘E", t("избранное", "favorites")),
                    ("⌘D", t("папку в избранное", "favorite this folder")), ("⌘,", t("настройки", "settings")),
                    ("⌃L", t("очистить историю", "clear finished blocks")),
                ]),
                everywhere,
            ]
        case .search:
            return [
                Group(title: t("Поиск", "Search"), rows: [
                    ("↑ ↓", t("найденные блоки", "found blocks")), ("↩", t("раскрыть", "expand")),
                    ("⌘C", t("копировать вывод", "copy output")), ("⌘R", t("повторить", "rerun")),
                    ("Esc", t("выйти из поиска", "leave search")),
                ]),
                everywhere,
            ]
        case .clipboard:
            return [
                Group(title: t("Запись", "Item"), rows: [
                    ("↑ ↓", t("выбрать", "select")), ("↩", t("копировать", "copy")), ("⌘↩", t("в поле", "to input")),
                    ("⌘1", t("крупно", "preview")), ("⌘S", t("закрепить", "pin")), ("⌘⌫", t("удалить", "delete")),
                    ("⇧⌘R", t("формат или как есть", "formatted or as is")),
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
            ("⌘4", t("всё скопированное", "everything you copied")), ("⇧⌘4", t("скриншот в буфер", "screenshot to clipboard")),
            ("⌘1", t("дерево папок", "folder tree")), ("⌘F", t("поиск по выводу", "search the output")),
            ("⌘E", t("избранное", "favorites")), ("⌘/", t("все клавиши", "all shortcuts")),
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
