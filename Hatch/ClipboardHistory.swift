import AppKit
import Observation
import CryptoKit

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
    /// Закреплён: наверху, не удаляется очисткой, сроком и лимитом. Необязательный ключ —
    /// файлы буфера из 0.1.7, где его нет, читаются как раньше.
    var pinned: Bool?

    /// Картинка (скриншот, «Скопировать изображение»); у неё `text` пустой. Необязательный ключ —
    /// файлы буфера до картинок читаются как раньше.
    var image: ClipImage?

    /// Форматирование включили или выключили кнопкой {} (⌘R); nil — как в настройках.
    var formatted: Bool?

    var isPinned: Bool {
        get { pinned == true }
        set { pinned = newValue ? true : nil }
    }

    var isImage: Bool { image != nil }

    var lineCount: Int { text.split(separator: "\n", omittingEmptySubsequences: false).count }
}

/// Тип фрагментов в фильтре над полем (⌘4): Tab и ⇧Tab листают по кругу. Пути к файлам — это текст.
enum ClipKind: String, CaseIterable {
    case all, text, images, pinned

    func includes(_ clip: Clip) -> Bool {
        switch self {
        case .all: true
        case .text: !clip.isImage
        case .images: clip.isImage
        case .pinned: clip.isPinned
        }
    }

    /// Следующий (+1) или предыдущий (−1) тип по кругу.
    func next(_ step: Int) -> ClipKind {
        let all = Self.allCases
        let index = all.firstIndex(of: self)!
        return all[(index + step + all.count) % all.count]
    }
}

/// Картинка в буфере: PNG-файл рядом с историей, размер в точках изображения и распознанный текст.
struct ClipImage: Codable, Equatable, Hashable {
    /// Имя файла в папке картинок буфера.
    var file: String
    var width: Int
    var height: Int
    var bytes: Int
    /// SHA-256 содержимого: та же картинка скопирована снова — поднимается наверх, а не дублируется.
    var hash: String
    /// Текст со скриншота (распознаётся в фоне); nil — ещё не распознан или распознавание выключено.
    var text: String?

    /// Первая строка распознанного текста — вместо названия картинки.
    var firstLine: String? {
        text?.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.count >= 3 }
    }

    /// «1440 × 900 · 412 КБ» (единицы — на языке интерфейса Hatch).
    func summary(lang: String) -> String {
        "\(width) × \(height) · " + Self.size(bytes, lang: lang)
    }

    static func size(_ bytes: Int, lang: String) -> String {
        let ru = lang == "ru"
        if bytes < 1024 * 1024 { return "\(max(1, Int((Double(bytes) / 1024).rounded()))) " + (ru ? "КБ" : "KB") }
        let megabytes = String(format: "%.1f", Double(bytes) / 1024 / 1024)
        return (ru ? megabytes.replacingOccurrences(of: ".", with: ",") : megabytes) + (ru ? " МБ" : " MB")
    }
}

/// История буфера обмена: свежие сверху, без повторов, не больше `limit` и не старше `days`.
/// Закреплённые показываются отдельной группой наверху и в срок и лимит не входят.
/// Хранится локально в `~/Library/Application Support/Hatch/clipboard.json` (доступ только владельцу).
@Observable
final class ClipboardHistory {
    private(set) var clips: [Clip] = []
    static let limit = 200
    /// Картинок — меньше: каждая — файл на диске.
    static let imageLimit = 50
    /// Больше — не сохраняем: скорее огромный скан или RAW, чем то, что вставляют.
    static let maxImageBytes = 20 * 1024 * 1024
    /// Самый длинный фрагмент, который сохраняем: больше — скорее файл или дамп, а не то, что вставляют.
    static let maxLength = 100_000

    @ObservationIgnored private let fileURL: URL?
    /// Папка PNG-файлов картинок (рядом с историей); nil — картинки не сохраняются.
    @ObservationIgnored let imagesDirectory: URL?
    @ObservationIgnored private var pendingSave: DispatchWorkItem?
    @ObservationIgnored private var pendingCleanup: DispatchWorkItem?

