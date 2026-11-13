import Foundation

/// Состояние сессии.
enum SessionState: String, Codable, Hashable, CaseIterable {
    case running
    case interactive
    case completed
    case stopped
    case interrupted

    /// Терминальные состояния: процесс завершён и не может продолжаться.
    var isTerminal: Bool {
        switch self {
        case .completed, .stopped, .interrupted: return true
        default: return false
        }
    }

    var isActive: Bool { !isTerminal }
}

/// Допустимые переходы между состояниями.
enum SessionTransition {
    /// Истина, если переход from -> to допустим.
    static func isAllowed(from: SessionState, to: SessionState) -> Bool {
        let allowed: Set<[SessionState]> = [
            [.running, .interactive],     // промоут в интерактив (PTY)
            [.running, .completed],       // нормальное завершение
            [.running, .stopped],         // остановка пользователем
            [.running, .interrupted],     // прерывание (выход из приложения)
            [.interactive, .completed],
            [.interactive, .stopped],
            [.interactive, .interrupted],
        ]
        return allowed.contains([from, to])
    }
}

/// Сессия запуска терминальной команды.
struct Session: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var command: String
    var state: SessionState
    var createdAt: Date
    var finishedAt: Date?
    var output: String
    var pid: Int32?
    var pgid: Int32?
    var isPinned: Bool
    var exitCode: Int32?
    /// Директория, в которой запускалась команда (nil — сессии до появления cd).
    var directory: String?
    /// Вывод с цветом (ANSI SGR) для отображения; `output` — тот же текст без оформления.
    var outputANSI: String?
    /// Пропущенная середина в превью работающей команды (после выхода — nil, вывод полный).
    var outputGap: OutputGap?
    /// Сколько строк начала вывода не сохранилось (вывод длиннее буфера терминала); nil — всё на месте.
    var outputDropped: Int?
    /// Шаги конвейера по сохранённому выводу (`grep foo`, `sort`…); nil — нет.
    var pipeStages: [String]?
    /// Исходный вывод команды, пока к нему применён конвейер (`output` — результат конвейера).
    var rawOutput: String?
    var rawOutputANSI: String?
    /// Незнакомая шеллу команда, пока он не ответил: блок не показывается (опечатка не мелькает).
    var isProvisional: Bool?
    /// Форматирование вывода включили или выключили кнопкой {} (⌘R); nil — как в настройках.
    var formatted: Bool?

    var pipeline: [String] { pipeStages ?? [] }

    init(id: UUID = UUID(),
         command: String,
         state: SessionState = .running,
         createdAt: Date = Date(),
         finishedAt: Date? = nil,
         output: String = "",
         pid: Int32? = nil,
         pgid: Int32? = nil,
         isPinned: Bool = false,
         exitCode: Int32? = nil,
         directory: String? = nil) {
        self.id = id
        self.command = command
        self.state = state
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.output = output
        self.pid = pid
        self.pgid = pgid
        self.isPinned = isPinned
        self.exitCode = exitCode
        self.directory = directory
    }

    /// Возвращает копию с применённым переходом состояния, либо nil, если переход недопустим.
    func transitioning(to newState: SessionState) -> Session? {
        guard SessionTransition.isAllowed(from: state, to: newState) else { return nil }
        var copy = self
        copy.state = newState
        if newState.isTerminal {
            copy.finishedAt = copy.finishedAt ?? Date()
        }
        return copy
    }
}

/// Пропуск в выводе: после первых `after` строк скрыто ещё `count`.
struct OutputGap: Codable, Equatable, Hashable {
    var after: Int
    var count: Int
}
