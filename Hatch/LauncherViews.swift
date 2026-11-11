import SwiftUI
import AppKit

/// Геометрия панели. Скругления концентричны: внешний радиус = внутренний + отступ между ними,
/// иначе зазор в углах выходит шире, чем по краям.
enum LauncherMetrics {
    /// Отступ контента от края панели.
    static let padding: CGFloat = 8
    /// Радиус поля ввода и блоков истории.
    static let innerRadius: CGFloat = 16
    static let panelRadius = innerRadius + padding
    /// Отступ содержимого внутри блока истории.
    static let blockPadding: CGFloat = 12
    /// Терминал внутри раскрытого блока.
    static let terminalRadius = innerRadius - blockPadding
    static let panelWidth: CGFloat = 720
    /// Запас окна вокруг панели под её тень.
    static let shadowMargin: CGFloat = 24
    /// Предел высоты истории: дальше прокрутка. Раскрытый блок занимает её целиком.
    static let historyMaxHeight: CGFloat = 470
    /// Строк вывода в свёрнутом блоке (включая строку «скрыто N»). Свежий блок берёт больше.
    static let compactOutputLines = 7
    static let outputFontSize: CGFloat = 10
    /// Высота строки вывода: блок считает, сколько строк влезает в свободное место.
    static let outputLineHeight: CGFloat = ceil(NSLayoutManager().defaultLineHeight(
        for: NSFont.monospacedSystemFont(ofSize: outputFontSize, weight: .regular)))
    /// Всё в блоке, кроме строк вывода: отступы, заголовок, промежуток до вывода.
    static let blockChrome: CGFloat = blockPadding * 2 + 22 + 6
    static let blockSpacing: CGFloat = 8
    /// Живой терминал в раскрытом блоке: блок занимает всю видимую область истории.
    static let terminalHeight: CGFloat = historyMaxHeight - blockChrome
    /// Раскрытый завершённый вывод длиннее этого — с кнопкой «показать всё».
    static let fullOutputLimit = 1000
}

