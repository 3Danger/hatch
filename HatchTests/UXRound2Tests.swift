import XCTest
import AppKit
@testable import Hatch

/// Второй UX-разбор: длительность и дата у блоков, вставка из буфера, шпаргалка, компактная история.
final class UXRound2Tests: XCTestCase {
    func testDurationText() {
        XCTAssertEqual(SessionBlockView.durationText(0.04, lang: "ru"), "0,0 с")
        XCTAssertEqual(SessionBlockView.durationText(2.44, lang: "ru"), "2,4 с")
        XCTAssertEqual(SessionBlockView.durationText(2.44, lang: "en"), "2.4 s")
        XCTAssertEqual(SessionBlockView.durationText(12.7, lang: "ru"), "12 с", "от 10 секунд — без десятых")
        XCTAssertEqual(SessionBlockView.durationText(3.7, lang: "ru", live: true), "3 с", "секундомер — целые секунды")
        XCTAssertEqual(SessionBlockView.durationText(65, lang: "ru"), "1:05")
        XCTAssertEqual(SessionBlockView.durationText(3723, lang: "ru"), "1:02:03")
        XCTAssertEqual(SessionBlockView.durationText(-1, lang: "ru"), "0,0 с")
    }

    func testSessionDurationCountsFromRerun() {
        let start = Date(timeIntervalSince1970: 1_000)
        var session = Session(command: "make", state: .completed, createdAt: start, finishedAt: start.addingTimeInterval(4))
        XCTAssertEqual(session.duration(), 4)
        session.startedAt = start.addingTimeInterval(100) // повтор ⌘R
        session.finishedAt = start.addingTimeInterval(102.5)
        XCTAssertEqual(session.duration(), 2.5)
        let running = Session(command: "sleep 9", state: .running, createdAt: start)
        XCTAssertEqual(running.duration(now: start.addingTimeInterval(7)), 7, "идущая — до сейчас")
        let legacy = Session(command: "ls", state: .stopped, createdAt: start)
        XCTAssertNil(legacy.duration(), "старая без времени окончания — без длительности")
    }

    func testWhenTextAddsDayForOlderBlocks() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 12))!
        let today = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 3, minute: 6))!
        let yesterday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 13, hour: 18, minute: 40))!
        let older = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 9))!
        let lastYear = calendar.date(from: DateComponents(year: 2025, month: 12, day: 30, hour: 9))!
        let time = { (d: Date) in d.formatted(date: .omitted, time: .shortened) }
        XCTAssertEqual(SessionBlockView.whenText(today, now: now, lang: "ru", calendar: calendar), time(today))
        XCTAssertEqual(SessionBlockView.whenText(yesterday, now: now, lang: "ru", calendar: calendar), "вчера " + time(yesterday))
        XCTAssertEqual(SessionBlockView.whenText(yesterday, now: now, lang: "en", calendar: calendar), "yesterday " + time(yesterday))
        let olderText = SessionBlockView.whenText(older, now: now, lang: "ru", calendar: calendar)
        XCTAssertTrue(olderText.contains("2") && olderText.contains("нояб"), olderText)
        XCTAssertFalse(olderText.contains("2026"), "этот год — без года: \(olderText)")
        XCTAssertTrue(SessionBlockView.whenText(lastYear, now: now, lang: "ru", calendar: calendar).contains("2025"))
    }

    func testKeysSheetShowsPasteWhenEnterPastes() {
        let copying = KeysSheetView.groups(mode: .clipboard, hotkey: "⌥Space", lang: "ru").flatMap(\.rows)
        XCTAssertEqual(copying.first { $0.key == "↩" }?.what, "копировать")
        XCTAssertFalse(copying.contains { $0.key == "⌘C" })
        let pasting = KeysSheetView.groups(mode: .clipboard, hotkey: "⌥Space", pastes: true, lang: "ru").flatMap(\.rows)
        XCTAssertEqual(pasting.first { $0.key == "↩" }?.what, "вставить в приложение")
        XCTAssertEqual(pasting.first { $0.key == "⌘C" }?.what, "копировать")
    }

    func testKeysColumnFitsLongestKey() {
        let groups = KeysSheetView.groups(mode: .command, hotkey: "⌥Space", lang: "ru")
        XCTAssertGreaterThan(KeysSheetView.keyColumn(groups), 44, "⌥Space шире колонки по умолчанию")
        XCTAssertEqual(KeysSheetView.keyColumn([KeysSheetView.Group(title: "x", rows: [("⌘C", "c")])]), 44)
    }

    func testPasteTargetIgnoresHatchItself() {
        PasteBack.rememberFrontmost(NSRunningApplication.current)
        XCTAssertNotEqual(PasteBack.target?.processIdentifier, getpid(), "сам Hatch — не цель вставки")
    }

    func testCompactHistoryDefaultsOnAndResets() {
        let defaults = UserDefaults(suiteName: "UXRound2.\(UUID().uuidString)")!
        let settings = SettingsStore(defaults: defaults)
        XCTAssertTrue(settings.compactHistory)
        XCTAssertTrue(settings.clipboardPasteOnEnter)
        settings.compactHistory = false
        settings.clipboardPasteOnEnter = false
        XCTAssertFalse(SettingsStore(defaults: defaults).compactHistory, "сохраняется")
        settings.resetToDefaults()
        XCTAssertTrue(settings.compactHistory)
        XCTAssertTrue(settings.clipboardPasteOnEnter)
    }
}

