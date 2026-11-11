import Foundation

/// Головная самопроверка фич: запуск с `--selftest`.
/// Каждая фича добавляет сценарий; итог — exit 0 при PASS, exit 1 при FAIL.
final class SelfTest {
    private var failures = 0
    private var checks = 0

    func run() -> Int32 {
        check("echo: скрытый запуск и вывод", testEcho)
        check("kill: убийство дерева процессов", testKill)
        check("история: персистентность", testHistoryPersistence)
        check("автокомплет: команды от живого zsh", testAutocompleteCommands)
        check("автокомплет: файлы", testAutocompleteFiles)
        check("кап истории: N + активные", testHistoryCap)
        check("удаление активной: kill + удаление", testDeleteActive)
        check("очистка всей истории", testClearAll)
        check("pin: закрепление", testPin)
        check("пайплайн ls -la | grep bash из ~", testGrepBashInHome)

        let ok = failures == 0
        print("SELFTEST \(checks) сценариев: \(ok ? "PASS" : "FAIL (\(failures))")")
        return ok ? 0 : 1
    }

    // MARK: - Helpers

    private func check(_ name: String, _ body: () -> Bool) {
        checks += 1
        let pass = body()
        print((pass ? "[PASS] " : "[FAIL] ") + name)
        if !pass { failures += 1 }
    }

    private func waitUntil(timeout: TimeInterval = 10, _ cond: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if cond() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return cond()
    }

    private func makeEnv() -> (SessionStore, SettingsStore, ProcessRunner) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("selftest-\(UUID().uuidString).json")
        let store = SessionStore(history: HistoryStore(fileURL: url))
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "SelfTest.\(UUID().uuidString)")!)
        let runner = ProcessRunner(sessionStore: store, settings: settings)
        return (store, settings, runner)
    }

    private func isAlive(pgid: Int32) -> Bool {
        kill(-pgid, 0) == 0
    }

    // MARK: - Scenarios

    private func testEcho() -> Bool {
        let (store, _, runner) = makeEnv()
        runner.run(command: "printf 'selftest-ok\\n'")
        guard waitUntil({ store.sessions.contains { $0.state.isTerminal } }) else { return false }
        let s = store.sessions.first
        return s?.state == .completed && (s?.output.contains("selftest-ok") ?? false)
    }

    private func testKill() -> Bool {
        let (store, _, runner) = makeEnv()
        runner.run(command: "sleep 30")
        guard waitUntil({ store.sessions.contains { $0.pgid != nil } }) else { return false }
        guard let session = store.sessions.first, let pgid = session.pgid else { return false }

        if !isAlive(pgid: pgid) { return false }

        runner.stop(sessionID: session.id)
        guard waitUntil({ store.sessions.contains { $0.state == .stopped } }) else { return false }

        // ждём, пока процесс реально уйдёт
        return waitUntil(timeout: 3, { !self.isAlive(pgid: pgid) })
    }

    private func testHistoryPersistence() -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("selftest-hist-\(UUID().uuidString).json")
        let store = SessionStore(history: HistoryStore(fileURL: url))
        var s = Session(command: "echo persisted")
        s.state = .completed
        s.finishedAt = Date()
        store.add(s)

        let reloaded = SessionStore(history: HistoryStore(fileURL: url))
        return reloaded.sessions.count == 1 && reloaded.sessions.first?.command == "echo persisted"
    }

    private func testAutocompleteCommands() -> Bool {
        let engine = ShellCompletionEngine()
        return engine.commandCompletions(prefix: "z").contains("zsh")
    }

    private func testAutocompleteFiles() -> Bool {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("selftest-files-\(UUID().uuidString)", isDirectory: true)
        guard (try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)) != nil else { return false }
        FileManager.default.createFile(atPath: dir.appendingPathComponent("zeta.txt").path, contents: nil)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("zebra.log").path, contents: nil)

        let engine = ShellCompletionEngine()
        let buffer = "cat \(dir.appendingPathComponent("ze").path)"
        let comps = engine.completions(for: buffer)
        return comps.contains { $0.hasSuffix("zeta.txt") } && comps.contains { $0.hasSuffix("zebra.log") }
    }

    private func testHistoryCap() -> Bool {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("selftest-cap-\(UUID().uuidString).json")
        let store = HistoryStore(fileURL: url, defaultLimit: 2)
        var sessions: [Session] = []
        for i in 0..<5 {
            var s = Session(command: "c\(i)")
            s.state = .completed
            s.finishedAt = Date()
            sessions.append(s)
        }
        sessions.append(Session(command: "active"))
        let capped = store.applyCap(to: sessions, limit: 2)
        let activeCount = capped.filter { $0.state.isActive }.count
        return capped.count == 3 && activeCount == 1
    }

    private func testDeleteActive() -> Bool {
        let (store, _, runner) = makeEnv()
        runner.run(command: "sleep 30")
        guard waitUntil({ store.sessions.contains { $0.pgid != nil } }) else { return false }
        guard let session = store.sessions.first else { return false }

        if session.state.isActive {
            runner.stop(sessionID: session.id)
        }
        store.remove(id: session.id)
        // активная сессия удалена
        guard !store.sessions.contains(where: { $0.id == session.id }) else { return false }
        // и процесс убит
        guard let pgid = session.pgid else { return true }
        return waitUntil(timeout: 3, { !self.isAlive(pgid: pgid) })
    }

    private func testClearAll() -> Bool {
        let (store, _, _) = makeEnv()
        var finished = Session(command: "ls")
        finished.state = .completed
        finished.finishedAt = Date()
        store.add(finished)
        store.add(Session(command: "run"))
        store.clearAll()
        return store.sessions.isEmpty
    }

    private func testPin() -> Bool {
        let (store, _, _) = makeEnv()
        let session = Session(command: "echo")
        store.add(session)
        store.togglePin(id: session.id)
        guard store.sessions.first?.isPinned == true else { return false }
        store.togglePin(id: session.id)
        return store.sessions.first?.isPinned == false
    }

    private func testGrepBashInHome() -> Bool {
        let (store, _, runner) = makeEnv()
        runner.run(command: "ls -la | grep bash")
        guard waitUntil({ store.sessions.contains { $0.state.isTerminal } }) else { return false }
        let session = store.sessions.first
        return session?.state == .completed && !(session?.output.isEmpty ?? true)
    }
}
