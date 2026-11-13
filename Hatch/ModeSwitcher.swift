import SwiftUI

/// Переключатель режимов панели в строке над полем: команды, поиск (⌘F), буфер (⌘4).
/// Компактный: подпись только у включённого, у остальных — значок, название и клавиша — в подсказке.
/// Включённый подсвечен цветом рамки поля этого режима.
struct ModeSwitcher: View {
    let mode: InputMode
    let lang: String
    var onSelect: (InputMode) -> Void

    private static let modes: [InputMode] = [.command, .search, .clipboard]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Self.modes, id: \.self) { item in segment(item) }
        }
        .padding(2)
        .tactileWell(RoundedRectangle(cornerRadius: 8, style: .circular))
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: mode)
        .fixedSize()
    }

    private func segment(_ item: InputMode) -> some View {
        let on = item == mode
        return Button { onSelect(item) } label: {
            HStack(spacing: 5) {
                Image(systemName: Self.icon(item))
                    .font(.system(size: 10.5, weight: .semibold))
                if on { Text(Self.title(item, lang)).font(.system(size: 11.5, weight: .medium)) }
            }
            .foregroundStyle(on ? Color.white : Color.secondary)
            .padding(.horizontal, on ? 9 : 7)
            .frame(height: 20)
            .background(on ? Self.color(item).opacity(0.55) : .clear, in: RoundedRectangle(cornerRadius: 6, style: .circular))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .circular).strokeBorder(on ? .white.opacity(0.14) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Self.help(item, lang))
        .accessibilityLabel(Self.title(item, lang))
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    static func icon(_ mode: InputMode) -> String {
        switch mode {
        case .command: "terminal"
        case .search: "magnifyingglass"
        case .clipboard: "doc.on.clipboard"
        }
    }

    static func title(_ mode: InputMode, _ lang: String) -> String {
        switch mode {
        case .command: L.t("mode_commands", lang)
        case .search: L.t("search", lang)
        case .clipboard: L.t("clip_mode", lang)
        }
    }

    static func help(_ mode: InputMode, _ lang: String) -> String {
        switch mode {
        case .command: L.t("mode_commands", lang) + " (Esc)"
        case .search: L.t("search", lang) + " (⌘F)"
        case .clipboard: L.t("clip_mode", lang) + " (⌘4)"
        }
    }

    /// Цвет рамки поля в этом режиме.
    static func color(_ mode: InputMode) -> Color {
        switch mode {
        case .command: Tactile.accent
        case .search: Tactile.search
        case .clipboard: Tactile.clip
        }
    }
}

/// Сколько нашёл поиск по истории: блоков и совпадений в командах и выводе.
enum SearchStats {
    static func count(_ query: String, in sessions: [Session]) -> (blocks: Int, matches: Int) {
        guard !query.isEmpty else { return (0, 0) }
        var blocks = 0, matches = 0
        for session in sessions {
            let n = occurrences(of: query, in: session.command) + occurrences(of: query, in: session.output)
            if n > 0 { blocks += 1; matches += n }
        }
        return (blocks, matches)
    }

    static func occurrences(of query: String, in text: String) -> Int {
        guard !query.isEmpty else { return 0 }
        var count = 0
        var range = text.startIndex..<text.endIndex
        while let found = text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: range) {
            count += 1
            range = found.upperBound..<text.endIndex
        }
        return count
    }

    /// «2 блока · 3 совпадения» / "2 blocks · 3 matches".
    static func summary(_ stats: (blocks: Int, matches: Int), lang: String) -> String {
        if lang == "ru" {
            return "\(stats.blocks) \(plural(stats.blocks, "блок", "блока", "блоков")) · "
                + "\(stats.matches) \(plural(stats.matches, "совпадение", "совпадения", "совпадений"))"
        }
        return "\(stats.blocks) \(stats.blocks == 1 ? "block" : "blocks") · \(stats.matches) \(stats.matches == 1 ? "match" : "matches")"
    }

    /// Русское множественное: 1 блок, 2 блока, 5 блоков, 11 блоков, 21 блок.
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let n10 = n % 10, n100 = n % 100
        if n10 == 1, n100 != 11 { return one }
        if (2...4).contains(n10), !(12...14).contains(n100) { return few }
        return many
    }
}