/// Буфер: текст записи до N строк, отформатированный — по строкам формата.
final class ClipRowLinesTests: XCTestCase {
    func testRowShowsUpToLimitLines() {
        let text = AttributedString((1...14).map { "line \($0)" }.joined(separator: "\n"))
        let shown = ClipboardListView.rowText(text, limit: 10).map { String($0.characters) }
        XCTAssertEqual(shown.count, 10)
        XCTAssertEqual(shown.first, "line 1")
        XCTAssertEqual(shown.last, "line 10")
        XCTAssertEqual(ClipboardListView.rowText(AttributedString("one"), limit: 10).map { String($0.characters) }, ["one"])
        XCTAssertEqual(ClipboardListView.rowText(AttributedString(""), limit: 10).count, 1, "пустая — одна строка")
    }

    func testRowKeepsFormatting() {
        var keyword = AttributedString("SELECT")
        keyword.foregroundColor = .purple
        var text = keyword
        text.append(AttributedString(" id\nFROM t"))
        let lines = ClipboardListView.rowText(text, limit: 10)
        XCTAssertEqual(lines.map { String($0.characters) }, ["SELECT id", "FROM t"])
        XCTAssertEqual(lines[0].runs.first?.foregroundColor, .purple, "подсветка остаётся в строке")
    }

    func testRowHeightGrowsPerLine() {
        XCTAssertEqual(ClipboardListView.rowHeight(lines: 2) - ClipboardListView.rowHeight(lines: 1), 17)
        XCTAssertEqual(ClipboardListView.rowHeight(lines: 0), ClipboardListView.rowHeight(lines: 1))
    }

    func testRowLinesSettingClamped() {
        let defaults = UserDefaults(suiteName: "ClipRowLines.\(UUID().uuidString)")!
        XCTAssertEqual(SettingsStore(defaults: defaults).clipboardRowLines, 10)
        defaults.set(99, forKey: "settings.clipboardRowLines")
        XCTAssertEqual(SettingsStore(defaults: defaults).clipboardRowLines, 30)
    }
}

