import AppKit
import Observation

/// Скопированный фрагмент в буфере Hatch (⌘4).
struct Clip: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var text: String
    /// Откуда скопировано: «Safari», «Hatch»; nil — неизвестно.
    var app: String?
    var bundleID: String?
    var copiedAt: Date
    /// Путь к файлу из Finder, а не текст.
    var isPath = false

    var lineCount: Int { text.split(separator: "\n", omittingEmptySubsequences: false).count }
}

/// История буфера обмена: свежие сверху, без повторов, не больше `limit` и не старше `days`.
/// Хранится локально в `~/Library/Application Support/Hatch/clipboard.json` (доступ только владельцу).
@Observable
final class ClipboardHistory {
    private(set) var clips: [Clip] = []
    static let limit = 200
    /// Самый длинный фрагмент, который сохраняем: больше — скорее файл или дамп, а не то, что вставляют.
    static let maxLength = 100_000

    @ObservationIgnored private let fileURL: URL?
    @ObservationIgnored private var pendingSave: DispatchWorkItem?

    /// - Parameter fileURL: nil — только в памяти (тесты интерфейса).
    init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder.clips.decode([Clip].self, from: data) {
            clips = decoded
        }
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("Hatch", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clipboard.json")
    }

    /// Новый фрагмент наверх. Такой же уже есть — поднимается наверх, откуда скопирован впервые, не меняется
    /// (Enter в Hatch копирует фрагмент снова — он не должен стать «из Hatch»).
    func record(_ clip: Clip, days: Int) {
        let text = clip.text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= Self.maxLength else { return }
        var entry = clip
        if let index = clips.firstIndex(where: { $0.text == text }) {
            let existing = clips.remove(at: index)
            entry.id = existing.id
            entry.app = existing.app ?? clip.app
            entry.bundleID = existing.bundleID ?? clip.bundleID
            entry.isPath = existing.isPath || clip.isPath
        }
        clips.insert(entry, at: 0)
        prune(days: days, now: clip.copiedAt)
        scheduleSave()
    }

    /// Старше `days` дней и сверх лимита — удаляются.
    func prune(days: Int, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-TimeInterval(max(days, 1)) * 86_400)
        let kept = Array(clips.filter { $0.copiedAt >= cutoff }.prefix(Self.limit))
        if kept != clips {
            clips = kept
            scheduleSave()
        }
    }

    func remove(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
        scheduleSave()
    }

    func clear() {
        clips = []
        scheduleSave()
    }

    /// Фрагменты, где встречается запрос (без учёта регистра); пустой запрос — все.
    func matching(_ query: String) -> [Clip] {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return clips }
        return clips.filter { $0.text.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    /// Записать сразу (при выходе из приложения).
    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        save()
    }

    private func scheduleSave() {
        guard fileURL != nil else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func save() {
        guard let fileURL, let data = try? JSONEncoder.clips.encode(clips) else { return }
        try? data.write(to: fileURL, options: [.atomic])
        // скопированное бывает личным — файл читает только владелец
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}

private extension JSONEncoder {
    static var clips: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var clips: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Копирование из самого Hatch (вывод блока, путь, результат расчёта, фрагмент из буфера):
/// помечается, чтобы в буфере Hatch было видно «Hatch», а не приложение под панелью.
enum Clipboard {
    static let hatchMarker = NSPasteboard.PasteboardType("io.github.3danger.hatch.copy")

    static func copy(_ text: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        pasteboard.setString("", forType: hatchMarker)
    }
}

/// Следит за системным буфером: уведомлений о копировании нет, поэтому раз в полсекунды
/// сверяется счётчик изменений (это дёшево), а содержимое читается только после изменения.
/// Не сохраняет пароли: менеджеры паролей помечают их как скрытые или временные (nspasteboard.org).
final class ClipboardWatcher {
    /// Пометки «не сохранять в истории буфера» (соглашение nspasteboard.org, 1Password и др.).
    static let skippedTypes: Set<String> = [
        "org.nspasteboard.ConcealedType",
        "org.nspasteboard.TransientType",
        "org.nspasteboard.AutoGeneratedType",
        "com.agilebits.onepassword",
        "de.petermaurer.TransientPasteboardType",
        "com.typeit4me.clipping",
        "Pasteboard generator type",
    ]

    private let pasteboard: NSPasteboard
    private let history: ClipboardHistory
    private let settings: SettingsStore
    /// Приложение, из которого скопировали: то, что впереди (Hatch — неактивирующая панель).
    private let frontmost: () -> NSRunningApplication?
    private var lastChange: Int
    private var timer: Timer?

    init(pasteboard: NSPasteboard = .general, history: ClipboardHistory, settings: SettingsStore,
         frontmost: @escaping () -> NSRunningApplication? = { NSWorkspace.shared.frontmostApplication }) {
        self.pasteboard = pasteboard
        self.history = history
        self.settings = settings
        self.frontmost = frontmost
        // то, что лежало в буфере до запуска, не записываем: неизвестно, когда и откуда оно
        self.lastChange = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Проверить буфер сейчас (таймер и тесты).
    func poll(now: Date = Date()) {
        let change = pasteboard.changeCount
        guard change != lastChange else { return }
        lastChange = change
        guard settings.clipboardEnabled, let clip = read(now: now) else { return }
        history.record(clip, days: settings.clipboardDays)
    }

    private func read(now: Date) -> Clip? {
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: Self.skippedTypes) else { return nil }
        if types.contains(Clipboard.hatchMarker.rawValue) {
            guard let text = pasteboard.string(forType: .string) else { return nil }
            return Clip(text: text, app: "Hatch", bundleID: Bundle.main.bundleIdentifier, copiedAt: now)
        }
        let app = frontmost()
        if let id = app?.bundleIdentifier, settings.clipboardExcludedApps.contains(id) { return nil }
        // файлы из Finder — путями, по одному на строку: так их вставляют в команды
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !urls.isEmpty {
            let paths = urls.map { ShellCompletionEngine.normalizeHomePath($0.path) }
            return Clip(text: paths.joined(separator: "\n"), app: app?.localizedName, bundleID: app?.bundleIdentifier,
                        copiedAt: now, isPath: true)
        }
        guard let text = pasteboard.string(forType: .string) else { return nil }
        return Clip(text: text, app: app?.localizedName, bundleID: app?.bundleIdentifier, copiedAt: now)
    }
}
