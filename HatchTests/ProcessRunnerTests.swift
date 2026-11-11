import XCTest
@testable import Hatch

final class ProcessRunnerTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        ShellTestIsolation.apply()
    }

    private func tmpURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("proc-\(UUID().uuidString).json")
    }

    private func makeEnvironment(environment: [String: String] = ProcessInfo.processInfo.environment)
        -> (SessionStore, SettingsStore, ProcessRunner) {
        let store = SessionStore(history: HistoryStore(fileURL: tmpURL()))
        let settings = SettingsStore(defaults: UserDefaults(suiteName: "ProcTests.\(UUID().uuidString)")!)
        let runner = ProcessRunner(sessionStore: store, settings: settings, environment: environment)
        return (store, settings, runner)
    }

    // MARK: - Алиасы из ~/.zshrc

    /// Окружение с отдельным ZDOTDIR, где .zshrc задаёт алиас — не зависим от конфига пользователя.
    private func environmentWithAlias() throws -> [String: String] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("zdot-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "alias hello='echo alias-works'\n".write(to: dir.appendingPathComponent(".zshrc"), atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        var env = ProcessInfo.processInfo.environment
        env["ZDOTDIR"] = dir.path
        env["SHELL"] = "/bin/zsh"
        return env
    }

    func testAliasFromZshrcWorks() throws {
        let (store, settings, runner) = makeEnvironment(environment: try environmentWithAlias())
        settings.shellPath = "/bin/zsh"
        runner.run(command: "hello")

        let session = waitTerminal(store)
        XCTAssertEqual(session?.state, .completed)
        XCTAssertEqual(session?.output.trimmingCharacters(in: .whitespacesAndNewlines), "alias-works")
    }

    func testAliasWorksInInteractiveSession() throws {
        let (store, settings, runner) = makeEnvironment(environment: try environmentWithAlias())
        settings.shellPath = "/bin/zsh"
        runner.runInPTY("hello")

        XCTAssertEqual(waitTerminal(store)?.output, "alias-works")
    }

    /// Обёртка через eval не ломает код выхода и кавычки в команде.
    func testExitCodeAndQuotingPreserved() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: #"echo "a  b" 'c$HOME'; exit 7"#)

        let session = waitTerminal(store)
        XCTAssertEqual(session?.exitCode, 7)
        XCTAssertEqual(session?.output.trimmingCharacters(in: .whitespacesAndNewlines), "a  b c$HOME")
    }

    private func waitUntil(timeout: TimeInterval = 8,
                           _ condition: @escaping () -> Bool,
                           onFulfill: @escaping () -> Void) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if condition() { onFulfill(); return }
            if Date() > deadline { onFulfill(); return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
        }
        poll()
    }

    func testRunEchoStreamsOutput() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "echo hello-hatch")

        let exp = expectation(description: "echo completes")
        waitUntil({ store.sessions.contains { $0.state.isTerminal } }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)

        let session = store.sessions.first
        XCTAssertNotNil(session)
        XCTAssertTrue(session?.output.contains("hello-hatch") ?? false)
        XCTAssertEqual(session?.state, .completed)
    }

    func testRunAppendsMultipleLines() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "printf 'one\\ntwo\\n'")

        let exp = expectation(description: "printf completes")
        waitUntil({ store.sessions.contains { $0.state.isTerminal } }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)

        let output = store.sessions.first?.output ?? ""
        XCTAssertTrue(output.contains("one"))
        XCTAssertTrue(output.contains("two"))
    }

    func testStopKillsProcessGroup() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "sleep 30")

        let exp = expectation(description: "running started")
        waitUntil({ store.sessions.contains { $0.pgid != nil } }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)

        guard let session = store.sessions.first, let pgid = session.pgid else {
            return XCTFail("сессия не запустилась")
        }
        XCTAssertTrue(Session.isAlive(pgid: pgid))

        runner.stop(sessionID: session.id)

        let stopExp = expectation(description: "stopped")
        waitUntil({ store.sessions.contains { $0.state == .stopped } }, onFulfill: { stopExp.fulfill() })
        wait(for: [stopExp], timeout: 8)
    }

    func testPTYInteractiveOutputFlows() {
        let (store, _, runner) = makeEnvironment()
        runner.runInPTY("printf 'pty-line\\n'")

        let exp = expectation(description: "pty completes")
        waitUntil({ store.sessions.contains { $0.state.isTerminal } }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)

        let session = store.sessions.first
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.state, .completed)
        XCTAssertTrue(session?.output.contains("pty-line") ?? false)
    }

    func testRunLsLAOutputNotEmpty() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "ls -la")

        let exp = expectation(description: "ls -la completes")
        waitUntil({ store.sessions.contains { $0.state.isTerminal } }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)

        let session = store.sessions.first
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.state, .completed)
        XCTAssertFalse(session?.output.isEmpty ?? true, "ls -la должен вернуть вывод")
    }

    func testRunGrepPipeline() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grep-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("myfile_target.txt").path, contents: nil)
        FileManager.default.createFile(atPath: dir.appendingPathComponent("other.txt").path, contents: nil)

        let (store, _, runner) = makeEnvironment()
        runner.run(command: "ls \(dir.path) | grep myfile_target")

        let exp = expectation(description: "grep pipeline completes")
        waitUntil({ store.sessions.contains { $0.state.isTerminal } }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)

        let session = store.sessions.first
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.state, .completed)
        XCTAssertTrue(session?.output.contains("myfile_target.txt") ?? false, "вывод должен содержать совпавшую строку: \(session?.output ?? "nil")")
    }

    func testRunPwdIsHome() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "pwd")

        let exp = expectation(description: "pwd completes")
        waitUntil({ store.sessions.contains { $0.state.isTerminal } }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)

        let output = store.sessions.first?.output.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        XCTAssertEqual(output, home, "команда должна стартовать из домашней директории")
    }

    func testRunGrepBashInHome() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "ls -la | grep bash")

        let exp = expectation(description: "grep bash completes")
        waitUntil({ store.sessions.contains { $0.state.isTerminal } }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)

        let session = store.sessions.first
        XCTAssertNotNil(session)
        XCTAssertEqual(session?.state, .completed)
        XCTAssertFalse(session?.output.isEmpty ?? true, "в ~ есть строки с bash, вывод не должен быть пустым: \(session?.output ?? "nil")")
    }

    // MARK: - Интерактивные сессии (встроенный терминал)

    private func waitTerminal(_ store: SessionStore, timeout: TimeInterval = 8) -> Session? {
        let exp = expectation(description: "interactive done")
        waitUntil(timeout: timeout, { store.sessions.first?.state.isTerminal ?? false }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: timeout + 1)
        return store.sessions.first
    }

    /// Полноэкранная программа (alt-screen, как vim/top) после выхода не оставляет вывода — только заголовок.
    func testFullScreenAppLeavesNoOutput() {
        let (store, _, runner) = makeEnvironment()
        runner.runInPTY(#"printf '\033[?1049hTUI SCREEN'; sleep 0.2; printf '\033[?1049l'"#)

        let session = waitTerminal(store)
        XCTAssertEqual(session?.state, .completed)
        XCTAssertEqual(session?.output, "", "экран TUI не попадает в историю: \(session?.output ?? "nil")")
    }

    /// Обычный текст интерактивной сессии сохраняется чистым, без escape-последовательностей.
    func testInteractivePlainOutputIsRendered() {
        let (store, _, runner) = makeEnvironment()
        runner.runInPTY(#"printf '\033[31mred\033[0m line\n'"#)

        let session = waitTerminal(store)
        XCTAssertEqual(session?.output, "red line")
    }

    /// Настоящий управляющий терминал: без него не работают less/ssh (/dev/tty), Ctrl-C и resize.
    func testInteractiveHasControllingTTY() {
        let (store, _, runner) = makeEnvironment()
        runner.runInPTY("exec 3</dev/tty && echo ctty-ok")

        let session = waitTerminal(store)
        XCTAssertTrue(session?.output.contains("ctty-ok") ?? false, session?.output ?? "nil")
    }

    func testInteractiveReceivesKeyboardInput() {
        let (store, _, runner) = makeEnvironment()
        runner.runInPTY("read x; echo got-$x")

        guard let id = store.sessions.first?.id, let terminal = runner.terminal(for: id) else {
            return XCTFail("нет терминала у интерактивной сессии")
        }
        terminal.send("hi\r")

        let session = waitTerminal(store)
        XCTAssertTrue(session?.output.contains("got-hi") ?? false, session?.output ?? "nil")
        XCTAssertNil(runner.terminal(for: id), "после выхода терминал освобождается")
    }

    func testInteractiveExitCode() {
        let (store, _, runner) = makeEnvironment()
        runner.runInPTY("exit 3")

        let session = waitTerminal(store)
        XCTAssertEqual(session?.state, .stopped)
        XCTAssertEqual(session?.exitCode, 3)
    }

    func testStopKillsInteractiveSession() {
        let (store, _, runner) = makeEnvironment()
        runner.runInPTY("sleep 30")
        guard let session = store.sessions.first, let pgid = session.pgid else {
            return XCTFail("сессия не запустилась")
        }
        XCTAssertEqual(session.state, .interactive)

        runner.stop(sessionID: session.id)

        XCTAssertEqual(waitTerminal(store)?.state, .stopped)
        XCTAssertFalse(Session.isAlive(pgid: pgid))
    }

    /// Длинная строка, перенесённая терминалом по ширине, сохраняется одной строкой.
    func testInteractiveWrappedLineIsJoined() {
        let (store, _, runner) = makeEnvironment()
        let long = String(repeating: "x", count: 300)
        runner.runInPTY("echo \(long)")

        XCTAssertEqual(waitTerminal(store)?.output, long)
    }

    func testInteractiveRunsInCurrentDirectory() throws {
        let dir = try makeTempDir()
        let (store, settings, runner) = makeEnvironment()
        settings.currentDirectory = dir
        runner.runInPTY("pwd")

        let output = waitTerminal(store)?.output ?? ""
        XCTAssertEqual(resolved(output), resolved(dir))
    }

    // MARK: - Ctrl+C (SIGINT)

    private func waitStarted(_ store: SessionStore) -> Session? {
        let exp = expectation(description: "started")
        waitUntil({ store.sessions.first?.pgid != nil }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)
        return store.sessions.first
    }

    func testInterruptStopsEndlessLoop() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "while true; do echo 123321; sleep 0.2; done")
        guard let session = waitStarted(store), let pgid = session.pgid else {
            return XCTFail("сессия не запустилась")
        }

        runner.interrupt(sessionID: session.id)

        XCTAssertEqual(waitTerminal(store)?.state, .stopped)
        XCTAssertFalse(Session.isAlive(pgid: pgid))
    }

    /// Именно SIGINT, как Ctrl+C в терминале: программа может его перехватить (а не SIGTERM, как у крестика).
    func testInterruptSendsSIGINT() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "trap 'echo caught-int; exit 0' INT; while true; do sleep 0.1; done")
        guard let session = waitStarted(store) else { return XCTFail("сессия не запустилась") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3)) // trap успевает встать

        runner.interrupt(sessionID: session.id)

        let finished = waitTerminal(store)
        XCTAssertTrue(finished?.output.contains("caught-int") ?? false, finished?.output ?? "nil")
    }

    func testInterruptStopsInteractiveSession() {
        let (store, _, runner) = makeEnvironment()
        runner.runInPTY("sleep 30")
        guard let session = store.sessions.first else { return XCTFail("сессия не запустилась") }
        // ^C до того, как шелл дочитал профиль, может потеряться — как и в обычном терминале
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        runner.interrupt(sessionID: session.id)

        XCTAssertEqual(waitTerminal(store)?.state, .stopped)
    }

    // MARK: - Все команды в терминале (цвет как в zsh)

    /// Обычная команда видит терминал: утилиты включают цвет, как в zsh.
    func testRegularCommandRunsInTerminal() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "[ -t 1 ] && echo tty-yes")
        XCTAssertEqual(waitTerminal(store)?.output, "tty-yes")
    }

    /// Цвета из вывода сохраняются: `ls -G` красит директории.
    func testColoredOutputIsKept() throws {
        let dir = try makeTempDir()
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "ls -G '\(dir)'")

        let session = waitTerminal(store)
        XCTAssertEqual(session?.output, "sub")
        XCTAssertTrue(session?.outputANSI?.contains("\u{1B}[") ?? false, "цвет директории: \(session?.outputANSI ?? "nil")")
        XCTAssertEqual(ANSIText.strip(session?.outputANSI ?? ""), "sub")
    }

    /// Пейджер не вешает обычную команду (git log и т.п. выводятся целиком).
    func testPagerDisabledForRegularCommands() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "echo \"$PAGER|$GIT_PAGER\"")
        XCTAssertEqual(waitTerminal(store)?.output, "cat|cat")
    }

    /// Пока команда работает, превью вывода обновляется в блоке.
    func testOutputPreviewUpdatesWhileRunning() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "echo first-line; sleep 30")

        let exp = expectation(description: "preview")
        waitUntil({ store.sessions.first?.output.contains("first-line") ?? false }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)
        XCTAssertEqual(store.sessions.first?.state, .running)
        store.sessions.first.map { runner.stop(sessionID: $0.id) }
    }

    /// Превью работающей команды: начало и свежий конец вывода, середина — числом строк.
    func testRunningPreviewKeepsHeadAndTail() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "for i in $(seq 1 100); do echo line-$i; done; sleep 30")

        let exp = expectation(description: "preview with tail")
        waitUntil({ store.sessions.first?.output.contains("line-100") ?? false }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)

        let session = store.sessions.first
        XCTAssertTrue(session?.output.hasPrefix("line-1\n") ?? false)
        XCTAssertNotNil(session?.outputGap)
        let shown = session?.output.split(separator: "\n").count ?? 0
        XCTAssertEqual(shown + (session?.outputGap?.count ?? 0), 100, "показанное + скрытое = весь вывод")
        session.map { runner.stop(sessionID: $0.id) }

        let done = expectation(description: "stopped")
        waitUntil({ store.sessions.first?.state.isTerminal ?? false }, onFulfill: { done.fulfill() })
        wait(for: [done], timeout: 8)
        XCTAssertNil(store.sessions.first?.outputGap, "после выхода — полный вывод без пропуска")
        XCTAssertEqual(store.sessions.first?.output.split(separator: "\n").count, 100)
    }

    // MARK: - Конвейер по сохранённому выводу

    private func waitOutput(_ store: SessionStore, _ expected: String) {
        let exp = expectation(description: "output \(expected)")
        waitUntil({ store.sessions.first?.output == expected }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)
    }

    /// Шаг конвейера обрабатывает сохранённый вывод — команда не перезапускается.
    func testPipeStageFiltersWithoutRerun() throws {
        let dir = try makeTempDir()
        let counter = dir + "/runs"
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "echo run >> '\(counter)'; printf 'alpha\\nbeta\\nbravo\\n'")
        guard let session = waitTerminal(store) else { return XCTFail("команда не завершилась") }

        runner.addPipeStage(sessionID: session.id, command: "grep b")
        waitOutput(store, "beta\nbravo")

        XCTAssertEqual(store.sessions.first?.pipeline, ["grep b"])
        XCTAssertEqual(store.sessions.first?.rawOutput, "alpha\nbeta\nbravo")
        XCTAssertEqual(try String(contentsOfFile: counter, encoding: .utf8), "run\n", "команда выполнилась один раз")
    }

    func testEditAndRemovePipeStages() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "printf 'c\\na\\nb\\n'")
        guard let session = waitTerminal(store) else { return XCTFail("команда не завершилась") }

        runner.addPipeStage(sessionID: session.id, command: "sort")
        waitOutput(store, "a\nb\nc")
        runner.addPipeStage(sessionID: session.id, command: "head -1")
        waitOutput(store, "a")
        runner.updatePipeStage(sessionID: session.id, index: 1, command: "tail -1")
        waitOutput(store, "c")
        runner.removePipeStage(sessionID: session.id, index: 0)
        waitOutput(store, "b")
        runner.removePipeStage(sessionID: session.id, index: 0)
        waitOutput(store, "c\na\nb")

        XCTAssertEqual(store.sessions.first?.pipeline, [])
        XCTAssertNotNil(store.sessions.first?.outputANSI, "без шагов — снова исходный вывод с цветом")
    }

    /// Повтор команды прогоняет новый вывод через тот же конвейер.
    func testRerunReappliesPipeline() throws {
        let dir = try makeTempDir()
        let counter = dir + "/n"
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "echo x >> '\(counter)'; printf 'keep-%s\\ndrop\\n' $(wc -l < '\(counter)' | tr -d ' ')")
        guard let session = waitTerminal(store) else { return XCTFail("команда не завершилась") }
        runner.addPipeStage(sessionID: session.id, command: "grep keep")
        waitOutput(store, "keep-1")

        runner.rerun(sessionID: session.id)
        waitOutput(store, "keep-2")
    }

    // MARK: - Перезапуск в том же блоке

    /// Повтор завершённой команды идёт в той же сессии: новый блок не появляется.
    func testRerunFinishedReusesSession() throws {
        let dir = try makeTempDir()
        let counter = dir + "/count"
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "echo x >> '\(counter)'; wc -l < '\(counter)'")
        guard let first = waitTerminal(store) else { return XCTFail("сессия не завершилась") }

        runner.rerun(sessionID: first.id)

        let exp = expectation(description: "rerun done")
        waitUntil({ (store.sessions.first?.output.contains("2") ?? false) && (store.sessions.first?.state.isTerminal ?? false) },
                  onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)

        XCTAssertEqual(store.sessions.count, 1)
        let session = store.sessions.first
        XCTAssertEqual(session?.id, first.id)
        XCTAssertEqual(session?.state, .completed)
        XCTAssertEqual(session?.output.trimmingCharacters(in: .whitespacesAndNewlines), "2", "вывод прошлого запуска заменён")
    }

    /// Повтор работающей команды: старый процесс убит, новый работает в том же блоке,
    /// и запоздалое завершение старого не портит состояние нового.
    func testRerunActiveRestartsInPlace() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "sleep 30")
        guard let first = waitStarted(store), let oldPgid = first.pgid else {
            return XCTFail("сессия не запустилась")
        }

        runner.rerun(sessionID: first.id)

        let exp = expectation(description: "restarted")
        waitUntil({ store.sessions.first.map { $0.pgid != nil && $0.pgid != oldPgid } ?? false },
                  onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5)) // события старого процесса успевают прийти

        // старый процесс убит; под нагрузкой система убирает его не мгновенно
        let dead = expectation(description: "old process gone")
        waitUntil(timeout: 3, { !Session.isAlive(pgid: oldPgid) }, onFulfill: { dead.fulfill() })
        wait(for: [dead], timeout: 4)
        XCTAssertFalse(Session.isAlive(pgid: oldPgid))
        XCTAssertEqual(store.sessions.count, 1)
        let session = store.sessions.first
        XCTAssertEqual(session?.id, first.id)
        XCTAssertEqual(session?.state, .running)
        XCTAssertNil(session?.exitCode)
        runner.stop(sessionID: first.id)
    }

    func testRerunInteractiveRestartsInPlace() {
        let (store, _, runner) = makeEnvironment()
        runner.runInPTY("sleep 30")
        guard let first = store.sessions.first, let oldPgid = first.pgid else {
            return XCTFail("сессия не запустилась")
        }

        runner.rerun(sessionID: first.id)

        let exp = expectation(description: "restarted")
        waitUntil({ store.sessions.first.map { $0.pgid != nil && $0.pgid != oldPgid } ?? false },
                  onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        XCTAssertEqual(store.sessions.count, 1)
        XCTAssertEqual(store.sessions.first?.state, .interactive)
        XCTAssertNotNil(runner.terminal(for: first.id))
        runner.stop(sessionID: first.id)
    }

    // MARK: - Текущая директория (cd)

    private func makeTempDir() throws -> String {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cwd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return dir.path
    }

    private func resolved(_ path: String?) -> String? {
        path.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }
    }

    /// Запускает команду и ждёт, пока она завершится и директория применится.
    private func runAndWait(_ runner: ProcessRunner, _ store: SessionStore, _ command: String,
                            directory: String? = nil) -> Session? {
        runner.run(command: command, directory: directory)
        let id = store.sessions.first?.id
        let exp = expectation(description: command)
        waitUntil({ store.sessions.first { $0.id == id }?.state.isTerminal ?? false }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)
        // директория применяется на main сразу после завершения
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        return store.sessions.first { $0.id == id }
    }

    func testCdChangesDirectoryForNextCommands() throws {
        let dir = try makeTempDir()
        let (store, settings, runner) = makeEnvironment()

        _ = runAndWait(runner, store, "cd '\(dir)'")
        XCTAssertEqual(resolved(settings.currentDirectory), resolved(dir))

        let pwd = runAndWait(runner, store, "pwd")
        XCTAssertEqual(resolved(pwd?.output.trimmingCharacters(in: .whitespacesAndNewlines)), resolved(dir))
        XCTAssertEqual(resolved(pwd?.directory), resolved(dir), "сессия помнит, где запускалась")
    }

    func testCdRelativeAndInChain() throws {
        let dir = try makeTempDir()
        let (store, settings, runner) = makeEnvironment()
        settings.currentDirectory = dir

        let chained = runAndWait(runner, store, "cd sub && pwd")
        XCTAssertEqual(chained?.state, .completed)
        XCTAssertEqual(resolved(settings.currentDirectory), resolved(dir + "/sub"))

        _ = runAndWait(runner, store, "cd ..")
        XCTAssertEqual(resolved(settings.currentDirectory), resolved(dir))
    }

    func testFailedCdKeepsDirectory() throws {
        let dir = try makeTempDir()
        let (store, settings, runner) = makeEnvironment()
        settings.currentDirectory = dir

        let session = runAndWait(runner, store, "cd ./no-such-dir")
        XCTAssertEqual(session?.state, .stopped)
        XCTAssertFalse(session?.output.isEmpty ?? true, "ошибка cd видна в выводе")
        XCTAssertEqual(settings.currentDirectory, dir)
    }

    /// Повтор запускает команду там, где она запускалась изначально, и не трогает текущую директорию.
    func testExplicitDirectoryDoesNotChangeCurrent() throws {
        let dir = try makeTempDir()
        let (store, settings, runner) = makeEnvironment()
        let home = settings.currentDirectory

        let session = runAndWait(runner, store, "pwd", directory: dir)
        XCTAssertEqual(resolved(session?.output.trimmingCharacters(in: .whitespacesAndNewlines)), resolved(dir))
        XCTAssertEqual(settings.currentDirectory, home)
    }

    /// Долгая команда, запущенная до cd, по завершении не откатывает директорию назад.
    func testLongCommandWithoutCdDoesNotResetDirectory() throws {
        let dir = try makeTempDir()
        let (store, settings, runner) = makeEnvironment()

        runner.run(command: "sleep 0.5")
        _ = runAndWait(runner, store, "cd '\(dir)'")

        let exp = expectation(description: "sleep done")
        waitUntil({ store.sessions.allSatisfy { $0.state.isTerminal } }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 8)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(resolved(settings.currentDirectory), resolved(dir))
    }

    /// Как в приложении: один ProcessRunner на все команды. Вторая команда и stderr тоже должны дать вывод.
    func testSequentialCommandsOnSameRunnerStreamOutput() {
        let (store, _, runner) = makeEnvironment()

        runner.run(command: "echo first-cmd")
        let firstExp = expectation(description: "first completes")
        waitUntil({ store.sessions.contains { $0.state.isTerminal && $0.output.contains("first-cmd") } },
                  onFulfill: { firstExp.fulfill() })
        wait(for: [firstExp], timeout: 8)

        runner.run(command: "echo second-cmd; echo second-err >&2")
        let secondExp = expectation(description: "second completes")
        waitUntil({
            store.sessions.first.map { $0.state.isTerminal && $0.output.contains("second-err") } ?? false
        }, onFulfill: { secondExp.fulfill() })
        wait(for: [secondExp], timeout: 8)

        let output = store.sessions.first?.output ?? ""
        XCTAssertTrue(output.contains("second-cmd"), "stdout второй команды: \(output)")
        XCTAssertTrue(output.contains("second-err"), "stderr второй команды: \(output)")
    }

    /// Многобайтовые символы, разрезанные границей чанка, не должны теряться.
    func testMultibyteOutputNotLost() {
        let (store, _, runner) = makeEnvironment()
        runner.run(command: "for i in $(seq 1 3000); do printf 'привет'; done")

        let exp = expectation(description: "cyrillic completes")
        waitUntil({
            store.sessions.first.map { $0.state.isTerminal && $0.output.count >= 18000 } ?? false
        }, onFulfill: { exp.fulfill() })
        wait(for: [exp], timeout: 15)

        XCTAssertEqual(store.sessions.first?.output.count, 18000)
    }
}

extension Session {
    static func isAlive(pgid: Int32) -> Bool {
        kill(-pgid, 0) == 0
    }
}
