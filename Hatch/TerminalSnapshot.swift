import SwiftTerm

/// Текст экрана терминала: чистый (копирование, поиск, тесты) и с цветом (ANSI SGR, для блоков).
/// Строится из буфера эмулятора, а не из сырого потока: перемещения курсора, `\r` прогресс-баров
/// и перерисовки уже применены — остаётся то, что видно в терминале.
struct TerminalSnapshot: Equatable {
    var plain: String
    var ansi: String
    /// Пропущенная середина, если снят только край вывода (превью работающей команды).
    var gap: OutputGap?

    static let empty = TerminalSnapshot(plain: "", ansi: "")

    /// - Parameters:
    ///   - head: сколько логических строк взять с начала; nil — весь вывод;
    ///   - tail: сколько строк взять с конца (вместе с `head`, середина — числом в `gap`).
    static func capture(_ terminal: Terminal, head: Int? = nil, tail: Int = 0) -> TerminalSnapshot {
        // полноэкранная программа (vim, top) после себя текста не оставляет
        guard !terminal.isCurrentBufferAlternate else { return .empty }

        // Логические строки: строка, перенесённая по ширине терминала, — продолжение предыдущей.
        // Клетки разбираем только у строк, которые попадут в снимок: середина длинного
        // вывода не стоит ничего, кроме подсчёта.
        var groups: [[BufferLine]] = []
        var row = terminal.buffer.totalLinesTrimmed
        while let line = terminal.getScrollInvariantLine(row: row) {
            row += 1
            if line.isWrapped, !groups.isEmpty {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }

        var cache: [Int: [Cell]] = [:]
        func content(_ index: Int) -> [Cell] {
            if let cached = cache[index] { return cached }
            var cells = groups[index].flatMap(Self.cells(of:))
            while let last = cells.last, last.character == " " { cells.removeLast() }
            cache[index] = cells
            return cells
        }

        // пустые строки по краям (в том числе незанятые строки экрана под курсором) не нужны
        var start = 0
        var end = groups.count
        while start < end, content(start).isEmpty { start += 1 }
        while end > start, content(end - 1).isEmpty { end -= 1 }

        let total = end - start
        var indices = Array(start..<end)
        var gap: OutputGap?
        if let head, head + tail < total {
            indices = Array(start..<(start + head)) + Array((end - tail)..<end)
            gap = OutputGap(after: head, count: total - head - tail)
        }

        let lines = indices.map(content)
        let plain = lines.map { String($0.map(\.character)) }.joined(separator: "\n")
        let ansi = lines.map(Self.encode).joined(separator: "\n")
        return TerminalSnapshot(plain: plain, ansi: ansi, gap: gap)
    }

    // MARK: - Private

    private struct Cell {
        let character: Character
        let style: Style
    }

    /// Что из оформления переносим в историю: цвет текста и начертание (фон — нет).
    private struct Style: Equatable {
        var foreground: Attribute.Color = .defaultColor
        var bold = false
        var dim = false
        var italic = false
        var underline = false

        var isDefault: Bool { self == Style() }
    }

    private static func cells(of line: BufferLine) -> [Cell] {
        (0..<line.count).compactMap { index in
            let data = line[index]
            guard data.width > 0 else { return nil } // вторая половина широкого символа
            let character = data.getCharacter()
            let style = data.attribute.style
            return Cell(
                character: character == "\u{0}" ? " " : character,
                style: Style(foreground: data.attribute.fg,
                             bold: style.contains(.bold),
                             dim: style.contains(.dim),
                             italic: style.contains(.italic),
                             underline: style.contains(.underline))
            )
        }
    }

    private static func encode(_ line: [Cell]) -> String {
        var result = ""
        var current = Style()
        for cell in line {
            if cell.style != current {
                result += sgr(cell.style)
                current = cell.style
            }
            result.append(cell.character)
        }
        if !current.isDefault { result += sgr(Style()) }
        return result
    }

    /// Полный набор атрибутов с нуля (`0;…`): каждая последовательность самодостаточна.
    private static func sgr(_ style: Style) -> String {
        var codes = ["0"]
        if style.bold { codes.append("1") }
        if style.dim { codes.append("2") }
        if style.italic { codes.append("3") }
        if style.underline { codes.append("4") }
        switch style.foreground {
        case .ansi256(let code) where code < 8:
            codes.append(String(30 + Int(code)))
        case .ansi256(let code) where code < 16:
            codes.append(String(90 + Int(code) - 8))
        case .ansi256(let code):
            codes.append("38;5;\(code)")
        case .trueColor(let r, let g, let b):
            codes.append("38;2;\(r);\(g);\(b)")
        case .defaultColor, .defaultInvertedColor:
            break
        }
        return "\u{1B}[" + codes.joined(separator: ";") + "m"
    }
}
