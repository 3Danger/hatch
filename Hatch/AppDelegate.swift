import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, HotKeyDelegate {
    private lazy var settings = SettingsStore()
    private lazy var history = HistoryStore()
    private lazy var sessionStore = SessionStore(history: history)
    private lazy var runner = ProcessRunner(sessionStore: sessionStore, settings: settings)
    private var hotKeyController: HotKeyController?
    private var statusItem: NSStatusItem?
    private var panelController: FloatingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // до первого обращения к настройкам и истории (они создаются лениво)
        LegacyMigration.run()

        if CommandLine.arguments.contains("--selftest") {
            exit(SelfTest().run())
        }

        // список команд для автодополнения — заранее, чтобы первый TAB был мгновенным
        CommandIndex.shared(for: settings.shellPath).prewarm()

        let controller = HotKeyController(delegate: self)
        hotKeyController = controller
        controller.rebind(settings.hotkeyString)

        setupStatusItem()

        let root = LauncherRootView()
            .environment(sessionStore)
            .environment(runner)
            .environment(settings)
            .environment(controller)

        panelController = FloatingWindowController(rootView: root)
        panelController?.show()
    }

    func hotKeyPressed() {
        panelController?.toggle()
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
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