/// Корневое представление лаунчера: ввод, история, экшн-кнопки.
struct LauncherRootView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ProcessRunner.self) private var runner
    @Environment(SettingsStore.self) private var settings
    @Environment(HotKeyController.self) private var hotKeys

    @State private var text = ""
    @FocusState private var inputFocused: Bool
    @State private var pendingDelete: Session?
    /// Перезапуск работающей команды ждёт подтверждения.
    @State private var pendingRerun: Session?
    @State private var confirmClear = false
    @State private var showSettings = false
    @State private var navigator = HistoryNavigator()
    /// Раскрытый на всю область истории блок (интерактивный терминал или полный вывод).
    @State private var expandedID: UUID?
    @State private var keyMonitor: Any?
    /// Сессия, прерванная ⌃C из раскрытого блока: после остановки блок сворачивается.
    @State private var interruptedID: UUID?

    private var lang: String { settings.languageCode }

    var body: some View {
        // Высота панели — по содержимому (до предела истории); окно следует за ней.
        VStack(spacing: LauncherMetrics.padding) {
            // где мы сейчас: светлые «крошки» над полем, обновляются при cd
            DirectoryBreadcrumbsView(path: settings.currentDirectory,
                                     recent: settings.recentDirectories,
                                     lang: lang,
                                     onNavigate: { settings.currentDirectory = $0 })
                .padding(.horizontal, 14) // по левому краю текста в поле ввода
                .padding(.bottom, -4)     // ближе к полю, чем к краю панели

            CommandInputView(text: $text,
                             directory: settings.currentDirectory,
                             onSubmit: { command in
                                 navigator.reset()
                                 run(command)
                                 text = ""
                             },
                             onHistory: navigateHistory,
                             onEdit: {
                                 navigator.reset()
                                 // набранный текст заодно фильтрует блоки истории
                                 sessionStore.filterText = text.trimmingCharacters(in: .whitespaces)
                             },
                             history: historyCommands)
            .focused($inputFocused)

            // колонка кнопок отстоит от истории так же, как от края панели
            HStack(alignment: .top, spacing: LauncherMetrics.padding) {
                historyArea
                    .frame(maxWidth: .infinity, alignment: .top)
                actionsColumn
            }
        }
        .padding(LauncherMetrics.padding)
        .frame(width: LauncherMetrics.panelWidth)
        .background {
            Color.clear
                .glassEffect(in: RoundedRectangle(cornerRadius: LauncherMetrics.panelRadius))
                // за пустые места панели (поля, промежутки) окно можно перетаскивать
                .contentShape(RoundedRectangle(cornerRadius: LauncherMetrics.panelRadius))
                .gesture(WindowDragGesture())
        }
        .background { PanelShadow() }
        // прозрачный запас окна под тень: иначе её обрезает край окна
        .padding(LauncherMetrics.shadowMargin)
        .preferredColorScheme(colorScheme)
        .onAppear {
            inputFocused = true
            NotificationService().requestPermission()
            installKeyShortcuts()
        }
        .onDisappear {
            keyMonitor.map(NSEvent.removeMonitor)
            keyMonitor = nil
        }
        // Выход из vim/top и т.п. или остановка по ⌃C — блок сворачивается до заголовка.
        // Обычная команда, завершившаяся сама, остаётся раскрытой: её вывод могут читать.
        .onChange(of: expandedSession?.state) { old, new in
            guard old?.isActive ?? false, new?.isTerminal ?? true else { return }
            if old == .interactive || expandedID == interruptedID { collapse() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hatchDidShow)) { _ in
            inputFocused = true
            switchToLatinIfEnabled() // фокус мог уже стоять в поле — onChange не сработает
        }
        // курсор в поле ввода — латинская раскладка (если включено в настройках)
        .onChange(of: inputFocused) { _, focused in
            if focused { switchToLatinIfEnabled() }
        }
        .onChange(of: settings.latinLayoutInInput) { _, enabled in
            if enabled { switchToLatinIfEnabled() } else { KeyboardLayoutSwitcher.shared.restore() }
        }
        .onChange(of: settings.hotkeyString) { _, newValue in
            hotKeys.rebind(newValue)
        }
        .alert(L.t("rerun_active_title", lang),
               isPresented: Binding(get: { pendingRerun != nil }, set: { if !$0 { pendingRerun = nil } })) {
            Button(L.t("rerun_action", lang), role: .destructive) {
                if let session = pendingRerun { performRerun(session) }
                pendingRerun = nil
            }
            Button(L.t("cancel", lang), role: .cancel) { pendingRerun = nil }
        } message: {
            Text(L.t("rerun_active_message", lang))
        }
        .alert(L.t("delete_active_title", lang),
               isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })) {
            Button(L.t("delete_action", lang), role: .destructive) {
                if let session = pendingDelete { performDelete(session) }
            }
            Button(L.t("cancel", lang), role: .cancel) { pendingDelete = nil }
        } message: {
            Text(L.t("delete_active_message", lang))
        }
        .confirmationDialog(L.t("clear_title", lang), isPresented: $confirmClear, titleVisibility: .visible) {
            Button(L.t("delete_action", lang), role: .destructive) { performClear() }
            Button(L.t("cancel", lang), role: .cancel) {}
        } message: {
            Text(L.t(clearMessageKey, lang))
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }

    // MARK: - History area

    /// Раскрытый блок на всю область или список мини-блоков.
    @ViewBuilder
    /// Блоки истории; раскрытый блок — в том же списке (раскрыт всегда только один).
    private var historyArea: some View {
        HistoryListView(
            lang: lang,
            selectedID: navigator.selectedID,
            expandedID: expandedID,
            terminalFor: { runner.terminal(for: $0) },
            onToggle: { session in
                if expandedID == session.id { collapse() } else { expand(session.id) }
            },
            onKill: { runner.stop(sessionID: $0.id) },
            onRerun: rerun,
            onCopy: copyOutput,
            onPin: { sessionStore.togglePin(id: $0.id) },
            onDelete: requestDelete,
            onPipeChange: { session, change in
                switch change {
                case .add(let command): runner.addPipeStage(sessionID: session.id, command: command)
                case .update(let index, let command):
                    runner.updatePipeStage(sessionID: session.id, index: index, command: command)
                case .remove(let index): runner.removePipeStage(sessionID: session.id, index: index)
                }
            }
        )
    }

    /// Колонка кнопок-иконок справа от истории; сюда же лягут будущие действия.
    private var actionsColumn: some View {
        VStack(spacing: 10) {
            sideButton("gearshape", help: L.t("settings", lang)) { showSettings = true }
            sideButton("trash", help: L.t("clear", lang)) {
                if sessionStore.clearScope != .nothing { confirmClear = true }
            }
            .disabled(sessionStore.clearScope == .nothing)
        }
        .frame(width: 32)
    }

    private func sideButton(_ systemName: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .frame(width: 32, height: 32)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    // MARK: - Actions

    private func navigateHistory(_ direction: HistoryDirection) -> String? {
        switch direction {
        case .older:
            let entries = sessionStore.filteredSessions.map {
                HistoryNavigator.Entry(id: $0.id, command: $0.command)
            }
            return navigator.older(entries: entries, current: text)
        case .newer:
            return navigator.newer()
        }
    }

    private var historyCommands: [String] {
        sessionStore.sessions.sorted { $0.createdAt > $1.createdAt }.map(\.command)
    }

    private var expandedSession: Session? {
        expandedID.flatMap { id in sessionStore.sessions.first { $0.id == id } }
    }

    private func run(_ command: String, directory: String? = nil) {
        runner.run(command: command, directory: directory)
        // интерактивная команда сразу открывается во встроенном терминале
        if let session = sessionStore.sessions.first, session.state == .interactive {
            expand(session.id)
        }
    }

    /// Повтор в том же блоке; работающую команду — только после подтверждения.
    private func rerun(_ session: Session) {
        if session.state.isActive {
            pendingRerun = session
        } else {
            performRerun(session)
        }
    }

    private func performRerun(_ session: Session) {
        runner.rerun(sessionID: session.id)
        // интерактивная команда сразу открывается во встроенном терминале
        if sessionStore.sessions.first(where: { $0.id == session.id })?.state == .interactive {
            expand(session.id)
        }
    }

    private func switchToLatinIfEnabled() {
        guard settings.latinLayoutInInput else { return }
        KeyboardLayoutSwitcher.shared.switchToLatin()
    }

    private func expand(_ id: UUID) {
        inputFocused = false
        expandedID = id
    }

    private func collapse() {
        guard expandedID != nil else { return }
        expandedID = nil
        interruptedID = nil
        inputFocused = true
    }

    /// Горячие клавиши панели. keyCode, а не символ: работают в любой раскладке.
    /// - ⌘W сворачивает раскрытый блок; сочетания с ⌘ не уходят в программу терминала.
    /// - ⌃C прерывает команду раскрытого блока (SIGINT), как в терминале.
    private func installKeyShortcuts() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if Self.arrowKeyCodes.contains(event.keyCode),
               modifiers.subtracting([.function, .numericPad]).isEmpty {
                return routeArrowToHistory(event) ? nil : event
            }
            switch (event.keyCode, modifiers) {
            case (13, .command) where expandedID != nil:
                collapse()
                return nil
            case (8, .control):
                return interruptByKeyboard(event) ? nil : event
            default:
                return event
            }
        }
    }

    /// ↓ и ↑ (keyCode 125, 126).
    private static let arrowKeyCodes: Set<UInt16> = [125, 126]
    /// Когда нажатие последний раз пересылалось в поле ввода: повтор не пересылаем снова,
    /// даже если поле фокус не получило, — иначе бесконечный круг.
    private static var lastArrowRepost = Date.distantPast

    /// Стрелки листают историю не только из поля ввода: если фокус не в текстовом поле,
    /// курсор ставится в поле ввода и туда же уходит нажатие. Не трогаем раскрытую работающую
    /// команду — стрелки нужны её терминалу (vim, меню, история шелла); диалоги и настройки тоже.
    private func routeArrowToHistory(_ event: NSEvent) -> Bool {
        // стрелки нужны живому терминалу раскрытой работающей команды
        if expandedSession?.state.isActive ?? false { return false }
        // только в самой панели: в списке папок, диалогах и настройках стрелки свои
        guard let window = event.window, window is LauncherPanel else { return false }
        if let editor = window.firstResponder as? NSTextView, editor.isFieldEditor { return false }
        guard Date().timeIntervalSince(Self.lastArrowRepost) > 0.3 else { return false }
        Self.lastArrowRepost = Date()
        inputFocused = true
        // нажатие повторяем, когда поле уже получило фокус: навигация — в поле ввода
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            NSApp.postEvent(event, atStart: true)
        }
        return true
    }

    /// ⌃C прерывает команду раскрытого блока. В живом терминале с фокусом
    /// ⌃C обрабатывает сам терминал (через tty).
    private func interruptByKeyboard(_ event: NSEvent) -> Bool {
        guard let session = expandedSession, session.state.isActive else { return false }
        // после остановки по ⌃C блок свернётся — и когда ⌃C отправил сам терминал
        interruptedID = session.id
        if let terminal = runner.terminal(for: session.id),
           event.window?.firstResponder === terminal.view {
            return false
        }
        runner.interrupt(sessionID: session.id)
        return true
    }

    private func requestDelete(_ session: Session) {
        if session.state.isActive {
            pendingDelete = session
        } else {
            sessionStore.remove(id: session.id)
        }
    }

    private func performDelete(_ session: Session) {
        if session.state.isActive {
            runner.stop(sessionID: session.id)
        }
        if expandedID == session.id { collapse() }
        sessionStore.remove(id: session.id)
    }

    private func performClear() {
        let targets = sessionStore.sessionsToClear
        let ids = Set(targets.map(\.id))
        if let expandedID, ids.contains(expandedID) { collapse() }
        targets.filter { $0.state.isActive }.forEach { runner.stop(sessionID: $0.id) }
        sessionStore.remove(ids: ids)
    }

    private var clearMessageKey: String {
        switch sessionStore.clearScope {
        case .finished(pinned: false), .nothing: return "clear_message_finished"
        case .active(pinned: false): return "clear_message_active"
        case .finished(pinned: true): return "clear_message_pinned_finished"
        case .active(pinned: true): return "clear_message_pinned_active"
        }
    }

    /// Без цвета; у работающей команды — весь экран, а не превью.
    private func copyOutput(_ session: Session) {
        let text = runner.terminal(for: session.id)?.snapshot().plain ?? session.output
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private var colorScheme: ColorScheme? {
        switch settings.theme {
        case .dark: return .dark
        case .light: return .light
        case .system, nil: return nil
        }
    }
}

