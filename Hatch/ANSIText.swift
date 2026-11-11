import SwiftUI
import AppKit

/// Цветной вывод в истории: разбор ANSI SGR, который пишет `TerminalSnapshot`
/// (цвет текста 16/256/truecolor, жирный, тусклый, курсив, подчёркивание).
/// Результат кешируется по самому тексту: перерисовка того же вывода не разбирает его заново,
/// а новый вывод — это новый текст и новый разбор, поэтому реальное время не страдает.
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

    /// Для SwiftUI `Text` (превью строк в блоках).
    static func attributed(_ text: String) -> AttributedString {
        if let cached = swiftUICache.object(forKey: text as NSString) { return cached.value }
        var result = AttributedString()
        for (chunk, style) in runs(text) {
            result += style.apply(to: AttributedString(chunk))
        }
        swiftUICache.setObject(Box(result), forKey: text as NSString, cost: text.utf8.count)
        return result
    }

    /// Для нативного текстового поля (раскрытый вывод): цвет и начертание — атрибутами AppKit.
    static func nsAttributed(_ text: String, font: NSFont) -> NSAttributedString {
        let key = "\(font.pointSize)|\(text)" as NSString
        if let cached = appKitCache.object(forKey: key) { return cached.value }
        let result = NSMutableAttributedString()
        for (chunk, style) in runs(text) {
            result.append(NSAttributedString(string: chunk, attributes: style.appKitAttributes(font: font)))
        }
        appKitCache.setObject(Box(result), forKey: key, cost: text.utf8.count)
        return result
    }

    // MARK: - Разбор

    /// Текст, разрезанный на куски одного оформления.
    private static func runs(_ text: String) -> [(String, Style)] {
        var result: [(String, Style)] = []
        var style = Style()
        var chunk = ""
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            let next = text.index(after: index)
            guard character == escape, next < text.endIndex, text[next] == "[",
                  let end = text[next...].firstIndex(of: "m") else {
                chunk.append(character)
                index = next
                continue
            }
            if !chunk.isEmpty {
                result.append((chunk, style))
                chunk = ""
            }
            let params = text[text.index(after: next)..<end]
                .split(separator: ";", omittingEmptySubsequences: false)
                .map { Int($0) ?? 0 }
            style.update(with: params.isEmpty ? [0] : params)
            index = text.index(after: end)
        }
        if !chunk.isEmpty { result.append((chunk, style)) }
        return result
    }

    // MARK: - Кеш

    private final class Box<Value> {
        let value: Value
        init(_ value: Value) { self.value = value }
    }

    /// Ограничен по объёму текста: старое вытесняется само.
    private static let swiftUICache: NSCache<NSString, Box<AttributedString>> = {
        let cache = NSCache<NSString, Box<AttributedString>>()
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()

    private static let appKitCache: NSCache<NSString, Box<NSAttributedString>> = {
        let cache = NSCache<NSString, Box<NSAttributedString>>()
        cache.totalCostLimit = 16 * 1024 * 1024
        return cache
    }()

    // MARK: - Оформление

    private struct RGB: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        init(_ red: Int, _ green: Int, _ blue: Int) {
            self.red = Double(red) / 255
            self.green = Double(green) / 255
            self.blue = Double(blue) / 255
        }

        var color: Color { Color(red: red, green: green, blue: blue) }
        var nsColor: NSColor { NSColor(srgbRed: red, green: green, blue: blue, alpha: 1) }
    }

    private struct Style {
        var foreground: RGB?
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
                    foreground = RGB(params[i + 2], params[i + 3], params[i + 4])
                    i += 4
                default: break
                }
                i += 1
            }
        }

        func apply(to text: AttributedString) -> AttributedString {
            var text = text
            if let foreground { text.foregroundColor = dim ? foreground.color.opacity(0.6) : foreground.color }
            else if dim { text.foregroundColor = .secondary }
            if bold { text.inlinePresentationIntent = .stronglyEmphasized }
            if italic { text.inlinePresentationIntent = (text.inlinePresentationIntent ?? []).union(.emphasized) }
            if underline { text.underlineStyle = .single }
            return text
        }

        func appKitAttributes(font: NSFont) -> [NSAttributedString.Key: Any] {
            var traits: NSFontTraitMask = []
            if bold { traits.insert(.boldFontMask) }
            if italic { traits.insert(.italicFontMask) }
            let styledFont = traits.isEmpty ? font : NSFontManager.shared.convert(font, toHaveTrait: traits)

            var color = foreground?.nsColor ?? .labelColor
            if dim { color = foreground == nil ? .secondaryLabelColor : color.withAlphaComponent(0.6) }

            var attributes: [NSAttributedString.Key: Any] = [.font: styledFont, .foregroundColor: color]
            if underline { attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue }
            return attributes
        }
    }

    // MARK: - Палитра

    /// 16 базовых цветов, подобраны под тёмное стекло панели.
    private static let palette: [RGB] = [
        RGB(0x4D, 0x4D, 0x4D), RGB(0xF0, 0x5D, 0x5D), RGB(0x5F, 0xD0, 0x7A), RGB(0xE5, 0xC0, 0x5C),
        RGB(0x5C, 0x9C, 0xF5), RGB(0xC6, 0x7E, 0xE8), RGB(0x4F, 0xC8, 0xD8), RGB(0xD0, 0xD0, 0xD0),
        RGB(0x80, 0x80, 0x80), RGB(0xFF, 0x80, 0x80), RGB(0x86, 0xE8, 0x9C), RGB(0xFF, 0xDD, 0x80),
        RGB(0x8A, 0xB8, 0xFF), RGB(0xDD, 0xA4, 0xF5), RGB(0x86, 0xE3, 0xEE), RGB(0xFF, 0xFF, 0xFF),
    ]

    /// xterm-256: 16 базовых, куб 6×6×6, 24 оттенка серого.
    private static func color256(_ code: Int) -> RGB {
        switch code {
        case 0..<16:
            return palette[code]
        case 16..<232:
            let n = code - 16
            let level = { (v: Int) in v == 0 ? 0 : 55 + v * 40 }
            return RGB(level(n / 36), level((n / 6) % 6), level(n % 6))
        default:
            let gray = 8 + (min(code, 255) - 232) * 10
            return RGB(gray, gray, gray)
        }
    }
}
