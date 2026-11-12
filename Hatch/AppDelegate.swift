import AppKit
import SwiftUI
import Observation

final class AppDelegate: NSObject, NSApplicationDelegate, HotKeyDelegate {
    private lazy var settings = SettingsStore()
    private lazy var history = HistoryStore()
    private lazy var sessionStore = SessionStore(history: history)
    private lazy var runner = ProcessRunner(sessionStore: sessionStore, settings: settings)
    private lazy var clipboard = ClipboardHistory(fileURL: ClipboardHistory.defaultFileURL)
    private var clipboardWatcher: ClipboardWatcher?
    private var hotKeyController: HotKeyController?
    private var statusItem: NSStatusItem?
    private var panelController: FloatingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest().run())
        }

        // Под тестами Hatch — только хост тестов: без панели, хоткея, значка и настоящей истории.
        // Иначе тест, нажимая клавиши, попадал бы и в эту панель — с историей пользователя.
        if Self.isRunningTests { return }

        // новая сборка закрывает старую: до чтения истории и до захвата горячей клавиши
        SingleInstance.terminateOthers()

        // до первого обращения к настройкам и истории (они создаются лениво)
        LegacyMigration.run()

        // список команд для автодополнения — заранее, чтобы первый TAB был мгновенным
        CommandIndex.shared(for: settings.shellPath).prewarm()

        let controller = HotKeyController(delegate: self)
        hotKeyController = controller
        controller.rebind(settings.hotkeyString)

        setupStatusItem()
        observeStatusIcon()

        // история буфера (⌘4): старое удаляется при запуске, дальше — при каждом копировании
        clipboard.prune(days: settings.clipboardDays)
        let watcher = ClipboardWatcher(history: clipboard, settings: settings)
        watcher.start()
        clipboardWatcher = watcher

        let root = LauncherRootView()
            .environment(sessionStore)
            .environment(runner)
            .environment(settings)
            .environment(controller)
            .environment(clipboard)

        panelController = FloatingWindowController(rootView: root)
        panelController?.show()
    }

    /// История пишется отложенно — при выходе записываем то, что не успело.
    func applicationWillTerminate(_ notification: Notification) {
        // под тестами историю не открывали — и записывать нечего (ленивое хранилище открыло бы настоящую)
        guard !Self.isRunningTests else { return }
        sessionStore.flush()
        clipboard.flush()
    }

    /// Повторный запуск Hatch.app (Spotlight, Finder, Dock) открывает панель —
    /// выход, если значок скрыт, а горячая клавиша не срабатывает.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return false
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func hotKeyPressed() {
        panelController?.toggle()
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // macOS запоминает место значка, если его перетащили с ⌘
        item.autosaveName = "HatchStatusItem"
        item.isVisible = settings.showStatusIcon
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "Hatch")
            button.action = #selector(statusItemClicked)
            button.target = self
        }
        let menu = NSMenu()
        menu.addItem(withTitle: "Показать лаунчер", action: #selector(showLauncher), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выход", action: #selector(quitApp), keyEquivalent: "q")
        item.menu = menu
        statusItem = item
    }

    /// Переключатель «Значок в строке меню» срабатывает сразу, без перезапуска.
    private func observeStatusIcon() {
        withObservationTracking {
            _ = settings.showStatusIcon
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                self.statusItem?.isVisible = self.settings.showStatusIcon
                self.observeStatusIcon()
            }
        }
    }

    @objc private func statusItemClicked() {
        // по клику на иконку показываем/скрываем лаунчер
        panelController?.toggle()
    }

    @objc private func showLauncher() {
        panelController?.show()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