/// Список сессий мини-блоками с экшн-кнопками.
struct HistoryListView: View {
    @Environment(SessionStore.self) private var sessionStore
    /// Высота содержимого: список занимает столько, сколько блоков, но не больше предела.
    @State private var contentHeight: CGFloat = 0
    /// Высоты блоков: свежему (верхнему) достаётся место, которое не заняли остальные.
    @State private var blockHeights: [UUID: CGFloat] = [:]

    let lang: String
    var selectedID: UUID?
    var expandedID: UUID?
    var terminalFor: (UUID) -> InteractiveTerminal? = { _ in nil }
    var onToggle: (Session) -> Void = { _ in }
    var onKill: (Session) -> Void = { _ in }
    var onRerun: (Session) -> Void = { _ in }
    var onCopy: (Session) -> Void = { _ in }
    var onPin: (Session) -> Void = { _ in }
    var onDelete: (Session) -> Void = { _ in }
    var onPipeChange: (Session, PipeChange) -> Void = { _, _ in }

    var body: some View {
        if sessionStore.filteredSessions.isEmpty {
            Text(L.t("history_empty", lang))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            ScrollViewReader { proxy in
              ScrollView {
                LazyVStack(spacing: LauncherMetrics.blockSpacing) {
                    ForEach(sessionStore.filteredSessions) { session in
                        SessionBlockView(session: session,
                                         lang: lang,
                                         isSelected: session.id == selectedID,
                                         isExpanded: session.id == expandedID,
                                         outputLines: session.id == sessionStore.filteredSessions.first?.id
                                            ? freshBlockLines : LauncherMetrics.compactOutputLines,
                                         terminal: session.id == expandedID ? terminalFor(session.id) : nil,
                                         onToggle: { onToggle(session) },
                                         onKill: { onKill(session) },
                                         onRerun: { onRerun(session) },
                                         onCopy: { onCopy(session) },
                                         onPin: { onPin(session) },
                                         onDelete: { onDelete(session) },
                                         onPipeChange: { onPipeChange(session, $0) },
                                         stageHistory: stageHistory)
                        .id(session.id)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { blockHeights[session.id] = $0 }
                    }
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
              }
              .frame(height: min(contentHeight, LauncherMetrics.historyMaxHeight))
              .onChange(of: selectedID) { _, id in
                  guard let id else { return }
                  withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
              }
              // раскрытый блок — к верху списка, дальше можно листать остальные
              .onChange(of: expandedID) { _, id in
                  guard let id else { return }
                  withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .top) }
              }
            }
        }
    }
}

