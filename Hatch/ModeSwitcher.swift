import SwiftUI
import AppKit

/// Переключатель режимов панели в строке над полем: команды, поиск (⌘F), буфер (⌘4).
/// Компактный: подпись только у включённого, у остальных — значок, название и клавиша — в подсказке.
/// Включённый подсвечен цветом рамки поля этого режима.
struct ModeSwitcher: View {
    let mode: InputMode
    let lang: String
    var onSelect: (InputMode) -> Void

    private static let modes: [InputMode] = [.command, .search, .clipboard]
    /// Ширина кнопки без подписи.
    static let iconWidth: CGFloat = 26
    static let spacing: CGFloat = 2
    /// Режим, который сейчас нарисован. Догоняет `mode` с небольшой задержкой: смена режима меняет и
    /// высоту панели (буфер ↔ история), и подсветка, начавшая ехать в тот же миг, обрывалась — окно
    /// перекладывалось и анимация перескакивала за два кадра. После перекладки она едет целиком.
    @State private var shown: InputMode?
    @State private var generation = 0

    /// Ширина включённой кнопки — одна на все режимы (по самой длинной подписи): переключатель не меняет
    /// ширину и не съезжает, подсветка только скользит под другую кнопку.
    static func activeWidth(_ lang: String) -> CGFloat {
        let widest = modes.map { titleWidth($0, lang) }.max() ?? 60
        return (widest + 12 + 5 + 18).rounded(.up) // значок, промежуток, поля
    }

    /// Ширина подписи режима.
    static func titleWidth(_ mode: InputMode, _ lang: String) -> CGFloat {
        let font = NSFont.systemFont(ofSize: 11.5, weight: .medium)
        return (title(mode, lang) as NSString).size(withAttributes: [.font: font]).width.rounded(.up)
    }

    var body: some View {
        let active = Self.activeWidth(lang)
        let mode = shown ?? self.mode
        let index = CGFloat(Self.modes.firstIndex(of: mode) ?? 0)
        ZStack(alignment: .leading) {
            // одна подсветка на всех: скользит под включённую кнопку, а не гаснет на одной и загорается на другой
            RoundedRectangle(cornerRadius: 6, style: .circular)
                .fill(Self.color(mode).opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .circular).strokeBorder(.white.opacity(0.14)))
                .frame(width: active, height: 20)
                .offset(x: index * (Self.iconWidth + Self.spacing))
            HStack(spacing: Self.spacing) {
                ForEach(Self.modes, id: \.self) { item in segment(item, active: active, mode: mode) }
            }
        }
        .padding(2)
        .tactileWell(RoundedRectangle(cornerRadius: 8, style: .circular))
        .fixedSize()
        // всё внутри переключателя — всегда пружиной: перекладка окна панели (её высота меняется вместе
        // с режимом) идёт без анимации и обрывала движение подсветки на полпути
        .transaction { $0.animation = .spring(response: 0.32, dampingFraction: 0.86) }
        .onChange(of: self.mode) { _, new in
            generation += 1
            let current = generation
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                guard current == generation else { return } // успели переключить ещё раз — едем к последнему
                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { shown = new }
            }
        }
    }

    private func segment(_ item: InputMode, active: CGFloat, mode: InputMode) -> some View {
        let on = item == mode
        return Button { onSelect(item) } label: {
            // подпись есть всегда, у выключенных — нулевой ширины и прозрачная: не появляется заново.
            // Новая подпись появлялась с положением из момента, когда панель ещё меняла высоту
            // (выход из буфера), и «прыгала» снизу вверх
            HStack(spacing: on ? 5 : 0) {
                Image(systemName: Self.icon(item))
                    .font(.system(size: 10.5, weight: .semibold))
                Text(Self.title(item, lang))
                    .font(.system(size: 11.5, weight: .medium))
                    .lineLimit(1)
                    .fixedSize()
                    .frame(width: on ? Self.titleWidth(item, lang) : 0, alignment: .leading)
                    .clipped()
                    .opacity(on ? 1 : 0)
            }
            .foregroundStyle(on ? Color.white : Color.secondary)
            .frame(width: on ? active : Self.iconWidth, height: 20)
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