    /// - Parameters:
    ///   - fileURL: nil — только в памяти (тесты интерфейса);
    ///   - imagesDirectory: куда класть картинки; по умолчанию — `clipboard-images` рядом с историей.
    init(fileURL: URL?, imagesDirectory: URL? = nil) {
        self.fileURL = fileURL
        self.imagesDirectory = imagesDirectory
            ?? fileURL?.deletingLastPathComponent().appendingPathComponent("clipboard-images", isDirectory: true)
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
            entry.pinned = existing.pinned
            entry.formatted = existing.formatted
        }
        clips.insert(entry, at: 0)
        prune(days: days, now: clip.copiedAt)
        scheduleSave()
    }

    /// Старше `days` дней и сверх лимитов — удаляются. Закреплённые остаются всегда.
    func prune(days: Int, now: Date = Date()) {
        let cutoff = now.addingTimeInterval(-TimeInterval(max(days, 1)) * 86_400)
        var unpinnedKept = 0
        var imagesKept = 0
        let kept = clips.filter { clip in
            if clip.isPinned { return true }
            guard clip.copiedAt >= cutoff, unpinnedKept < Self.limit else { return false }
            if clip.isImage {
                guard imagesKept < Self.imageLimit else { return false }
                imagesKept += 1
            }
            unpinnedKept += 1
            return true
        }
        if kept != clips {
            clips = kept
            scheduleSave()
            scheduleImageCleanup()
        }
    }

    func remove(_ clip: Clip) {
        clips.removeAll { $0.id == clip.id }
        scheduleSave()
        scheduleImageCleanup()
    }

    func clear() {
        clips = []
        scheduleSave()
        scheduleImageCleanup()
    }

    // MARK: - Картинки

    /// Новая картинка наверх; та же (по содержимому) — поднимается наверх, откуда скопирована впервые.
    /// nil — не сохранена (больше 20 МБ, нет папки, не записалась).
    @discardableResult
    func recordImage(png: Data, width: Int, height: Int, app: String?, bundleID: String?,
                     at date: Date = Date(), days: Int) -> Clip? {
        guard let imagesDirectory, png.count <= Self.maxImageBytes, !png.isEmpty else { return nil }
        let hash = Self.sha256(png)
        if let index = clips.firstIndex(where: { $0.image?.hash == hash }) {
            var existing = clips.remove(at: index)
            existing.copiedAt = date
            clips.insert(existing, at: 0)
            scheduleSave()
            return existing
        }
        let file = UUID().uuidString + ".png"
        do {
            try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let url = imagesDirectory.appendingPathComponent(file)
            try png.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch {
            return nil
        }
        let clip = Clip(text: "", app: app, bundleID: bundleID, copiedAt: date,
                        image: ClipImage(file: file, width: width, height: height, bytes: png.count, hash: hash))
        clips.insert(clip, at: 0)
        prune(days: days, now: date)
        scheduleSave()
        return clip
    }

    /// {} у записи: форматировать или показывать как есть.
    func setFormatted(_ value: Bool?, for clipID: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return }
        clips[index].formatted = value
        scheduleSave()
    }

    /// Распознанный текст картинки (в фоне, после сохранения).
    func setRecognizedText(_ text: String, for clipID: UUID) {
        guard let index = clips.firstIndex(where: { $0.id == clipID }), clips[index].image != nil else { return }
        clips[index].image?.text = text
        scheduleSave()
    }

    func imageURL(_ clip: Clip) -> URL? {
        guard let file = clip.image?.file else { return nil }
        return imagesDirectory?.appendingPathComponent(file)
    }

    /// Файлы картинок, которых больше нет в истории, удаляются не сразу: 5 секунд после очистки
    /// работает «Отменить». Без истории (тесты) — не трогаем.
    private func scheduleImageCleanup() {
        guard imagesDirectory != nil else { return }
        pendingCleanup?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.removeUnusedImageFiles() }
        pendingCleanup = work
        DispatchQueue.main.asyncAfter(deadline: .now() + PanelToast.duration + 5, execute: work)
    }

    /// Удалить PNG, на которые не ссылается ни один фрагмент (и после запуска — оставшиеся от прошлого).
    func removeUnusedImageFiles() {
        guard let imagesDirectory,
              let files = try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path) else { return }
        let used = Set(clips.compactMap { $0.image?.file })
        for file in files where file.hasSuffix(".png") && !used.contains(file) {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file))
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Закрепить или открепить. Открепленный встаёт к недавним на своё место по времени копирования.
    func togglePin(_ clip: Clip) {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[index].isPinned.toggle()
        scheduleSave()
    }

    /// Корзина и ⌃L в режиме буфера: убрать незакреплённые. Возвращает убранное — для «Отменить».
    @discardableResult
    func clearUnpinned() -> [Clip] {
        let removed = clips.filter { !$0.isPinned }
        guard !removed.isEmpty else { return [] }
        clips.removeAll { !$0.isPinned }
        scheduleSave()
        scheduleImageCleanup()
        return removed
    }

    /// «Отменить» после очистки: убранное возвращается на свои места (по времени копирования).
    func restore(_ removed: [Clip]) {
        let ids = Set(clips.map(\.id))
        let back = removed.filter { !ids.contains($0.id) }
        guard !back.isEmpty else { return }
        let pinned = clips.filter(\.isPinned)
        let recent = (clips.filter { !$0.isPinned } + back).sorted { $0.copiedAt > $1.copiedAt }
        clips = pinned + recent
        scheduleSave()
    }

    /// Фрагменты, где встречается запрос (без учёта регистра); пустой запрос — все.
    /// Картинки ищутся по распознанному тексту, приложению и словам «картинка», «скриншот», «image».
    /// Порядок как в списке: сначала закреплённые, затем недавние.
    func matching(_ query: String, kind: ClipKind = .all) -> [Clip] {
        let query = query.trimmingCharacters(in: .whitespaces)
        let found = clips.filter { kind.includes($0) && (query.isEmpty || Self.matches($0, query)) }
        return found.filter(\.isPinned) + found.filter { !$0.isPinned }
    }

    /// Сколько фрагментов каждого типа подходит под запрос — числа в фильтре над полем.
    func counts(_ query: String) -> [ClipKind: Int] {
        let found = matching(query)
        return Dictionary(uniqueKeysWithValues: ClipKind.allCases.map { kind in (kind, found.filter(kind.includes).count) })
    }

    private static let imageWords = ["картинка", "изображение", "скриншот", "снимок", "image", "picture", "screenshot"]

    static func matches(_ clip: Clip, _ query: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        guard let image = clip.image else { return clip.text.range(of: query, options: options) != nil }
        let lower = query.lowercased()
        if imageWords.contains(where: { $0.hasPrefix(lower) }) { return true }
        if let app = clip.app, app.range(of: query, options: options) != nil { return true }
        return image.text?.range(of: query, options: options) != nil
    }

    /// Строка распознанного текста, где нашёлся запрос, — показать, почему картинка в результатах.
    static func matchedLine(_ clip: Clip, _ query: String) -> String? {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty, let text = clip.image?.text else { return nil }
        return text.split(whereSeparator: \.isNewline).map(String.init)
            .first { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
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

    /// Картинку из буфера Hatch — обратно в системный буфер (PNG и TIFF: вставится куда угодно).
    @discardableResult
    static func copyImage(at url: URL, to pasteboard: NSPasteboard = .general) -> Bool {
        guard let png = try? Data(contentsOf: url) else { return false }
        pasteboard.clearContents()
        pasteboard.setData(png, forType: .png)
        if let tiff = NSImage(data: png)?.tiffRepresentation { pasteboard.setData(tiff, forType: .tiff) }
        pasteboard.setString("", forType: hatchMarker)
        return true
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
        guard settings.clipboardEnabled else { return }
        if let clip = read(now: now) {
            history.record(clip, days: settings.clipboardDays)
        } else if settings.clipboardImages, let image = readImage() {
            let source = source()
            guard let clip = history.recordImage(png: image.png, width: image.width, height: image.height,
                                                 app: source.app, bundleID: source.bundleID, at: now,
                                                 days: settings.clipboardDays) else { return }
            // текст со скриншота — в фоне; панель и следующее копирование не ждут
            if settings.clipboardRecognizeText, clip.image?.text == nil, let url = history.imageURL(clip) {
                let history = history
                TextRecognizer.shared.recognize(url) { text in history.setRecognizedText(text, for: clip.id) }
            }
        }
    }

    /// Откуда скопировано: из Hatch (по пометке) или приложение впереди. nil в `app` — из исключений.
    private func source() -> (app: String?, bundleID: String?) {
        if pasteboard.types?.contains(Clipboard.hatchMarker) == true { return ("Hatch", Bundle.main.bundleIdentifier) }
        let app = frontmost()
        return (app?.localizedName, app?.bundleIdentifier)
    }

    /// Пропустить: пароль, пометка «не сохранять» или приложение из исключений.
    private var isSkipped: Bool {
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        if !types.isDisjoint(with: Self.skippedTypes) { return true }
        if types.contains(Clipboard.hatchMarker.rawValue) { return false }
        if let id = frontmost()?.bundleIdentifier, settings.clipboardExcludedApps.contains(id) { return true }
        return false
    }

    /// Картинка без текста (скриншот, «Скопировать изображение»): PNG и её размер в пикселях.
    /// Если в буфере есть текст (ячейки таблицы приходят и картинкой), сюда не доходит — сохранится текст.
    private func readImage() -> (png: Data, width: Int, height: Int)? {
        guard !isSkipped else { return nil }
        let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff)
            ?? pasteboard.data(forType: NSPasteboard.PasteboardType("public.jpeg"))
        guard let data, data.count <= ClipboardHistory.maxImageBytes, let rep = NSBitmapImageRep(data: data) else { return nil }
        let png = pasteboard.data(forType: .png) ?? rep.representation(using: .png, properties: [:])
        guard let png else { return nil }
        return (png, rep.pixelsWide, rep.pixelsHigh)
    }

    private func read(now: Date) -> Clip? {
        let types = Set((pasteboard.types ?? []).map(\.rawValue))
        guard types.isDisjoint(with: Self.skippedTypes) else { return nil }
        if types.contains(Clipboard.hatchMarker.rawValue) {
            guard let text = pasteboard.string(forType: .string), !text.isEmpty else { return nil }
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
        guard let text = pasteboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return Clip(text: text, app: app?.localizedName, bundleID: app?.bundleIdentifier, copiedAt: now)
    }
}