extension HistoryListView {
    /// Уже применявшиеся шаги конвейера, свежие первыми, без повторов — для подсказок.
    private var stageHistory: [String] {
        var seen = Set<String>()
        return sessionStore.sessions
            .sorted { $0.createdAt > $1.createdAt }
            .flatMap(\.pipeline)
            .filter { seen.insert($0).inserted }
    }

    /// Сколько строк вывода показать свежему блоку: всё свободное место панели,
    /// которое не заняли остальные блоки, но не меньше обычного.
    private var freshBlockLines: Int {
        let sessions = sessionStore.filteredSessions
        let others = sessions.dropFirst().reduce(CGFloat(0)) { $0 + (blockHeights[$1.id] ?? 0) }
            + CGFloat(max(sessions.count - 1, 0)) * LauncherMetrics.blockSpacing
        let free = LauncherMetrics.historyMaxHeight - others - LauncherMetrics.blockChrome
        return max(LauncherMetrics.compactOutputLines, Int(free / LauncherMetrics.outputLineHeight))
    }
}

/// Мини-блок сессии. Клик раскрывает его на всю область истории,
/// клик по заголовку раскрытого — сворачивает.
struct SessionBlockView: View {
    let session: Session
    let lang: String
    var isSelected = false
    var isExpanded = false
    /// Сколько строк вывода показать в свёрнутом виде (включая строку «скрыто N»).
    var outputLines = LauncherMetrics.compactOutputLines
    @State private var showAllOutput = false
    /// Живой терминал интерактивной сессии — показывается в раскрытом блоке.
    var terminal: InteractiveTerminal?
    var onToggle: () -> Void = {}
    var onKill: () -> Void = {}
    var onRerun: () -> Void = {}
    var onCopy: () -> Void = {}
    var onPin: () -> Void = {}
    var onDelete: () -> Void = {}
    var onPipeChange: (PipeChange) -> Void = { _ in }
    /// Применявшиеся шаги конвейера (по всем блокам) — первые в подсказках.
    var stageHistory: [String] = []
    /// Какой шаг конвейера редактируется: индекс, `pipeline.count` — новый шаг, nil — никакой.
    @State private var editingStage: Int?
    @State private var stageDraft = ""
    @FocusState private var stageFieldFocused: Bool
    @State private var stageEngine = ShellCompletionEngine()
    @State private var stageCandidates: [String] = []
    @State private var stageSelected = 0
    /// Текст подставлен из варианта (TAB, клик) — варианты не пересчитываем.
    @State private var stageApplying = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header

