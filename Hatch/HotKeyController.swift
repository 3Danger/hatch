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
}
