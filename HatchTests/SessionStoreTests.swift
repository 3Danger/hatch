import XCTest
@testable import Hatch

final class SessionStoreTests: XCTestCase {

    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("session-\(UUID().uuidString).json")
    }

    private func makeStore() -> SessionStore {
        SessionStore(history: HistoryStore(fileURL: tmpURL()))
    }

    /// После перезапуска процессов прошлого запуска уже нет: активные сессии — interrupted,
    /// а pgid сбрасывается, чтобы stop не убил чужую группу с переиспользованным номером.
    func testActiveSessionsFromPreviousLaunchBecomeInterrupted() {
        let url = tmpURL()
        let history = HistoryStore(fileURL: url)
        history.save([
            Session(command: "vim test", state: .interactive, pid: 111, pgid: 111),
            Session(command: "sleep 99", state: .running, pid: 222, pgid: 222),
            Session(command: "ls", state: .completed, finishedAt: Date(), pid: 333, pgid: 333, exitCode: 0),
        ])

        let store = SessionStore(history: HistoryStore(fileURL: url))
        let byCommand = Dictionary(uniqueKeysWithValues: store.sessions.map { ($0.command, $0) })

        for command in ["vim test", "sleep 99"] {
            let s = byCommand[command]
            XCTAssertEqual(s?.state, .interrupted, command)
            XCTAssertNil(s?.pgid, command)
            XCTAssertNil(s?.pid, command)
            XCTAssertNotNil(s?.finishedAt, command)
        }
        XCTAssertEqual(byCommand["ls"]?.state, .completed)
        XCTAssertEqual(byCommand["ls"]?.pgid, 333)
        XCTAssertTrue(HistoryStore(fileURL: url).load().allSatisfy { $0.state.isTerminal }, "исправление сохраняется на диск")
    }

    // MARK: - Запись на диск

    /// Превью работающей команды (обновляется каждые 150 мс) на диск не пишется.
    func testPreviewUpdatesAreNotWritten() {
        let history = HistoryStore(fileURL: tmpURL())
        let store = SessionStore(history: history)
        let s = Session(command: "tail -f log")
        store.add(s)
        let writes = history.writeCount

        for i in 0..<20 { store.update(id: s.id, persist: .never) { $0.output = "line \(i)" } }
        RunLoop.main.run(until: Date().addingTimeInterval(1.3))

        XCTAssertEqual(history.writeCount, writes)
    }

    /// Частые изменения сливаются: не чаще одной записи в секунду.
    func testUpdatesAreCoalesced() {
        let history = HistoryStore(fileURL: tmpURL())
        let store = SessionStore(history: history)
        let s = Session(command: "echo")
        store.add(s)
        let writes = history.writeCount

        for i in 0..<20 { store.update(id: s.id) { $0.output = "v\(i)" } }
        XCTAssertEqual(history.writeCount, writes, "сразу не пишем")
        RunLoop.main.run(until: Date().addingTimeInterval(1.3))
        XCTAssertEqual(history.writeCount, writes + 1)
    }

    /// Неизменённую историю не перезаписываем.
    func testUnchangedHistoryIsNotRewritten() {
        let history = HistoryStore(fileURL: tmpURL())
        let sessions = [Session(command: "ls", state: .completed, finishedAt: Date())]
        history.save(sessions)
        history.save(sessions)
        XCTAssertEqual(history.writeCount, 1)
    }

    func testAddInsertsFirst() {
        let store = makeStore()
        store.add(Session(command: "first"))
        store.add(Session(command: "second"))
        XCTAssertEqual(store.sessions.map(\.command), ["second", "first"])
    }

    func testFilter() {
        let store = makeStore()
        store.add(Session(command: "git status"))
        store.add(Session(command: "top"))
        store.filterText = "git"
        XCTAssertEqual(store.filteredSessions.map(\.command), ["git status"])
    }

    /// clear и ⌃L: уходят завершённые незакреплённые; «Отменить» возвращает их на места.
    func testClearFinishedKeepsRunningAndPinnedAndRestores() {
        let store = makeStore()
        store.add(Session(command: "old", state: .completed, createdAt: Date(timeIntervalSinceNow: -30)))
        var pinned = Session(command: "pinned", state: .completed, createdAt: Date(timeIntervalSinceNow: -20))
        pinned.isPinned = true
        store.add(pinned)
        store.add(Session(command: "failed", state: .stopped, createdAt: Date(timeIntervalSinceNow: -10)))
        store.add(Session(command: "worker", state: .running, createdAt: Date()))

        let removed = store.clearFinished()
        XCTAssertEqual(Set(removed.map(\.command)), ["old", "failed"])
        XCTAssertEqual(store.sessions.map(\.command), ["worker", "pinned"])

        store.restore(removed)
        XCTAssertEqual(store.sessions.map(\.command), ["worker", "failed", "pinned", "old"])
        store.restore(removed) // повторно — без дублей
        XCTAssertEqual(store.sessions.count, 4)
        XCTAssertEqual(store.clearFinished().count, 2)
        XCTAssertEqual(store.clearFinished().count, 0)
    }

    /// Поиск (⌘F) находит и по выводу, без учёта регистра.
    func testSearchMatchesOutput() {
        let store = makeStore()
        var compose = Session(command: "docker compose up -d")
        compose.output = "unable to get image 'apache/kafka:latest'"
        store.add(compose)
        store.add(Session(command: "ls -li"))
        store.filterText = "KAFKA"
        XCTAssertEqual(store.filteredSessions.map(\.command), ["docker compose up -d"])
        store.filterText = ""
        XCTAssertEqual(store.filteredSessions.count, 2)
    }

    /// Закрепление защищает от очистки, но не поднимает блок наверх.
    func testPinnedDoesNotChangeOrder() {
        let store = makeStore()
        var a = Session(command: "a", createdAt: Date(timeIntervalSinceNow: -10))
        a.isPinned = true
        store.add(a)
        store.add(Session(command: "b"))
        XCTAssertEqual(store.filteredSessions.map(\.command), ["b", "a"])
    }

    func testActiveAboveFinished() {
        let store = makeStore()
        var finished = Session(command: "finished")
        finished.state = .completed
        finished.finishedAt = Date()
        let running = Session(command: "running")
        store.add(finished)
        store.add(running)
        XCTAssertEqual(store.filteredSessions.map(\.command), ["running", "finished"])
    }

    func testUpdateStatePersists() throws {
        let url = tmpURL()
        let store = SessionStore(history: HistoryStore(fileURL: url))
        let s = Session(command: "echo")
        store.add(s)
        store.update(id: s.id) { $0.state = .completed; $0.finishedAt = Date() }
        XCTAssertEqual(store.sessions.first?.state, .completed)
        XCTAssertNotNil(store.sessions.first?.finishedAt)
        store.flush() // изменения пишутся отложенно — как при закрытии приложения

        let reloaded = SessionStore(history: HistoryStore(fileURL: url))
        XCTAssertEqual(reloaded.sessions.first?.state, .completed)
    }

    func testRemove() {
        let store = makeStore()
        let s = Session(command: "x")
        store.add(s)
        store.remove(id: s.id)
        XCTAssertTrue(store.sessions.isEmpty)
    }

    func testClearCompletedKeepsActive() {
        let store = makeStore()
        var fin = Session(command: "fin")
        fin.state = .completed
        fin.finishedAt = Date()
        store.add(fin)
        store.add(Session(command: "run"))
        store.clearCompleted()
        XCTAssertEqual(store.sessions.map(\.command), ["run"])
    }

    /// Есть завершённые — очистка трогает только их, активные остаются.
    func testClearScopeFinishedWhenAnyFinished() {
        let store = makeStore()
        store.add(Session(command: "fin", state: .completed, finishedAt: Date()))
        store.add(Session(command: "run"))
        XCTAssertEqual(store.clearScope, .finished(pinned: false))
    }

    /// Остались только активные — очистка их останавливает и удаляет.
    func testClearScopeActiveWhenOnlyActive() {
        let store = makeStore()
        store.add(Session(command: "run"))
        store.add(Session(command: "vim", state: .interactive))
        XCTAssertEqual(store.clearScope, .active(pinned: false))
    }

    func testClearScopeNothingWhenEmpty() {
        XCTAssertEqual(makeStore().clearScope, .nothing)
    }

    private func pinned(_ session: Session) -> Session {
        var s = session
        s.isPinned = true
        return s
    }

    /// Закреплённые очистка не трогает, пока есть незакреплённые — даже активные.
    func testClearSkipsPinnedWhileUnpinnedRemain() {
        let store = makeStore()
        store.add(pinned(Session(command: "keep", state: .completed, finishedAt: Date())))
        store.add(Session(command: "fin", state: .completed, finishedAt: Date()))
        store.add(Session(command: "run"))

        XCTAssertEqual(store.clearScope, .finished(pinned: false))
        XCTAssertEqual(store.sessionsToClear.map(\.command), ["fin"])

        store.remove(ids: Set(store.sessionsToClear.map(\.id)))
        XCTAssertEqual(store.clearScope, .active(pinned: false))
        XCTAssertEqual(store.sessionsToClear.map(\.command), ["run"])
    }

    /// Остались только закреплённые — тогда очищаются и они: сначала завершённые, потом активные.
    func testClearReachesPinnedWhenNothingElse() {
        let store = makeStore()
        store.add(pinned(Session(command: "pinned-run")))
        store.add(pinned(Session(command: "pinned-fin", state: .completed, finishedAt: Date())))

        XCTAssertEqual(store.clearScope, .finished(pinned: true))
        XCTAssertEqual(store.sessionsToClear.map(\.command), ["pinned-fin"])

        store.remove(ids: Set(store.sessionsToClear.map(\.id)))
        XCTAssertEqual(store.clearScope, .active(pinned: true))
    }
}