/// ↩ в буфере копирует запись, как она видна: отформатированную; в истории — та же запись, без копии.
final class FormattedCopyTests: XCTestCase {
    func testFormattedCopyBumpsOriginalClip() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("hatch-tests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "FormattedCopy.\(UUID().uuidString)")!)
        let history = ClipboardHistory(fileURL: nil)
        let raw = "{\"id\":42,\"ok\":true}"
        history.record(Clip(text: raw, app: "Code", bundleID: nil, copiedAt: Date()), days: 7)
        history.record(Clip(text: "other", app: "Safari", bundleID: nil, copiedAt: Date()), days: 7)
        let watcher = ClipboardWatcher(pasteboard: pasteboard, history: history, settings: settings, frontmost: { nil })
        let formatted = "{\n  \"id\": 42,\n  \"ok\": true\n}"
        Clipboard.copy(formatted, source: raw, to: pasteboard)
        XCTAssertEqual(pasteboard.string(forType: .string), formatted, "вставится отформатированный")
        watcher.poll()
        XCTAssertEqual(history.clips.map(\.text), [raw, "other"], "та же запись поднялась наверх, новой нет")
        XCTAssertEqual(history.clips.first?.app, "Code")
    }
}

/// Подсказки кнопок: каталог действий и место подсказки на экране.
final class HatchTipsTests: XCTestCase {
    private let all: [HatchAction] = [
        .copyOutput, .rerun, .stop, .blockMenu, .addFilter, .pasteInto("Terminal"), .pasteInto(nil), .copyClipToPaste,
        .copyClipOnly, .insertClip, .insertPath, .previewClip, .formatOn, .formatOff, .pinClip, .unpinClip, .deleteClip,
        .favorites, .settings, .modeCommands, .modeSearch, .modeClipboard, .copyAll, .pinWindow, .unpinWindow,
        .closePreview(pinned: false), .closePreview(pinned: true),
    ]

    func testEveryActionDescribesItselfInBothLanguages() {
        for action in all {
            XCTAssertFalse(action.text("ru").isEmpty, "\(action)")
            XCTAssertFalse(action.text("en").isEmpty, "\(action)")
            XCTAssertNotEqual(action.text("ru"), action.text("en"), "\(action) переведено")
        }
        XCTAssertEqual(HatchAction.pasteInto("Terminal").text("ru"), "Вставить в Terminal")
        XCTAssertEqual(HatchAction.closePreview(pinned: true).key, "⌘W")
        XCTAssertEqual(HatchAction.closePreview(pinned: false).key, "Esc")
        XCTAssertNil(HatchAction.addFilter.key, "фильтр — только мышью")
    }

    func testKeysMatchKeysSheetAndMenu() {
        let block = KeysSheetView.groups(mode: .command, hotkey: "⌥Space", lang: "ru").flatMap(\.rows)
        XCTAssertEqual(block.first { $0.what == "копировать вывод" }?.key, HatchAction.copyOutput.key)
        XCTAssertEqual(block.first { $0.what == "повторить" }?.key, HatchAction.rerun.key)
        let clip = KeysSheetView.groups(mode: .clipboard, hotkey: "⌥Space", pastes: true, lang: "ru").flatMap(\.rows)
        XCTAssertEqual(clip.first { $0.what == "крупно" }?.key, HatchAction.previewClip.key)
        XCTAssertEqual(clip.first { $0.what == "вставить в приложение" }?.key, HatchAction.pasteInto(nil).key)
    }

    func testTipStaysOnScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1000, height: 800)
        let size = CGSize(width: 200, height: 46)
        let middle = TipCenter.origin(for: size, above: NSRect(x: 400, y: 300, width: 24, height: 24), in: screen)
        XCTAssertEqual(middle.x, 312, "по центру кнопки")
        XCTAssertEqual(middle.y, 330, "над кнопкой")
        let right = TipCenter.origin(for: size, above: NSRect(x: 980, y: 300, width: 20, height: 24), in: screen)
        XCTAssertEqual(right.x, 1000 - 200 - 4, "у правого края — внутрь экрана")
        let top = TipCenter.origin(for: size, above: NSRect(x: 400, y: 770, width: 24, height: 24), in: screen)
        XCTAssertLessThan(top.y, 770, "сверху места нет — под кнопкой")
    }
}