            if editingStage != nil, !stageCandidates.isEmpty {
                stageSuggestionsRow
            }

            if isExpanded {
                expandedBody
            } else if !session.output.isEmpty {
                outputPreview
            }
        }
        .padding(LauncherMetrics.blockPadding)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: LauncherMetrics.innerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: LauncherMetrics.innerRadius)
                .strokeBorder(isSelected ? Color.accentColor : Color.white.opacity(0.18),
                              lineWidth: isSelected ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: LauncherMetrics.innerRadius))
        .onTapGesture { if !isExpanded { onToggle() } }
    }

    private var header: some View {
            HStack(spacing: 8) {
                if isExpanded {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Text(session.command)
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.tail)

                pipelineChips

                Spacer(minLength: 4)

                statusBadge

                if session.state.isTerminal {
                    let exit = session.exitCode.map { "exit \($0)" } ?? "exit —"
                    Text("\(exit) • \(session.output.count) симв.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                iconButton("arrow.clockwise.circle", help: L.t("rerun", lang), action: onRerun)
                iconButton("doc.on.doc", help: L.t("copy", lang), action: onCopy)
                iconButton(session.isPinned ? "pin.fill" : "pin", help: L.t("pin", lang), action: onPin)

                if session.state.isActive {
                    iconButton("xmark.circle.fill", color: .red, help: L.t("stop", lang), action: onKill)
                }

                iconButton("trash", help: L.t("delete", lang), action: onDelete)
            }
            .contentShape(Rectangle())
            // заголовок перехватывает клик у блока, поэтому сам переключает в обе стороны:
            // у свёрнутого блока без вывода, кроме заголовка, кликать не по чему
            .onTapGesture { onToggle() }
            .help(isExpanded ? L.t("collapse", lang) : "")
    }

    // MARK: - Конвейер по сохранённому выводу

    /// Шаги конвейера плашками `| grep foo ✕` и «+» для нового шага (только у завершённой команды).
    @ViewBuilder
    private var pipelineChips: some View {
        ForEach(Array(session.pipeline.enumerated()), id: \.offset) { index, stage in
            if editingStage == index {
                stageField
            } else {
                stageChip(stage, index: index)
            }
        }
        if editingStage == session.pipeline.count {
            stageField
        } else if session.state.isTerminal {
            Button {
                startEditing(at: session.pipeline.count, text: "")
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .frame(width: 18, height: 18)
                    .background(.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .help(L.t("add_pipe_stage", lang))
        }
    }

    private func stageChip(_ stage: String, index: Int) -> some View {
        HStack(spacing: 4) {
            Text("| " + stage)
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 180, alignment: .leading)
                .onTapGesture { startEditing(at: index, text: stage) }
                .help(L.t("edit_pipe_stage", lang))
            Button { onPipeChange(.remove(index)) } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(L.t("remove_pipe_stage", lang))
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.white.opacity(0.12), in: Capsule())
    }

    /// Поле шага: Enter — применить, Esc или пусто — отменить.
    private var stageField: some View {
        HStack(spacing: 2) {
            Text("|").font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
            TextField("grep …", text: $stageDraft)
                .textFieldStyle(.plain)
                .font(.system(size: 12, design: .monospaced))
                .frame(width: 160)
                .focused($stageFieldFocused)
                .onSubmit(commitStage)
                .onExitCommand { editingStage = nil }
                .onKeyPress(.tab) {
                    guard !stageCandidates.isEmpty else { return .ignored }
                    applyStageCandidate(stageCandidates[stageSelected % stageCandidates.count])
                    stageSelected += 1
                    return .handled
                }
                .onChange(of: stageDraft) { _, _ in
                    if stageApplying { stageApplying = false; return }
                    refreshStageCandidates()
                }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.white.opacity(0.18), in: Capsule())
    }

    private func startEditing(at index: Int, text: String) {
        setStageDraft(text) // текст ставим сами — варианты считаем ниже явно
        editingStage = index
        stageFieldFocused = true
        refreshStageCandidates()
    }

    /// Варианты: свои недавние шаги → частые фильтры → дополнения шелла
    /// (команды, алиасы, файлы — в директории, где выполнялась команда блока).
    private func refreshStageCandidates() {
        stageEngine.directory = session.directory
        let completions = stageEngine.completions(for: stageDraft)
            .map { stageEngine.applyCandidate(stageDraft, candidate: $0) }
        stageCandidates = PipeStageSuggestions.candidates(for: stageDraft, history: stageHistory,
                                                          completions: completions)
        stageSelected = 0
    }

    private func applyStageCandidate(_ candidate: String) {
        setStageDraft(candidate)
        stageFieldFocused = true
    }

    /// Текст поля без пересчёта вариантов (флаг сбросит onChange — только если текст изменился).
    private func setStageDraft(_ text: String) {
        guard text != stageDraft else { return }
        stageApplying = true
        stageDraft = text
    }

    /// Варианты плашками под заголовком: TAB перебирает, клик подставляет.
    private var stageSuggestionsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(stageCandidates.enumerated()), id: \.offset) { index, candidate in
                    let next = index == stageSelected % stageCandidates.count
                    Text(candidate)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(next ? Color.accentColor : Color.secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.white.opacity(next ? 0.16 : 0.08), in: Capsule())
                        .onTapGesture { applyStageCandidate(candidate) }
                }
            }
        }
    }

    private func commitStage() {
        guard let index = editingStage else { return }
        editingStage = nil
        let command = stageDraft.trimmingCharacters(in: .whitespaces)
        if index == session.pipeline.count {
            if !command.isEmpty { onPipeChange(.add(command)) }
        } else if command.isEmpty {
            onPipeChange(.remove(index))
        } else if command != session.pipeline[index] {
            onPipeChange(.update(index, command))
        }
    }

    /// Раскрытый блок: живой терминал, пока программа работает, иначе полный вывод.
    @ViewBuilder
    private var expandedBody: some View {
        // пока команда работает — живой терминал (можно отвечать на вопросы, жать ⌃C)
        if let terminal, session.state.isActive {
            TerminalHostView(terminal: terminal)
                .id(ObjectIdentifier(terminal)) // после перезапуска — новый терминал
                .frame(maxWidth: .infinity)
                .frame(height: LauncherMetrics.terminalHeight)
                .clipShape(RoundedRectangle(cornerRadius: LauncherMetrics.terminalRadius))
        } else {
            // по высоте текста: список прокручивается дальше, к остальным блокам
            fullOutput
                .textSelection(.enabled)
        }
    }

    /// Вывод с цветом, как в терминале; `lines` — сколько строк разбирать (превью).
    /// Весь вывод; очень длинный — первые `fullOutputLimit` строк и кнопка «показать всё»
    /// (тысячи строк в одном тексте тормозят прокрутку).
    private var fullOutput: some View {
        let source = session.outputANSI ?? session.output
        let lines = source.components(separatedBy: "\n")
        let limited = !showAllOutput && lines.count > LauncherMetrics.fullOutputLimit
        let shown = limited ? lines.prefix(LauncherMetrics.fullOutputLimit).joined(separator: "\n") : source
        return VStack(alignment: .leading, spacing: 6) {
            Text(session.outputANSI == nil ? AttributedString(shown) : ANSIText.attributed(shown))
                .font(.system(size: LauncherMetrics.outputFontSize, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
            if limited {
                Button(String(format: L.t("show_all_lines", lang), lines.count)) { showAllOutput = true }
                    .buttonStyle(.plain)
                    .font(.system(size: LauncherMetrics.outputFontSize, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
        }
    }

    /// Свёрнутый вывод: начало, «скрыто N строк» с кнопкой раскрыть, конец.
    private var outputPreview: some View {
        let source = session.outputANSI ?? session.output
        let layout = OutputPreview.layout(lines: source.components(separatedBy: "\n"),
                                          gap: session.outputGap, maxLines: outputLines)
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(layout.head.enumerated()), id: \.offset) { outputLine($0.element) }
            if layout.hidden > 0 { hiddenLinesMarker(layout.hidden) }
            ForEach(Array(layout.tail.enumerated()), id: \.offset) { outputLine($0.element) }
        }
    }

    /// Одна строка вывода фиксированной высоты: длинная обрезается (целиком — в раскрытом блоке).
    private func outputLine(_ line: String) -> some View {
        Text(session.outputANSI == nil ? AttributedString(line) : ANSIText.attributed(line))
            .font(.system(size: LauncherMetrics.outputFontSize, design: .monospaced))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, minHeight: LauncherMetrics.outputLineHeight,
                   maxHeight: LauncherMetrics.outputLineHeight, alignment: .leading)
    }

    private func hiddenLinesMarker(_ count: Int) -> some View {
        HStack(spacing: 8) {
            Text("⋯  " + String(format: L.t("hidden_lines", lang), count))
                .foregroundStyle(.secondary)
            Button(L.t("expand", lang), action: onToggle)
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
        }
        .font(.system(size: LauncherMetrics.outputFontSize, weight: .medium))
        .frame(maxWidth: .infinity, minHeight: LauncherMetrics.outputLineHeight,
               maxHeight: LauncherMetrics.outputLineHeight, alignment: .leading)
    }

    private func iconButton(_ systemName: String,
                            color: Color = .primary,
                            help: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13))
                .foregroundStyle(color)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var statusBadge: some View {
        let label: String
        let color: Color
        switch session.state {
        case .running:
            label = L.t("active", lang); color = .green
        case .interactive:
            label = L.t("interactive", lang); color = .orange
        case .completed:
            label = L.t("completed", lang); color = .secondary
        case .stopped:
            label = L.t("stopped", lang); color = .red
        case .interrupted:
            label = L.t("interrupted", lang); color = .orange
        }
        return Text(label)
            .font(.caption2)
            .foregroundStyle(color)
    }
}

