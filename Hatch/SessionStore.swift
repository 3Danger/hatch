import Foundation
import Observation

/// Центральное хранилище сессий, привязанное к UI.
@Observable
final class SessionStore {
    private(set) var sessions: [Session] = []
    /// Запрос поиска (⌘F): ищется в командах и в выводе. Пусто — показываются все.
    var filterText: String = ""

    private let history: HistoryStore

    init(history: HistoryStore = HistoryStore()) {
        self.history = history
        let loaded = history.load()
        self.sessions = loaded.map(Self.markInterruptedIfActive)
        if sessions != loaded { persist() }
    }

    /// Процессы прошлого запуска приложения нам больше не принадлежат: активные сессии — interrupted.
    /// pid/pgid сбрасываются, чтобы stop не убил чужую группу с переиспользованным номером.
    private static func markInterruptedIfActive(_ session: Session) -> Session {
        guard var updated = session.transitioning(to: .interrupted) else { return session }
        updated.pid = nil
        updated.pgid = nil
        return updated
    }

    /// Сессии с учётом фильтра и сортировки: закреплённые выше, затем активные, затем по времени.
    var filteredSessions: [Session] {
        var result = sessions.filter { $0.isProvisional != true }
        if !filterText.isEmpty {
            let query = filterText
            result = result.filter {
                $0.command.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                    || $0.output.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
        // закрепление защищает от очистки, но порядок не меняет
        return result.sorted { a, b in
            if a.state.isActive != b.state.isActive {
                return a.state.isActive && !b.state.isActive
            }
            return a.createdAt > b.createdAt
        }
    }

    func add(_ session: Session) {
        sessions.insert(session, at: 0)
        persist()
    }

    /// Когда изменение попадает на диск.
    enum Persistence {
        /// Отложенно: частые изменения сливаются в одну запись не чаще раза в секунду.
        case soon
        /// Не писать (превью работающей команды — итог запишется при её завершении).
        case never
    }

    func update(id: UUID, persist persistence: Persistence = .soon, transform: (inout Session) -> Void) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        transform(&sessions[idx])
        if persistence == .soon { scheduleSave() }
    }

    func remove(id: UUID) {
        sessions.removeAll { $0.id == id }
        persist()
    }

    func remove(ids: Set<UUID>) {
        sessions.removeAll { ids.contains($0.id) }
        persist()
    }

    /// Что удалит «Очистить историю»: завершённые; активные — только если кроме них ничего нет.
    /// Что удалит «Очистить историю» — первый непустой уровень:
    /// незакреплённые завершённые → незакреплённые активные → закреплённые завершённые → закреплённые активные.
    /// Закреплённые трогаются, только когда незакреплённых не осталось.
    enum ClearScope: Equatable {
        case finished(pinned: Bool)
        case active(pinned: Bool)
        case nothing
    }

    var clearScope: ClearScope {
        for pinned in [false, true] {
            let group = sessions.filter { $0.isPinned == pinned }
            if group.contains(where: { $0.state.isTerminal }) { return .finished(pinned: pinned) }
            if !group.isEmpty { return .active(pinned: pinned) }
        }
        return .nothing
    }

    /// Сессии, которые удалит очистка (активные перед удалением надо остановить).
    var sessionsToClear: [Session] {
        switch clearScope {
        case .finished(let pinned):
            return sessions.filter { $0.isPinned == pinned && $0.state.isTerminal }
        case .active(let pinned):
            return sessions.filter { $0.isPinned == pinned && $0.state.isActive }
        case .nothing:
            return []
        }
    }

    /// `clear` и ⌃L: убрать завершённые незакреплённые, работающие и закреплённые остаются.
    /// Возвращает удалённые — их можно вернуть (`restore`).
    @discardableResult
    func clearFinished() -> [Session] {
        let removed = sessions.filter { $0.state.isTerminal && !$0.isPinned }
        guard !removed.isEmpty else { return [] }
        let ids = Set(removed.map(\.id))
        sessions.removeAll { ids.contains($0.id) }
        persist()
        return removed
    }

    /// «Отменить» после очистки: удалённые возвращаются на свои места (по времени запуска).
    func restore(_ removed: [Session]) {
        let present = Set(sessions.map(\.id))
        let back = removed.filter { !present.contains($0.id) }
        guard !back.isEmpty else { return }
        sessions = (sessions + back).sorted { $0.createdAt > $1.createdAt }
        persist()
    }

    func clearCompleted() {
        sessions.removeAll { !$0.state.isActive }
        persist()
    }

    /// Удаляет все сессии (после остановки активных).
    func clearAll() {
        sessions.removeAll()
        persist()
    }

    func togglePin(id: UUID) {
        guard let idx = sessions.firstIndex(where: { $0.id == id }) else { return }
        sessions[idx].isPinned.toggle()
        persist()
    }

    func activeIDs() -> [UUID] {
        sessions.filter { $0.state.isActive }.map(\.id)
    }

    /// Обновляет текущее значение N для капа и применяет его к завершённым.
    func applyHistoryLimit(_ limit: Int) {
        sessions = history.applyCap(to: sessions, limit: limit)
        persist()
    }

    /// Записать отложенные изменения сейчас (при закрытии приложения).
    func flush() {
        persist()
    }

    private static let saveDelay: TimeInterval = 1
    private var pendingSave: DispatchWorkItem?

    private func scheduleSave() {
        guard pendingSave == nil else { return } // запись уже запланирована — её хватит
        let work = DispatchWorkItem { [weak self] in
            self?.pendingSave = nil
            self?.persist()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    private func persist() {
        pendingSave?.cancel()
        pendingSave = nil
        history.save(sessions)
    }
}
