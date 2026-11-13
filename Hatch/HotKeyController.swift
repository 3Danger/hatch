import Foundation
import Observation

/// Пере-регистрация глобального хоткей при изменении настройки.
@Observable
final class HotKeyController {
    private let manager: HotKeyManager
    private var currentSpec: String?

    init(delegate: HotKeyDelegate) {
        manager = HotKeyManager(delegate: delegate)
    }

    /// Перепривязывает хоткей по строковому описанию.
    func rebind(_ spec: String) {
        guard spec != currentSpec else { return }
        guard let binding = KeyBindingParser.parse(spec) else { return }
        currentSpec = spec
        _ = manager.register(binding, identifier: 1)
    }

    private static let screenshotID: UInt32 = 2
    private var currentScreenshotSpec: String?

    /// Сочетание снимка экрана (работает и когда панель скрыта); nil — выключено.
    func rebindScreenshot(_ spec: String?, action: @escaping () -> Void) {
        manager.handlers[Self.screenshotID] = action
        guard spec != currentScreenshotSpec else { return }
        currentScreenshotSpec = spec
        guard let spec, let binding = KeyBindingParser.parse(spec) else {
            manager.unregister(identifier: Self.screenshotID)
            return
        }
        _ = manager.register(binding, identifier: Self.screenshotID)
    }
}
