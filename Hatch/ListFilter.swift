import Foundation

/// Фильтр набором в списках Hatch (избранное, выбор приложения, дерево папок).
/// Регистр не важен; набранное в русской раскладке понимается как те же клавиши в латинской
/// (`зл` → `pk`): в списках раскладка сама не переключается.
enum ListFilter {
    /// Насколько хорошо совпало: меньше — выше в списке.
    enum Rank: Int, Comparable {
        /// С начала имени: `pk` → pkpay.
        case namePrefix
        /// С начала слова внутри имени: `base` → account-balance-base, `ut` → MacUtils.
        case wordPrefix
        /// Любая часть имени.
        case nameContains
        /// Только в пути или подписи: `desk` → папка в ~/Desktop.
        case extraContains

        static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }
    }

    private static let russian = Array("йцукенгшщзхъфывапролджэячсмитьбюё")
    private static let latin = Array("qwertyuiop[]asdfghjkl;'zxcvbnm,.`")

    /// Набранное в русской раскладке — теми же клавишами в латинской.
    static func latinLayout(_ text: String) -> String {
        String(text.lowercased().map { character in
            russian.firstIndex(of: character).map { latin[$0] } ?? character
        })
    }

    /// Совпадение с именем (и подписью — путём, если есть). nil — не совпало.
    /// Пробуется набранное как есть (русские имена папок) и в латинской раскладке.
    static func rank(_ query: String, name: String, extra: String? = nil) -> Rank? {
        let typed = query.lowercased()
        guard !typed.isEmpty else { return .namePrefix }
        let variants = Set([typed, latinLayout(typed)])
        return variants.compactMap { rank(normalized: $0, name: name, extra: extra) }.min()
    }

    private static func rank(normalized query: String, name: String, extra: String?) -> Rank? {
        let lower = name.lowercased()
        if lower.hasPrefix(query) { return .namePrefix }
        if wordStarts(in: name).contains(where: { lower[$0...].hasPrefix(query) }) { return .wordPrefix }
        if lower.contains(query) { return .nameContains }
        if let extra, extra.lowercased().contains(query) { return .extraContains }
        return nil
    }

    /// Начала слов: после `-`, `_`, `.`, пробела и т. п., и заглавная после строчной (MacUtils).
    private static func wordStarts(in name: String) -> [String.Index] {
        var starts: [String.Index] = []
        var previous: Character?
        for index in name.indices {
            let character = name[index]
            if let previous, character.isLetter || character.isNumber {
                let afterSeparator = !(previous.isLetter || previous.isNumber)
                let camelCase = character.isUppercase && previous.isLowercase
                if afterSeparator || camelCase { starts.append(index) }
            }
            previous = character
        }
        return starts
    }

    /// Совпавшие, лучшие выше; при равном совпадении — в прежнем порядке.
    static func filter<T>(_ items: [T], query: String, name: (T) -> String, extra: (T) -> String? = { _ in nil }) -> [T] {
        guard !query.isEmpty else { return items }
        return items.enumerated()
            .compactMap { offset, item in rank(query, name: name(item), extra: extra(item)).map { (offset, $0, item) } }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
            .map(\.2)
    }

    /// Как `filter`, но у элемента несколько имён (приложение: «Терминал» и Terminal) — берётся лучшее совпадение.
    static func filter<T>(_ items: [T], query: String, names: (T) -> [String]) -> [T] {
        guard !query.isEmpty else { return items }
        return items.enumerated()
            .compactMap { offset, item in names(item).compactMap { rank(query, name: $0) }.min().map { (offset, $0, item) } }
            .sorted { ($0.1, $0.0) < ($1.1, $1.0) }
            .map(\.2)
    }

    /// Где в тексте совпало набранное (как есть или в латинской раскладке) — для подсветки.
    static func matchRange(_ query: String, in text: String) -> Range<String.Index>? {
        guard !query.isEmpty else { return nil }
        for variant in [query.lowercased(), latinLayout(query)] {
            if let range = text.range(of: variant, options: [.caseInsensitive, .diacriticInsensitive]) { return range }
        }
        return nil
    }

    /// Буква для фильтра: буквы, цифры и знаки, которые бывают в именах (`-_./`), опционально пробел.
    static func accepts(_ character: Character, space: Bool) -> Bool {
        character.isLetter || character.isNumber || "-_./".contains(character) || (space && character == " ")
    }
}
