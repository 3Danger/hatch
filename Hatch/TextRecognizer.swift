import Foundation
import Vision

/// Текст со скриншота — встроенным в macOS распознаванием (Vision), без сети. Русский и английский.
/// По одной картинке за раз и с низким приоритетом: десять скриншотов подряд не тормозят панель.
final class TextRecognizer {
    static let shared = TextRecognizer()

    private let queue = DispatchQueue(label: "io.github.3danger.hatch.ocr", qos: .utility)

    /// Распознать и вернуть текст на главном потоке (строки через перевод строки; пусто — текста нет).
    func recognize(_ url: URL, completion: @escaping (String) -> Void) {
        queue.async {
            let text = Self.recognizeNow(url)
            DispatchQueue.main.async { completion(text) }
        }
    }

    /// Синхронно — для фона и тестов.
    static func recognizeNow(_ url: URL) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["ru-RU", "en-US"]
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(url: url)
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
    }
}