/// Поле ввода команды: стекло, призрак-превью, мульти-кандидаты с TAB-циклированием.
/// Направление шага по истории из поля ввода.
enum HistoryDirection {
    case older
    case newer
}

struct CommandInputView: View {
    @Binding var text: String
    /// Текущая директория лаунчера: от неё дополняются относительные пути.
    var directory: String
    var onSubmit: (String) -> Void
    /// Шаг по истории стрелкой: текст для поля или nil, если шагать некуда.
    var onHistory: (HistoryDirection) -> String? = { _ in nil }
    /// Пользователь сам поменял текст — навигация по истории сбрасывается.
    var onEdit: () -> Void = {}
    /// Команды из истории, от новых к старым: источник серой подсказки.
    var history: [String] = []
    @State private var engine = ShellCompletionEngine()
    /// Серая подсказка из истории (как zsh-autosuggestions): принимается стрелкой →.
    @State private var historyCompletion: String?
    @State private var typedWidth: CGFloat = 0
    /// Варианты дополнения и текст, для которого они посчитаны.
    @State private var candidates: [String] = []
    @State private var candidatesText: String?
    /// TAB как в zsh: общая часть, затем перебор вариантов.
    @State private var completer = TabCompleter()
    /// Текст ставим сами (перебор, история) — не считать это вводом пользователя.
    @State private var settingText = false