/// SQL-скрипт с командами psql и инструкциями вокруг запросов: узнаётся как SQL, запросы форматируются,
/// остальное остаётся как написано.
final class SQLScriptTests: XCTestCase {
    private let script = """
    -- Очистка технических таблиц, перенесённых с боя. Выполнять последним: в конце возвращает место на диске.
    \\set ON_ERROR_STOP on

    BEGIN;

    -- Ключи идемпотентности боевых запросов тестам не нужны.
    TRUNCATE TABLE cashoperations.delayed_messages, cashoperations.idempotency_requests;

    -- Схема не зафиксирована, поэтому удаляем из обеих.
    DROP TABLE IF EXISTS
        cashoperations._tmp_email_phone,
        public._tmp_wtis_users;

    COMMIT;

    -- Работает вне транзакции; ANALYZE обновляет статистику после массового удаления.
    VACUUM (FULL, ANALYZE);
    """

    func testScriptIsRecognizedAsSQL() {
        XCTAssertTrue(SyntaxDetector.isSQL(script), "команда psql в начале — не повод не узнать SQL")
        XCTAssertTrue(SyntaxDetector.isSQL("BEGIN;\nUPDATE t SET a = 1;\nCOMMIT;"))
        XCTAssertTrue(SyntaxDetector.isSQL("VACUUM (FULL, ANALYZE);"))
        XCTAssertFalse(SyntaxDetector.isSQL("Begin with the basics, then read the docs."), "обычная речь")
        XCTAssertFalse(SyntaxDetector.isSQL("Commit message: fix the build"))
        XCTAssertFalse(SyntaxDetector.isSQL("Analyze the logs before the release"))
    }

    func testScriptWithoutQueriesStaysAsWritten() {
        XCTAssertNil(HatchPG.format(script), "запросов нет — формату Hatch нечего делать")
        let shown = SyntaxService.compute(script, kind: .sql, mode: .full,
                                          options: SyntaxOptions(allowed: [.sql], sqlStyle: "hatch"), language: nil)
        XCTAssertEqual(shown.text, script, "показывается как написан, с подсветкой")
    }

    func testQueriesInScriptAreFormattedRestKept() throws {
        let mixed = """
        \\set ON_ERROR_STOP on
        BEGIN;
        -- активные заказы
        select id, total from orders where status = 'paid' and total > 0;
        DROP TABLE IF EXISTS
            public._tmp_a,
            public._tmp_b;
        COMMIT;
        """
        let out = try XCTUnwrap(HatchPG.format(mixed))
        XCTAssertTrue(out.hasPrefix("\\set ON_ERROR_STOP on\nBEGIN;"), "пустых строк во входе не было — и не появилось: \(out)")
        XCTAssertTrue(out.contains("-- активные заказы\nSELECT"), out)
        XCTAssertTrue(out.contains("WHERE TRUE\n  AND status = 'paid'\n  AND total > 0;"), out)
        XCTAssertTrue(out.contains("DROP TABLE IF EXISTS\n    public._tmp_a,\n    public._tmp_b;"), "как написано: \(out)")
        XCTAssertTrue(out.hasSuffix("public._tmp_b;\nCOMMIT;"), out)
    }

