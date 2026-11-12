import AppKit
import SwiftTerm

/// Терминал сессии: эмулятор SwiftTerm поверх настоящего PTY с управляющим терминалом.
/// Через него идут все команды — утилиты видят tty и ведут себя как в zsh (цвет, прогресс-бары,
/// Ctrl-C, изменение размера, `/dev/tty`). Вью живёт, пока жив процесс: в раскрытом блоке
/// это живой терминал, при сворачивании экран сохраняется.
final class InteractiveTerminal: NSObject, LocalProcessTerminalViewDelegate {
    /// Размер области раскрытого блока: с ним процесс стартует, дальше вью подстраивается сама.
    static let initialFrame = NSRect(x: 0, y: 0, width: 640, height: 410)
    /// Сколько строк хранит эмулятор: из них собирается итоговый вывод в истории.
    /// Что не поместилось, вытесняется из начала — сколько, видно в блоке.
    static let defaultScrollback = 50_000
    /// Превью работающей команды: столько строк с начала и с конца (середина — числом).
    /// С запасом на самый высокий блок — свежий, растянутый на свободное место.
    static let previewEdgeLines = 20
    /// Не чаще одного снимка превью за этот интервал: поток вывода не грузит интерфейс.
    private static let previewInterval: TimeInterval = 0.15

    let view: SessionTerminalView
    /// Превью вывода, пока процесс работает (на main, с ограничением частоты).
    var onOutput: ((TerminalSnapshot) -> Void)?
    /// Вызывается на main после выхода: код выхода и итоговый экран.
    var onExit: ((Int32, TerminalSnapshot) -> Void)?

    var pid: pid_t { view.process.shellPid }

    private var finished = false
    private var previewScheduled = false
    /// Когда терминал последний раз получил порцию вывода.
    private var lastDataAt = Date()
    /// Тишина после конца вывода, после которой экран считается дочитанным.
    private static let drainQuiet: TimeInterval = 0.1
    /// Дольше ждать дочитывания не будем (вывод от фоновых потомков и т.п.).
    private static let drainTimeout: TimeInterval = 15

    init(scrollback: Int = InteractiveTerminal.defaultScrollback) {
        view = SessionTerminalView(frame: Self.initialFrame)
        view.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        view.changeScrollback(scrollback)
        super.init()
        view.processDelegate = self
        view.onData = { [weak self] in
            self?.lastDataAt = Date()
            self?.schedulePreview()
        }
    }

    /// Запускает `shell -lc script`; false — процесс не стартовал.
    func start(shell: String, script: String, directory: String, environment: [String: String]) -> Bool {
        view.startProcess(executable: shell,
                          args: ["-lc", script],
                          environment: Self.terminalEnvironment(environment),
                          execName: nil,
                          currentDirectory: directory)
        return pid > 0
    }

    /// Цвета как у поля вывода в блоке: тёмная лунка в тёмной теме, светлая — в светлой.
    /// Без этого SwiftTerm рисует системный фон — белый прямоугольник посреди тёмной панели.
    func applyColors(dark: Bool) {
        guard appliedDark != dark else { return }
        appliedDark = dark
        view.nativeBackgroundColor = dark ? NSColor(srgbRed: 0x1d / 255, green: 0x1d / 255, blue: 0x1f / 255, alpha: 1)
                                          : NSColor(srgbRed: 0xe6 / 255, green: 0xe6 / 255, blue: 0xea / 255, alpha: 1)
        view.nativeForegroundColor = dark ? NSColor(srgbRed: 0xd5 / 255, green: 0xd5 / 255, blue: 0xda / 255, alpha: 1)
                                          : NSColor(srgbRed: 0x1d / 255, green: 0x1d / 255, blue: 0x1f / 255, alpha: 1)
        view.caretColor = .controlAccentColor
        view.needsDisplay = true
    }
    private var appliedDark: Bool?

    /// Ввод в процесс, как с клавиатуры.
    func send(_ text: String) {
        view.process.send(data: ArraySlice(Array(text.utf8)))
    }

    /// Текущий экран целиком (например, для копирования вывода работающей команды).
    func snapshot() -> TerminalSnapshot {
        TerminalSnapshot.capture(view.getTerminal())
    }

    // MARK: - LocalProcessTerminalViewDelegate

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        finish(status: exitCode)
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}

    // MARK: - Private

    private func schedulePreview() {
        guard !previewScheduled, !finished else { return }
        previewScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.previewInterval) { [weak self] in
            guard let self else { return }
            self.previewScheduled = false
            guard !self.finished else { return }
            self.onOutput?(TerminalSnapshot.capture(self.view.getTerminal(),
                                                    head: Self.previewEdgeLines, tail: Self.previewEdgeLines))
        }
    }

    private func finish(status: Int32?) {
        guard !finished else { return }
        finished = true
        let code = status.map(Self.exitStatus) ?? -1
        deliverWhenDrained(code: code, since: Date())
    }

    /// Процесс завершился раньше, чем терминал разобрал его вывод: большой быстрый вывод
    /// доходит порциями ещё какое-то время. Снимок — когда вывод дочитан до конца (EOF)
    /// и новых порций нет; иначе терялся бы конец вывода — итог команды.
    private func deliverWhenDrained(code: Int32, since start: Date) {
        let reachedEnd = view.process.childfd == -1
        let quiet = Date().timeIntervalSince(lastDataAt) >= Self.drainQuiet
        if (reachedEnd && quiet) || Date().timeIntervalSince(start) > Self.drainTimeout {
            onExit?(code, snapshot())
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.deliverWhenDrained(code: code, since: start)
        }
    }

    /// Сырой статус waitpid → код выхода; для убитых сигналом — номер сигнала, как у `Process`.
    private static func exitStatus(_ status: Int32) -> Int32 {
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : signal
    }

    /// Окружение команды + то, что нужно TUI: TERM и UTF-8.
    private static func terminalEnvironment(_ base: [String: String]) -> [String] {
        var env = base
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        if env["LANG"] == nil { env["LANG"] = "en_US.UTF-8" }
        return env.map { "\($0.key)=\($0.value)" }
    }
}

/// Терминальная вью, которая сообщает о каждой порции вывода (для превью в блоке).
final class SessionTerminalView: LocalProcessTerminalView {
    var onData: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        hideScroller()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        hideScroller()
    }

    /// Полосы прокрутки в Hatch нет: терминал листается колёсиком и трекпадом.
    /// Скрытая полоса не занимает места — терминалу достаётся вся ширина.
    private func hideScroller() {
        subviews.compactMap { $0 as? NSScroller }.forEach { $0.isHidden = true }
    }

    override func dataReceived(slice: ArraySlice<UInt8>) {
        super.dataReceived(slice: slice)
        onData?()
    }
}