    private var font: Font { .system(size: 20, weight: .medium) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            inputField

            if let menu = completer.menu {
                candidatesDropdown(menu)
            }
        }
    }

    private var inputField: some View {
        ZStack(alignment: .leading) {
            if !text.isEmpty {
                Text(text)
                    .font(font)
                    .opacity(0)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(key: TypedWidthKey.self, value: geo.size.width)
                        }
                    )
                    .onPreferenceChange(TypedWidthKey.self) { typedWidth = $0 }
            }

            if let ghost = historyGhost {
                Text(ghost)
                    .font(font)
                    .foregroundStyle(.tertiary)
                    .offset(x: typedWidth)
                    .allowsHitTesting(false)
            }

            TextField("Введите команду…", text: $text)
                .textFieldStyle(.plain)
                .font(font)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: LauncherMetrics.innerRadius))
        .overlay(
            RoundedRectangle(cornerRadius: LauncherMetrics.innerRadius)
                .strokeBorder(.white.opacity(0.28))
        )
        // Shift+TAB приходит как «backtab» (U+0019)
        .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")]) { press in
            let backward = press.modifiers.contains(.shift) || press.key == KeyEquivalent("\u{19}")
            return tab(backward ? .backward : .forward)
        }
        .onKeyPress(.rightArrow) { acceptHistory() }
        .onKeyPress(.downArrow) { stepHistory(.older) }
        .onKeyPress(.upArrow) { stepHistory(.newer) }
        .onExitCommand { cancelCompletion() }
        .onSubmit { onSubmit(text) }
        .onChange(of: text) { _, newValue in
            if settingText { settingText = false; return }
            // пользователь печатает: выбранный вариант принят, перебор окончен
            completer.reset()
            onEdit()
            refresh(newValue)
        }
    }

    /// Остаток подсказки из истории после набранного.
    private var historyGhost: String? {
        guard completer.menu == nil, let completion = historyCompletion,
              completion.hasPrefix(text), completion.count > text.count else { return nil }
        return String(completion.dropFirst(text.count))
    }

    private func candidatesDropdown(_ menu: TabCompleter.Menu) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(menu.candidates.enumerated()), id: \.offset) { index, candidate in
                        let selected = index == menu.index
                        Text(candidate)
                            .font(.system(size: 13, weight: selected ? .semibold : .regular, design: .monospaced))
                            .foregroundStyle(selected ? Color.accentColor : Color.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selected ? Color.accentColor.opacity(0.15) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                            .id(index)
                            .onTapGesture {
                                // клик — принять вариант и искать дальше (как после единственного варианта)
                                completer.reset()
                                text = engine.applyCandidate(menu.original, candidate: candidate)
                            }
                    }
                }
                .padding(4)
            }
            .onChange(of: menu.index) { _, index in
                if let index { proxy.scrollTo(index) }
            }
        }
        .frame(maxHeight: 140)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.15))
        )
    }

    // MARK: - TAB

    private func tab(_ direction: TabCompleter.Direction) -> KeyPress.Result {
        // текст мог прийти не с клавиатуры (стрелки по истории) — варианты считаем для него
        if completer.menu == nil, candidatesText != text { refresh(text) }
        guard let newText = completer.press(direction, text: text, candidates: candidates,
                                            apply: engine.applyCandidate) else { return .ignored }
        guard newText != text else { return .handled } // список показан, вставим следующим TAB
        if completer.menu != nil {
            // перебор: текст меняется, но это не ввод — варианты и перебор сохраняются
            settingText = true
            text = newText
        } else {
            // один вариант или общая часть: как ввод — сразу считаем варианты дальше
            text = newText
        }
        return .handled
    }

    /// Esc во время перебора — вернуть набранное.
    private func cancelCompletion() {
        guard let original = completer.cancel(), original != text else { return }
        settingText = true
        text = original
    }

    // MARK: - История

    private func stepHistory(_ direction: HistoryDirection) -> KeyPress.Result {
        guard let command = onHistory(direction) else { return .ignored }
        completer.reset()
        historyCompletion = nil
        if command != text {
            settingText = true
            text = command
        }
        return .handled
    }

    /// → принимает серую подсказку из истории; без подсказки — обычное движение курсора.
    private func acceptHistory() -> KeyPress.Result {
        guard let completion = historyCompletion, historyGhost != nil else { return .ignored }
        historyCompletion = nil
        text = completion
        return .handled
    }

    /// Варианты дополнения и подсказка из истории для текущего текста.
    private func refresh(_ value: String) {
        engine.directory = directory
        candidates = engine.completions(for: value)
        candidatesText = value
        historyCompletion = HistorySuggestion.completion(for: value, in: history)
    }
}

private struct TypedWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Встраивает NSView терминала сессии. Одна и та же вью переезжает между раскрытиями,
/// поэтому экран программы сохраняется, пока блок свёрнут.
struct TerminalHostView: NSViewRepresentable {
    let terminal: InteractiveTerminal

    func makeNSView(context: Context) -> NSView {
        let terminalView = terminal.view
        let container = NSView(frame: terminalView.frame)
        terminalView.removeFromSuperview()
        terminalView.frame = container.bounds
        terminalView.autoresizingMask = [.width, .height]
        container.addSubview(terminalView)
        DispatchQueue.main.async {
            terminalView.window?.makeFirstResponder(terminalView)
        }
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Изменение конвейера по сохранённому выводу.
enum PipeChange {
    case add(String)
    case update(Int, String)
    case remove(Int)
}

/// Тень панели по её скруглённой форме и только снаружи: внутри вырезана, чтобы не темнить стекло.
private struct PanelShadow: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: LauncherMetrics.panelRadius)
        shape
            .fill(Color.black)
            .shadow(color: .black.opacity(0.35), radius: 16, y: 6)
            .mask {
                ZStack {
                    Rectangle().padding(-LauncherMetrics.shadowMargin)
                    shape.blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}
