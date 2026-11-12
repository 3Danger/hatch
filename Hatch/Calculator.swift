import Foundation

/// Калькулятор в поле ввода, как в Spotlight: `12*3.5`, `(1200-150)/3`, `2^10`, `4500*15%`.
/// Считает, только если в строке одни числа и знаки действий и есть хотя бы одно действие:
/// одно число (`42`, `-5`) — это ввод команды, а не расчёт.
enum Calculator {
    enum Outcome: Equatable {
        case value(Double)
        case divisionByZero
    }

    /// nil — не выражение (буквы, одно число, незаконченное `12*`): поле работает как обычно.
    static func evaluate(_ text: String) -> Outcome? {
        let source = text.trimmingCharacters(in: .whitespaces)
        guard looksLikeExpression(source) else { return nil }
        var parser = Parser(Array(source))
        do {
            let value = try parser.parse()
            guard value.isFinite else { return nil }
            return .value(value == 0 ? 0 : value) // без «-0»
        } catch Parser.Failure.divisionByZero {
            return .divisionByZero
        } catch {
            return nil
        }
    }

    /// Результат для подписи: с разделителем разрядов, до 10 знаков после запятой, как в системе.
    static func display(_ value: Double, locale: Locale = .current) -> String {
        format(value, locale: locale, grouping: true)
    }

    /// В буфер: то же число без разделителя разрядов — чтобы вставлялось как число.
    static func clipboard(_ value: Double, locale: Locale = .current) -> String {
        format(value, locale: locale, grouping: false)
    }

    private static func format(_ value: Double, locale: Locale, grouping: Bool) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = grouping
        formatter.maximumFractionDigits = 10
        formatter.minimumFractionDigits = 0
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }

    private static let allowed = Set("0123456789.,+-*/^%()×÷ ")
    private static let actions = Set("+*/^%×÷")

    /// Одни цифры и знаки, есть цифра и действие. Минус в начале числа — не действие (`-5`),
    /// а между числами — действие (`10-3`).
    private static func looksLikeExpression(_ text: String) -> Bool {
        guard !text.isEmpty, text.allSatisfy(allowed.contains), text.contains(where: \.isNumber) else { return false }
        if text.contains(where: actions.contains) { return true }
        let chars = Array(text.filter { $0 != " " })
        return chars.indices.contains { index in
            chars[index] == "-" && index > 0 && (chars[index - 1].isNumber || chars[index - 1] == ")" || chars[index - 1] == ".")
        }
    }

    /// Рекурсивный спуск: сложение < умножение < степень (справа налево) < унарный минус < проценты.
    private struct Parser {
        enum Failure: Error { case syntax, divisionByZero }

        private let chars: [Character]
        private var position = 0

        init(_ chars: [Character]) { self.chars = chars }

        mutating func parse() throws -> Double {
            let value = try sum()
            skipSpaces()
            guard position == chars.count else { throw Failure.syntax }
            return value
        }

        private mutating func sum() throws -> Double {
            var value = try product()
            while let op = take(["+", "-"]) {
                let right = try product()
                value = op == "+" ? value + right : value - right
            }
            return value
        }

        private mutating func product() throws -> Double {
            var value = try unary()
            while let op = take(["*", "/", "×", "÷"]) {
                let right = try unary()
                if op == "*" || op == "×" {
                    value *= right
                } else {
                    guard right != 0 else { throw Failure.divisionByZero }
                    value /= right
                }
            }
            return value
        }

        /// `-2^2` = −4, как в математике и Spotlight.
        private mutating func unary() throws -> Double {
            if take(["-"]) != nil { return -(try unary()) }
            return try power()
        }

        private mutating func power() throws -> Double {
            let base = try percent()
            guard take(["^"]) != nil else { return base }
            let exponent = try unary()
            return pow(base, exponent)
        }

        /// `15%` — это 0.15, так что `4500*15%` = 675.
        private mutating func percent() throws -> Double {
            var value = try primary()
            while take(["%"]) != nil { value /= 100 }
            return value
        }

        private mutating func primary() throws -> Double {
            skipSpaces()
            if take(["("]) != nil {
                let value = try sum()
                guard take([")"]) != nil else { throw Failure.syntax }
                return value
            }
            return try number()
        }

        /// Дробная часть — через точку или запятую: `1.5` и `1,5`.
        private mutating func number() throws -> Double {
            skipSpaces()
            var digits = ""
            var hasSeparator = false
            while position < chars.count {
                let char = chars[position]
                if char.isNumber {
                    digits.append(char)
                } else if char == "." || char == "," {
                    guard !hasSeparator else { throw Failure.syntax }
                    hasSeparator = true
                    digits.append(".")
                } else {
                    break
                }
                position += 1
            }
            guard digits.contains(where: \.isNumber), let value = Double(digits) else { throw Failure.syntax }
            return value
        }

        private mutating func take(_ options: Set<Character>) -> Character? {
            skipSpaces()
            guard position < chars.count, options.contains(chars[position]) else { return nil }
            defer { position += 1 }
            return chars[position]
        }

        private mutating func skipSpaces() {
            while position < chars.count, chars[position] == " " { position += 1 }
        }
    }
}
