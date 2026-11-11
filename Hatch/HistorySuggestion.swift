import Foundation

/// Подсказка из истории, как в fish / zsh-autosuggestions: последняя команда,
/// начинающаяся с набранного текста.
enum HistorySuggestion {
    /// - Parameter history: команды от новых к старым.
    static func completion(for text: String, in history: [String]) -> String? {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return history.first { $0.hasPrefix(text) && $0 != text }
    }
}
