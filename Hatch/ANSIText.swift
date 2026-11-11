import SwiftUI

/// Цветной вывод в истории: разбор ANSI SGR, который пишет `TerminalSnapshot`
/// (цвет текста 16/256/truecolor, жирный, тусклый, курсив, подчёркивание).
enum ANSIText {
    private static let escape: Character = "\u{1B}"

    static func strip(_ text: String) -> String {
        text.replacingOccurrences(of: #"\u001B\[[0-9;]*m"#, with: "", options: .regularExpression)
    }

    /// Первые `lines` строк — для превью свёрнутого блока (разбираем не весь вывод).
    static func prefix(_ text: String, lines: Int) -> String {
        text.split(separator: "\n", maxSplits: lines, omittingEmptySubsequences: false)
            .prefix(lines)
            .joined(separator: "\n")
    }

    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString()
        var style = Style()
        var chunk = ""
        var index = text.startIndex

        func flush() {
            guard !chunk.isEmpty else { return }
            result += style.apply(to: AttributedString(chunk))
            chunk = ""
        }

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            guard character == escape, next < text.endIndex, text[next] == "[",
                  let end = text[next...].firstIndex(of: "m") else {
                chunk.append(character)
                index = next
                continue
            }
            flush()
            let params = text[text.index(after: next)..<end]
                .split(separator: ";", omittingEmptySubsequences: false)
                .map { Int($0) ?? 0 }
            style.update(with: params.isEmpty ? [0] : params)
            index = text.index(after: end)
        }
        flush()
        return result
    }

    // MARK: - Style

    private struct Style {
        var foreground: Color?
        var bold = false
        var dim = false
        var italic = false
        var underline = false

        mutating func update(with params: [Int]) {
            var i = 0
            while i < params.count {
                switch params[i] {
                case 0: self = Style()
                case 1: bold = true
                case 2: dim = true
                case 3: italic = true
                case 4: underline = true
                case 30...37: foreground = ANSIText.palette[params[i] - 30]
                case 90...97: foreground = ANSIText.palette[params[i] - 90 + 8]
                case 39: foreground = nil
                case 38 where i + 2 < params.count && params[i + 1] == 5:
                    foreground = ANSIText.color256(params[i + 2])
                    i += 2
                case 38 where i + 4 < params.count && params[i + 1] == 2:
                    foreground = Color(red: Double(params[i + 2]) / 255,
                                       green: Double(params[i + 3]) / 255,
                                       blue: Double(params[i + 4]) / 255)
                    i += 4
                default: break
                }
                i += 1
            }
        }

        func apply(to text: AttributedString) -> AttributedString {
            var text = text
            if let foreground { text.foregroundColor = dim ? foreground.opacity(0.6) : foreground }
            else if dim { text.foregroundColor = .secondary }
            if bold { text.inlinePresentationIntent = .stronglyEmphasized }
            if italic { text.inlinePresentationIntent = (text.inlinePresentationIntent ?? []).union(.emphasized) }
            if underline { text.underlineStyle = .single }
            return text
        }
    }

    // MARK: - Palette

    /// 16 базовых цветов, подобраны под тёмное стекло панели.
    private static let palette: [Color] = [
        rgb(0x4D, 0x4D, 0x4D), rgb(0xF0, 0x5D, 0x5D), rgb(0x5F, 0xD0, 0x7A), rgb(0xE5, 0xC0, 0x5C),
        rgb(0x5C, 0x9C, 0xF5), rgb(0xC6, 0x7E, 0xE8), rgb(0x4F, 0xC8, 0xD8), rgb(0xD0, 0xD0, 0xD0),
        rgb(0x80, 0x80, 0x80), rgb(0xFF, 0x80, 0x80), rgb(0x86, 0xE8, 0x9C), rgb(0xFF, 0xDD, 0x80),
        rgb(0x8A, 0xB8, 0xFF), rgb(0xDD, 0xA4, 0xF5), rgb(0x86, 0xE3, 0xEE), rgb(0xFF, 0xFF, 0xFF),
    ]

    private static func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    /// xterm-256: 16 базовых, куб 6×6×6, 24 оттенка серого.
    private static func color256(_ code: Int) -> Color {
        switch code {
        case 0..<16:
            return palette[code]
        case 16..<232:
            let n = code - 16
            let level = { (v: Int) in v == 0 ? 0 : 55 + v * 40 }
            return rgb(level(n / 36), level((n / 6) % 6), level(n % 6))
        default:
            let gray = 8 + (min(code, 255) - 232) * 10
            return rgb(gray, gray, gray)
        }
    }
}
