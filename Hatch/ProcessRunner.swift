import Foundation
import Observation
import Darwin
import UserNotifications
import AppKit

/// Запуск команд в терминале (PTY): вывод как в zsh — с цветом и tty; остановка по группе процессов.
@Observable
final class ProcessRunner {
    private let sessionStore: SessionStore
    private let settings: SettingsStore

    /// Живые терминалы сессий (пока процесс не завершился).
    private var terminals: [UUID: InteractiveTerminal] = [:]
    /// Метка последнего прогона конвейера: результат устаревшего прогона отбрасывается.
    private var pipelineTokens: [UUID: UUID] = [:]
    /// Метка текущего запуска сессии. Перезапуск идёт в той же сессии, поэтому события
    /// прошлого процесса (вывод, завершение) отбрасываются по несовпадению метки.
    private var runTokens: [UUID: UUID] = [:]

    /// Окружение для команд (в тестах подменяется, например ZDOTDIR).
    private let environment: [String: String]

    init(sessionStore: SessionStore, settings: SettingsStore,
         environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.sessionStore = sessionStore
        self.settings = settings
        self.environment = environment
    }

    /// Запускает команду в новой сессии. vim, top, ssh и т.п. — интерактивные: блок сразу
    /// раскрывается живым терминалом и сворачивается при выходе из программы.
    /// - Parameter directory: где запускать; nil — текущая директория лаунчера.
    ///   Только запуск в текущей директории может её сменить (`cd`).
    func run(command: String, directory: String? = nil) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let interactive = isInteractive(command: trimmed)
        let workingDirectory = resolveDirectory(directory)
        let session = Session(command: trimmed, state: interactive ? .interactive : .running,
                              directory: workingDirectory)
        sessionStore.add(session)
        start(sessionID: session.id, command: trimmed, directory: workingDirectory,
              followsCurrent: directory == nil, interactive: interactive)
    }

    /// Запуск как интерактивной программы, независимо от имени команды.
    func runInPTY(_ command: String, directory: String? = nil) {
        let workingDirectory = resolveDirectory(directory)
        let session = Session(command: command, state: .interactive, directory: workingDirectory)
        sessionStore.add(session)
        start(sessionID: session.id, command: command, directory: workingDirectory,
              followsCurrent: false, interactive: true)
    }

    /// Терминал сессии, пока её процесс жив.
    func terminal(for sessionID: UUID) -> InteractiveTerminal? {
        terminals[sessionID]
    }

    /// Повтор команды в том же блоке: работающий процесс сначала останавливается,
    /// затем команда запускается заново в своей исходной директории.
    func rerun(sessionID: UUID) {
        guard let session = sessionStore.sessions.first(where: { $0.id == sessionID }) else { return }
        // события старого процесса больше не относятся к сессии
        runTokens[sessionID] = UUID()

        guard session.state.isActive, let pgid = session.pgid else {
            restart(session)
            return
        }
        stop(sessionID: sessionID)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let deadline = Date().addingTimeInterval(3)
            while Session.isAlive(pgid: pgid) && Date() < deadline {
                usleep(20_000)
            }
            DispatchQueue.main.async { self?.restart(session) }
        }
    }

    /// Ctrl+C: ^C через tty — SIGINT получит текущая программа, она может его перехватить.
    func interrupt(sessionID: UUID) {
        if let terminal = terminals[sessionID] {
            terminal.send("\u{3}")
            return
        }
        guard let pgid = sessionStore.sessions.first(where: { $0.id == sessionID })?.pgid else { return }
        kill(-pgid, SIGINT)
    }

    /// Останавливает сессию, убивая всю группу процессов.
    func stop(sessionID: UUID) {
        guard let pgid = sessionStore.sessions.first(where: { $0.id == sessionID })?.pgid else { return }
        kill(-pgid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
            if Session.isAlive(pgid: pgid) {
                kill(-pgid, SIGKILL)
            }
        }
    }

    // MARK: - Конвейер по сохранённому выводу

    /// Добавляет шаг конвейера к завершённой команде: команда не перезапускается,
    /// шаги обрабатывают её сохранённый вывод.
    func addPipeStage(sessionID: UUID, command: String) {
        changePipeline(sessionID) { $0.append(command) }
    }

    func updatePipeStage(sessionID: UUID, index: Int, command: String) {
        changePipeline(sessionID) { stages in
            guard stages.indices.contains(index) else { return }
            stages[index] = command
        }
    }

    func removePipeStage(sessionID: UUID, index: Int) {
        changePipeline(sessionID) { stages in
            guard stages.indices.contains(index) else { return }
            stages.remove(at: index)
        }
    }

    private func changePipeline(_ sessionID: UUID, _ change: (inout [String]) -> Void) {
        // у работающей команды вывод ещё меняется — обрабатывать нечего
        guard let session = sessionStore.sessions.first(where: { $0.id == sessionID }),
              session.state.isTerminal else { return }
        var stages = session.pipeline
        change(&stages)
        stages = stages.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        sessionStore.update(id: sessionID) { s in
            if s.rawOutput == nil {
                s.rawOutput = s.output
                s.rawOutputANSI = s.outputANSI
            }
            s.pipeStages = stages.isEmpty ? nil : stages
            if stages.isEmpty { // шагов не осталось — снова исходный вывод
                s.output = s.rawOutput ?? s.output
                s.outputANSI = s.rawOutputANSI
                s.rawOutput = nil
                s.rawOutputANSI = nil
            }
        }
        if stages.isEmpty {
            pipelineTokens[sessionID] = nil
        } else {
            applyPipeline(sessionID)
        }
    }

    /// Прогоняет сохранённый вывод через шаги конвейера и показывает результат.
    private func applyPipeline(_ sessionID: UUID) {
        guard let session = sessionStore.sessions.first(where: { $0.id == sessionID }),
              let raw = session.rawOutput, !session.pipeline.isEmpty else { return }
        let token = UUID()
        pipelineTokens[sessionID] = token
        let directory = resolveDirectory(session.directory)
        let shell = settings.shellPath
        let environment = environment
        Task { @MainActor [weak self] in
            let result = await OutputPipeline.run(stages: session.pipeline, input: raw, directory: directory,
                                                  shell: shell, environment: environment)
            guard let self, self.pipelineTokens[sessionID] == token else { return }
            self.sessionStore.update(id: sessionID) { s in
                s.output = result.output
                s.outputANSI = nil
                s.outputGap = nil
            }
        }
    }

    // MARK: - Запуск

    private func restart(_ session: Session) {
        let directory = resolveDirectory(session.directory)
        // режим прошлого запуска сохраняется; у завершённой сессии его подскажет имя команды
        let interactive = session.state == .interactive || isInteractive(command: session.command)
        terminals[session.id] = nil
        sessionStore.update(id: session.id) { s in
            s.state = interactive ? .interactive : .running
            s.output = ""
            s.outputANSI = nil
            s.outputGap = nil
            s.rawOutput = nil
            s.rawOutputANSI = nil
            s.exitCode = nil
            s.finishedAt = nil
            s.pid = nil
            s.pgid = nil
            s.directory = directory
        }
        start(sessionID: session.id, command: session.command, directory: directory,
              followsCurrent: false, interactive: interactive)
    }

    /// Запускает процесс команды для уже созданной сессии.
    private func start(sessionID: UUID, command: String, directory workingDirectory: String,
                       followsCurrent: Bool, interactive: Bool) {
        let token = UUID()
        runTokens[sessionID] = token
        let startedAt = Date()
        let pwdFile = followsCurrent
            ? FileManager.default.temporaryDirectory.appendingPathComponent("hatch-pwd-\(sessionID.uuidString)")
            : nil

        let terminal = InteractiveTerminal()
        terminal.onOutput = { [weak self] preview in
            guard let self, self.runTokens[sessionID] == token else { return }
            self.sessionStore.update(id: sessionID) { s in
                s.output = preview.plain
                s.outputANSI = preview.ansi
                s.outputGap = preview.gap
            }
        }
        terminal.onExit = { [weak self] code, screen in
            guard let self, self.runTokens[sessionID] == token else { return } // сессию уже перезапустили
            self.terminals[sessionID] = nil
            // Директорию меняет только команда, которая сама сделала cd: долгая команда,
            // запущенная раньше, не откатывает текущую директорию назад.
            if let finalDirectory = pwdFile.flatMap(Self.consumeReportedDirectory),
               finalDirectory != workingDirectory, SettingsStore.isDirectory(finalDirectory) {
                self.settings.currentDirectory = finalDirectory
            }
            self.sessionStore.update(id: sessionID) { s in
                s.exitCode = code
                s.output = screen.plain
                s.outputANSI = screen.ansi
                s.outputGap = screen.gap
                if !s.pipeline.isEmpty { // повтор команды с конвейером: новый вывод — через те же шаги
                    s.rawOutput = screen.plain
                    s.rawOutputANSI = screen.ansi
                }
                if s.state.isActive {
                    s.state = code == 0 ? .completed : .stopped
                }
                s.finishedAt = s.finishedAt ?? Date()
            }
            self.applyPipeline(sessionID)
            // уведомление о завершении долгой команды, если приложение не в фокусе
            if !interactive, Date().timeIntervalSince(startedAt) >= 5 {
                NotificationService().notifyIfNotFocused(title: "Готово", body: "Команда «\(command)» завершилась")
            }
        }

        var env = commandEnvironment(directory: workingDirectory, command: command)
        if !interactive {
            // в терминале git log и т.п. ушли бы в less и ждали клавиш — выводим целиком
            env["PAGER"] = "cat"
            env["GIT_PAGER"] = "cat"
        }
        let shell = settings.shellPath
        guard terminal.start(shell: shell, script: Self.script(shell: shell, reportingDirectoryTo: pwdFile),
                             directory: workingDirectory, environment: env) else {
            sessionStore.update(id: sessionID) { s in
                s.state = .stopped
                s.exitCode = -1
                s.finishedAt = Date()
                s.output = "Ошибка запуска"
            }
            return
        }

        terminals[sessionID] = terminal
        // forkpty делает процесс лидером своей сессии и группы: pgid == pid
        sessionStore.update(id: sessionID) { s in
            s.pid = terminal.pid
            s.pgid = terminal.pid
        }
        if !interactive {
            scheduleTimeoutIfNeeded(pgid: terminal.pid)
        }
    }

    /// Тайм-аут фоновой команды (0 = нет).
    private func scheduleTimeoutIfNeeded(pgid: pid_t) {
        let timeout = settings.timeoutSeconds
        guard timeout > 0 else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
            guard Session.isAlive(pgid: pgid) else { return }
            kill(-pgid, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) {
                if Session.isAlive(pgid: pgid) {
                    kill(-pgid, SIGKILL)
                }
            }
        }
    }

    // MARK: - Окружение и скрипт

    /// Существующая директория для запуска: явная, иначе текущая, иначе домашняя.
    private func resolveDirectory(_ directory: String?) -> String {
        if let directory, SettingsStore.isDirectory(directory) { return directory }
        if SettingsStore.isDirectory(settings.currentDirectory) { return settings.currentDirectory }
        settings.currentDirectory = SettingsStore.homeDirectory
        return settings.currentDirectory
    }

    /// PWD сохраняет логический путь (`/tmp`, а не `/private/tmp`) для `pwd`;
    /// команда передаётся переменной, а не в тексте скрипта — без проблем с кавычками.
    private func commandEnvironment(directory: String, command: String) -> [String: String] {
        var env = environment
        env["PWD"] = directory
        env[Self.commandVariable] = command
        // команда идёт в терминале: oh-my-zsh раз в N дней спросит «обновиться? [Y/n]» и зависнет
        env["DISABLE_AUTO_UPDATE"] = "true"
        return env
    }

    static let commandVariable = "HATCH_COMMAND"

    /// Скрипт запуска команды:
    /// 1. rc-файл пользователя (`~/.zshrc`): алиасы и функции, как в его терминале;
    /// 2. сама команда через `eval` — алиасы раскрываются при разборе, поэтому команда
    ///    разбирается уже после загрузки rc;
    /// 3. если нужно — итоговая директория в файл (так `cd` меняет текущую директорию лаунчера).
    ///    После `exit`/`exec` или убийства файла не будет — директория не меняется.
    static func script(shell: String, reportingDirectoryTo file: URL? = nil) -> String {
        var lines = [
            rcPrelude(shell: shell),
            "__hatch_cmd=$\(commandVariable); unset \(commandVariable)",
            #"eval "$__hatch_cmd""#,
        ]
        if let file {
            let quoted = "'" + file.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
            lines += [
                "__hatch_status=$?",
                "builtin pwd > \(quoted) 2>/dev/null",
                "exit $__hatch_status",
            ]
        }
        return lines.joined(separator: "\n")
    }

    /// Неинтерактивный шелл сам rc-файл не читает. Ошибки rc не засоряют вывод команды.
    private static func rcPrelude(shell: String) -> String {
        let name = (shell as NSString).lastPathComponent
        if name.contains("zsh") {
            return #"[[ -r "${ZDOTDIR:-$HOME}/.zshrc" ]] && source "${ZDOTDIR:-$HOME}/.zshrc" 2>/dev/null"#
        }
        if name.contains("bash") {
            return #"[ -r "$HOME/.bashrc" ] && . "$HOME/.bashrc" 2>/dev/null; shopt -s expand_aliases"#
        }
        return ""
    }

    private static func consumeReportedDirectory(_ file: URL) -> String? {
        defer { try? FileManager.default.removeItem(at: file) }
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        let path = text.trimmingCharacters(in: .newlines)
        return path.isEmpty ? nil : path
    }

    /// Эвристика: команда считается интерактивной по имени бинарника.
    private func isInteractive(command: String) -> Bool {
        let firstToken = command.trimmingCharacters(in: .whitespaces)
            .split(separator: " ").first.map(String.init) ?? ""
        let base = (firstToken as NSString).lastPathComponent
        let interactive: Set<String> = [
            "vim", "nvim", "vi", "top", "htop", "ssh", "less", "more",
            "man", "watch", "bc", "ipython", "irb", "psql", "mysql", "node", "python"
        ]
        return interactive.contains(base)
    }
}

private extension Session {
    static func isAlive(pgid: Int32) -> Bool {
        kill(-pgid, 0) == 0
    }
}