    /// Скрипт из нескольких запросов: каждый — по правилам Hatch, `CREATE TEMP TABLE … AS` — заголовком
    /// над запросом, ANALYZE — как написан, переменные psql (`:'cutoff'`) — словом, комментарий — над своим AND.
    func testCreateTableAsScript() throws {
        let script = """
        CREATE TEMP TABLE k_co AS
        SELECT c.guid
        FROM cashorder c
        WHERE c.document_ts >= :'cutoff'::timestamp
            OR c.change_ts >= :'cutoff'::timestamp
            OR EXISTS (SELECT 1 FROM k_ord k WHERE k.guid = c.settlement_object);

        ANALYZE k_co;

        CREATE TEMP TABLE d_rr AS
        SELECT r.guid
        FROM retail_reports r
        WHERE r.document_ts < :'cutoff'::timestamptz
            AND NOT EXISTS (
                SELECT 1
                FROM retail_reports_list l
                    JOIN k_co k ON k.guid = l.cashorder_guid
                WHERE l.retail_report_guid = r.guid)
            -- КО из WTIS ссылаются на отчёт полем cashorder.retail_report
            AND NOT EXISTS (SELECT 1 FROM cashorder c WHERE c.retail_report = r.guid);
        """
        XCTAssertEqual(HatchPG.format(script, dialect: "postgresql"), """
        CREATE TEMP TABLE k_co AS
          SELECT c.guid
          FROM cashorder c
          WHERE FALSE
            OR c.document_ts >= :'cutoff'::timestamp
            OR c.change_ts >= :'cutoff'::timestamp
            OR EXISTS (
              SELECT FROM k_ord k
              WHERE k.guid = c.settlement_object
            );

        ANALYZE k_co;

        CREATE TEMP TABLE d_rr AS
          SELECT r.guid
          FROM retail_reports r
          WHERE TRUE
            AND r.document_ts < :'cutoff'::timestamptz
            AND NOT EXISTS (
              SELECT FROM retail_reports_list l
              JOIN k_co k ON k.guid = l.cashorder_guid
              WHERE l.retail_report_guid = r.guid
            )
            -- КО из WTIS ссылаются на отчёт полем cashorder.retail_report
            AND NOT EXISTS (
              SELECT FROM cashorder c
              WHERE c.retail_report = r.guid
            );
        """)
        let once = try XCTUnwrap(HatchPG.format(script, dialect: "postgresql"))
        XCTAssertEqual(HatchPG.format(once, dialect: "postgresql"), once, "второй раз — то же самое")
    }

    func testCreateAsQueryIsOneLevelDeeper() {
        XCTAssertEqual(HatchPG.format("""
        CREATE TEMP TABLE d_shift AS
        SELECT guid
        FROM closing_cash_shift
        WHERE document_ts < :'cutoff'::timestamptz AND change_ts < :'cutoff'::timestamptz;
        """, dialect: "postgresql"), """
        CREATE TEMP TABLE d_shift AS
          SELECT guid
          FROM closing_cash_shift
          WHERE TRUE
            AND document_ts < :'cutoff'::timestamptz
            AND change_ts < :'cutoff'::timestamptz;
        """)
        XCTAssertEqual(HatchPG.format("explain select a from t"), "EXPLAIN\nSELECT a\nFROM t", "EXPLAIN — запрос на месте")
    }

    func testOneUnformattableQueryKeepsTheRest() throws {
        // в запросе с комментарием внутри заголовка CREATE формат не уверен — он как написан, соседний форматируется
        let out = try XCTUnwrap(HatchPG.format("create /* x */ table t as select 1;\nselect a, b from t where a = 1 and b = 2;"))
        XCTAssertTrue(out.hasPrefix("CREATE /* x */ TABLE t AS SELECT 1;"), "как написан, регистр — по настройке: \(out)")
        XCTAssertTrue(out.contains("WHERE TRUE\n  AND a = 1\n  AND b = 2;"), out)
    }

    func testPsqlBlockKeepsItsLines() throws {
        let script = """
        \\set ON_ERROR_STOP on
        \\if :{?retention_days}
        \\else
        \\set retention_days 90
        \\endif

        select id from orders where created_at < now() - interval '90 days' and status = 'done';
        select 1;
        """
        let out = try XCTUnwrap(HatchPG.format(script))
        XCTAssertTrue(out.hasPrefix("\\set ON_ERROR_STOP on\n\\if :{?retention_days}\n\\else\n\\set retention_days 90\n\\endif\n\nSELECT"),
                      "команды psql строка за строкой, пустая строка — где была: \(out)")
        XCTAssertTrue(out.contains(";\n\nSELECT 1;"), "между запросами — пустая строка, как всегда: \(out)")
    }

}
