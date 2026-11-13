import XCTest
@testable import Hatch

/// Форматирование и подсветка: какой формат, JSON с порядком ключей, SQL с регистром, XML, подсветка.
final class SyntaxTests: XCTestCase {
    private let all = Set(SyntaxKind.allCases)

    func testDetectsFormats() {
        XCTAssertEqual(SyntaxDetector.detect(#"{"b": 1, "a": [true, null]}"#, allowed: all), .json)
        XCTAssertEqual(SyntaxDetector.detect("{\"level\":\"info\"}\n{\"level\":\"error\"}", allowed: all), .jsonLines)
        XCTAssertEqual(SyntaxDetector.detect("select id from orders where id = 1", allowed: all), .sql)
        XCTAssertEqual(SyntaxDetector.detect("WITH t AS (SELECT 1) SELECT * FROM t", allowed: all), .sql)
        XCTAssertEqual(SyntaxDetector.detect("apiVersion: v1\nkind: Pod\nmetadata:\n  name: x", allowed: all), .yaml)
        XCTAssertEqual(SyntaxDetector.detect("<root><a x=\"1\">t</a></root>", allowed: all), .xml)
    }

    func testPlainTextIsNotCode() {
        XCTAssertNil(SyntaxDetector.detect("Созвон перенесли на 16:00.\nПовестка:\n1. Выкатка", allowed: all))
        XCTAssertNil(SyntaxDetector.detect("Select the file you want to open.", allowed: all), "текст со словом select")
        XCTAssertNil(SyntaxDetector.detect("{not json", allowed: all))
        XCTAssertNil(SyntaxDetector.detect(#"{"a": 1}"#, allowed: [.sql]), "JSON выключен в настройках")
    }

    func testJSONKeepsKeyOrder() {
        let result = JSONSyntax.format(#"{"z":1,"a":{"y":[1,2],"b":"x"},"e":[]}"#)
        XCTAssertEqual(result.text, """
        {
          "z": 1,
          "a": {
            "y": [
              1,
              2
            ],
            "b": "x"
          },
          "e": []
        }
        """)
        let key = result.spans.first { $0.token == .key }
        XCTAssertEqual(key.map { (result.text as NSString).substring(with: NSRange(location: $0.location, length: $0.length)) }, "\"z\"")
    }

    func testJSONCompactAndUnicode() {
        let result = JSONSyntax.format("{\n  \"name\": \"Иван \\\"И\\\"\",\n  \"ok\": true\n}", compact: true)
        XCTAssertEqual(result.text, #"{"name": "Иван \"И\"", "ok": true}"#)
        XCTAssertTrue(result.spans.contains { $0.token == .literal })
    }

    func testSQLKeywordCase() {
        let sql = "select o.id, sum(i.qty) as total from orders o join items i on i.oid = o.id where o.status = 'paid' group by o.id"
        let upper = SyntaxService.compute(sql, kind: .sql, mode: .full, options: SyntaxOptions(allowed: all), language: nil)
        XCTAssertTrue(upper.text.hasPrefix("SELECT\n  o.id,"), upper.text)
        XCTAssertTrue(upper.text.contains("\nFROM\n"))
        XCTAssertTrue(upper.spans.contains { $0.token == .keyword }, "подсвечено")
        let lower = SyntaxService.compute(sql, kind: .sql, mode: .compact,
                                          options: SyntaxOptions(allowed: all, sqlCase: "lower"), language: nil)
        XCTAssertTrue(lower.text.hasPrefix("select o.id, sum(i.qty) as total from orders o"), lower.text)
        XCTAssertFalse(lower.text.contains("\n"), "в строке списка — одной строкой")
    }

    func testXMLFormat() {
        let formatted = XMLSyntax.format("<root><a x=\"1\">t</a><b/></root>")
        XCTAssertEqual(formatted?.components(separatedBy: "\n").count, 4, formatted ?? "")
    }

    func testHighlightJSParse() {
        let result = SyntaxEngine.parse(html: #"<span class="hljs-attr">a:</span> <span class="hljs-string">&quot;x&quot; &amp; y</span>"#)
        XCTAssertEqual(result.text, "a: \"x\" & y")
        XCTAssertEqual(result.spans.map(\.token), [.key, .string])
    }

    func testYAMLHighlightKeepsText() {
        let yaml = "apiVersion: v1\nkind: Pod # comment\nspec:\n  - name: app"
        let result = SyntaxService.compute(yaml, kind: .yaml, mode: .full, options: SyntaxOptions(allowed: all), language: nil)
        XCTAssertEqual(result.text, yaml)
        XCTAssertTrue(result.spans.contains { $0.token == .comment })
    }

    /// Цвета для вывода команд: ANSI на каждой строке отдельно — превью разбирает построчно.
    func testANSIPerLine() {
        let h = Highlighted(text: "/* a\nb */ x", spans: [.init(location: 0, length: 9, token: .comment)])
        let lines = SyntaxRender.ansi(h).components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines.allSatisfy { $0.contains("\u{1B}[0m") })
        XCTAssertEqual(ANSIText.attributed(lines[0]).characters.map(String.init).joined(), "/* a")
    }

    func testProgramColorsAreLeftAlone() {
        XCTAssertTrue(ANSIText.hasColor("\u{1B}[32mok\u{1B}[0m"))
        XCTAssertTrue(ANSIText.hasColor("\u{1B}[1;38;5;12mx"))
        XCTAssertFalse(ANSIText.hasColor("\u{1B}[0mplain\u{1B}[1m"), "сброс и жирный — не цвет программы")
        XCTAssertFalse(ANSIText.hasColor("{\"a\": 1}"))
    }

    func testExcludedCommandsAndApps() throws {
        let settings = SettingsStore(defaults: try XCTUnwrap(UserDefaults(suiteName: "SyntaxTests.\(UUID().uuidString)")))
        XCTAssertFalse(settings.formatsByDefault(command: "cat orders.json"))
        XCTAssertFalse(settings.formatsByDefault(command: "/bin/cat orders.json"))
        XCTAssertTrue(settings.formatsByDefault(command: "curl -s https://x"))
        settings.addFormatExcludedApp("com.apple.Terminal")
        XCTAssertFalse(settings.formatsByDefault(bundleID: "com.apple.Terminal"))
        XCTAssertTrue(settings.formatsByDefault(bundleID: "com.apple.Safari"))
        settings.formatByDefault = false
        XCTAssertFalse(settings.formatsByDefault(command: "curl"))
        XCTAssertTrue(settings.syntaxOptions.allowed.contains(.jsonLines), "логи JSON — вместе с JSON")
        settings.toggleFormatKind("json")
        XCTAssertFalse(settings.syntaxOptions.allowed.contains(.jsonLines))
    }

    /// Окно текста меняет размер свободно (не в пропорциях), но не меньше минимума.
    func testTextWindowResizesFreely() {
        let start = NSRect(x: 100, y: 100, width: 400, height: 300)
        let bounds = CGSize(width: 1600, height: 1000)
        let wider = ClipPreviewWindow.resizedFree(start, edges: [.bottom, .right], delta: CGSize(width: 100, height: 0), bounds: bounds)
        XCTAssertEqual(wider.size, CGSize(width: 500, height: 300), "только шире")
        XCTAssertEqual(wider.maxY, start.maxY)
        let tiny = ClipPreviewWindow.resizedFree(start, edges: [.top, .left], delta: CGSize(width: 1000, height: -1000), bounds: bounds)
        XCTAssertEqual(tiny.size, ClipPreviewWindow.minTextSize)
        XCTAssertEqual(tiny.maxX, start.maxX, "правый край на месте")
        XCTAssertEqual(tiny.minY, start.minY, "нижний край на месте")
    }
}

/// Свой формат SQL включается настройкой; в строке списка — всё равно обычный, в одну строку.
final class SQLStyleSettingTests: XCTestCase {
    func testHatchStyleOnlyWhenChosen() {
        let sql = "select a, b from t where x = 1 and y = 2"
        var options = SyntaxOptions(allowed: Set(SyntaxKind.allCases))
        let standard = SyntaxService.compute(sql, kind: .sql, mode: .full, options: options, language: nil)
        XCTAssertTrue(standard.text.hasPrefix("SELECT\n  a,"), standard.text)
        options.sqlStyle = "hatch"
        let hatch = SyntaxService.compute(sql, kind: .sql, mode: .full, options: options, language: nil)
        XCTAssertEqual(hatch.text, "SELECT a\n     , b\nFROM t\nWHERE TRUE\n  AND x = 1\n  AND y = 2")
        XCTAssertTrue(hatch.spans.contains { $0.token == .keyword })
        let row = SyntaxService.compute(sql, kind: .sql, mode: .compact, options: options, language: nil)
        XCTAssertFalse(row.text.contains("\n"))
        // не справился — обычный формат
        let odd = SyntaxService.compute("select (1 from t", kind: .sql, mode: .full, options: options, language: nil)
        XCTAssertFalse(odd.text.isEmpty)
    }
}
