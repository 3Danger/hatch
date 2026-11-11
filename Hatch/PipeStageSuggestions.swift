import Foundation

/// Варианты для шага конвейера: свои недавние шаги → частые фильтры → дополнения шелла
/// (команды, алиасы, файлы в директории команды). Все варианты — строкой целиком.
enum PipeStageSuggestions {
    static let limit = 8

    /// Частые обработчики вывода.
    static let commonFilters = ["grep", "sort", "uniq -c", "head", "tail", "wc -l", "jq", "awk", "cut", "sed", "xargs"]

    /// - Parameters:
    ///   - history: уже применявшиеся шаги, свежие первыми;
    ///   - completions: дополнения шелла для набранного текста — строками целиком.
    static func candidates(for text: String, history: [String], completions: [String]) -> [String] {
        let typed = text.trimmingCharacters(in: .whitespaces)
        let sources: [String]
        if typed.isEmpty {
            sources = Array(history.prefix(5)) + commonFilters
        } else {
            sources = history + commonFilters + completions
        }

        var seen = Set<String>()
        var result: [String] = []
        for candidate in sources where candidate.hasPrefix(text) && candidate != text {
            guard seen.insert(candidate).inserted else { continue }
            result.append(candidate)
            if result.count == limit { break }
        }
        return result
    }
}
