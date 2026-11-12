import SwiftUI
import AppKit

/// Геометрия панели. Скругления концентричны: внешний радиус = внутренний + отступ между ними,
/// иначе зазор в углах выходит шире, чем по краям.
enum LauncherMetrics {
    /// Отступ контента от края панели.
    static let padding: CGFloat = 8
    /// Радиус поля ввода и блоков истории.
    static let innerRadius: CGFloat = 11
    static let panelRadius = innerRadius + padding
    /// Отступ содержимого внутри блока истории.
    static let blockPadding: CGFloat = 12
    /// Кнопки-колпачки одного размера с соседями: в заголовке блока («+» и действия) и в поле ввода.
    static let blockButton: CGFloat = 24
    /// «Развернуть» в строке «скрыто N»: колпачок как в макете, строка под него выше обычной.
    static let markerButtonHeight: CGFloat = 18
    static let markerRowHeight: CGFloat = 24
    static let inputButton: CGFloat = 28
    static func buttonRadius(_ size: CGFloat) -> CGFloat { (size * 0.29).rounded() }
    /// Запас окна вокруг панели под её тень.
    static let shadowMargin: CGFloat = 24
    static let outputFontSize: CGFloat = 10
    /// Ширина символа моноширинного шрифта вывода: сколько символов влезает в строку превью.
    static let outputCharWidth: CGFloat = ("M" as NSString).size(withAttributes: [
        .font: NSFont.monospacedSystemFont(ofSize: outputFontSize, weight: .regular)]).width
    /// Высота строки вывода: блок считает, сколько строк влезает в свободное место.
    static let outputLineHeight: CGFloat = ceil(NSLayoutManager().defaultLineHeight(
        for: NSFont.monospacedSystemFont(ofSize: outputFontSize, weight: .regular)))
    /// Всё в блоке, кроме строк вывода: отступы, заголовок, промежуток до вывода.
    static let blockChrome: CGFloat = blockPadding * 2 + 36 + 8
    static let blockSpacing: CGFloat = 8
    /// Живой терминал в раскрытом блоке: блок занимает всю видимую область истории.
    static func terminalHeight(historyHeight: CGFloat) -> CGFloat { historyHeight - blockChrome }
}

/// Корневое представление лаунчера: ввод, история, экшн-кнопки.
struct LauncherRootView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(ProcessRunner.self) private var runner
    @Environment(SettingsStore.self) private var settings
    @Environment(HotKeyController.self) private var hotKeys

    @State private var text = ""
    /// Режим поиска (⌘F): то же поле ввода ищет по истории; набранная команда ждёт в `text`.
    @State private var searchMode = false
    @State private var searchQuery = ""
    /// ⌘P (или сочетание из настроек): дерево папок у текущей папки; счётчик — каждое нажатие.
    @State private var folderTreeRequest = 0
    /// Список «Избранное» (кнопка ★, ⌘E).
    @State private var favoritesOpen = false
    /// Сообщение внизу панели («Удалено…», «В избранном…»), с «Отменить», если можно.
    @State private var toast: PanelToast?
    @FocusState private var inputFocused: Bool
    /// Видимая высота истории — от неё тянется нижний край (предел мог быть больше содержимого).
    @State private var historyVisibleHeight: CGFloat = 0
    /// Размер и запас до края экрана в начале перетаскивания края панели.
    @State private var resizeStart: (size: CGSize, room: CGSize)?
    @State private var pendingDelete: Session?
    /// Перезапуск работающей команды ждёт подтверждения.
    @State private var pendingRerun: Session?
    @State private var confirmClear = false
    @State private var showSettings = false
    @State private var navigator = HistoryNavigator()
    /// Раскрытый на всю область истории блок (интерактивный терминал или полный вывод).
    @State private var expandedID: UUID?
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?
    /// Рамки раскрытого блока и полосы прокрутки: клик вне блока его сворачивает.
    @State private var frames = PanelFrames()
    /// Сессия, прерванная ⌃C из раскрытого блока: после остановки блок сворачивается.
    @State private var interruptedID: UUID?

    private var lang: String { settings.languageCode }

    var body: some View {
        // Высота панели — по содержимому (до предела истории); окно следует за ней.
        // Настройки выезжают сверху, как лист окна macOS; панель за ними темнеет.
        attachLifecycle(ZStack(alignment: .top) {
            panelContent
                .brightness(showSettings ? -0.35 : 0)
                .allowsHitTesting(!showSettings)
            if showSettings {
                SettingsView(onClose: closeSettings)
                    .padding(.top, 2)
                    .transition(.settingsLayer)
                    .zIndex(1)
            }
        }
        .padding(LauncherMetrics.padding)
        .frame(width: settings.panelWidth)
        // лист выезжает из-за верхнего края панели, а не поверх окна
        .clipShape(RoundedRectangle(cornerRadius: LauncherMetrics.panelRadius))
        // правый и нижний края и угол между ними тянутся: ширина и предел высоты истории
        .overlay { resizeHandles }
        .background {
            // сплошное окно, без стекла и прозрачности
            let shape = RoundedRectangle(cornerRadius: LauncherMetrics.panelRadius)
            shape.fill(Tactile.window)
                .overlay(shape.strokeBorder(Tactile.windowEdge))
                // за пустые места панели (поля, промежутки) окно перетаскивается
                .overlay { WindowDragArea() }
        }
        .background { PanelShadow() }
        // прозрачный запас окна под тень: иначе её обрезает край окна
        .padding(LauncherMetrics.shadowMargin)
        .preferredColorScheme(colorScheme))
    }

    private var panelContent: some View {
        VStack(spacing: LauncherMetrics.padding) {
            // где мы сейчас: светлые «крошки» над полем, обновляются при cd
            DirectoryBreadcrumbsView(path: settings.currentDirectory,
                                     recent: settings.recentDirectories,
                                     favorites: settings.favoriteDirectories,
                                     lang: lang,
                                     onNavigate: { settings.currentDirectory = $0 },
                                     onToggleFavorite: toggleFavoriteDirectory,
                                     treeRequest: folderTreeRequest)
                .padding(.horizontal, 14) // по левому краю текста в поле ввода
                .padding(.bottom, -4)     // ближе к полю, чем к краю панели

            CommandInputView(text: searchMode ? $searchQuery : $text,
                             directory: settings.currentDirectory,
                             mode: searchMode ? .search : .command,
                             lang: lang,
                             onSubmit: { command in
                                 if searchMode { openFound(); return }
                                 navigator.reset()
                                 run(command)
                                 text = ""
                             },
                             onHistory: navigateHistory,
                             onEdit: {
                                 navigator.reset()
                                 // фильтрует историю только поиск; набор команды список не трогает
                                 if searchMode { sessionStore.filterText = searchQuery.trimmingCharacters(in: .whitespaces) }
                             },
                             onExitSearch: exitSearch,
                             history: historyCommands,
                             isFocused: inputFocused,
                             trailing: AnyView(inputButtons))
            .focused($inputFocused)

            historyArea
                .frame(maxWidth: .infinity, alignment: .top)
                .onGeometryChange(for: CGFloat.self) { $0.size.height.rounded() } action: {
                    historyVisibleHeight = $0
                }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                PanelToastView(toast: toast, lang: lang, onUndo: { undoToast(toast) })
                    .id(toast.id)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: toast)
    }

    /// Жизненный цикл, горячие клавиши и диалоги панели — отдельно от раскладки.
    private func attachLifecycle<V: View>(_ content: V) -> some View {
        content
        .onAppear {
            inputFocused = true
            NotificationService().requestPermission()
            installKeyShortcuts()
        }
        .onDisappear {
            keyMonitor.map(NSEvent.removeMonitor)
            keyMonitor = nil
            mouseMonitor.map(NSEvent.removeMonitor)
            mouseMonitor = nil
        }
        // Выход из vim/top и т.п. или остановка по ⌃C — блок сворачивается до заголовка.
        // Обычная команда, завершившаяся сама, остаётся раскрытой: её вывод могут читать.
        .onChange(of: expandedSession?.state) { old, new in
            guard old?.isActive ?? false, new?.isTerminal ?? true else { return }
            if old == .interactive || expandedID == interruptedID { collapse() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hatchDidShow)) { _ in
            // панель открывается заново — в обычном режиме, с набранной командой
            if searchMode { exitSearch() }
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
    }

    // MARK: - Настройки и кнопки панели

    /// Настройки и очистка истории — справа в поле ввода, а не отдельной колонкой.
    private var inputButtons: some View {
        HStack(spacing: 6) {
            GlassIconButton(icon: favoritesOpen ? .starOn : .star, color: favoritesOpen ? Tactile.star : nil,
                            size: LauncherMetrics.inputButton, help: L.t("favorites", lang)) { favoritesOpen.toggle() }
                // своё всплывающее окно, сплошное: системное в macOS 26 стеклянное
                .hatchPopup(isPresented: $favoritesOpen) { _ in
                    PopupCard {
                    FavoritesView(directories: settings.favoriteDirectories,
                                  commands: settings.favoriteCommands,
                                  currentDirectory: settings.currentDirectory,
                                  lang: lang,
                                  onGo: { path in
                                      favoritesOpen = false
                                      if !settings.navigate(to: path) { NSSound.beep() }
                                      inputFocused = true
                                  },
                                  onRun: { command in
                                      favoritesOpen = false
                                      exitSearch()
                                      run(command)
                                  },
                                  onRemoveDirectory: { settings.toggleFavoriteDirectory($0) },
                                  onRemoveCommand: { settings.toggleFavoriteCommand($0) })
                    }
                }
            GlassIconButton(icon: .gear, size: LauncherMetrics.inputButton, help: L.t("settings", lang)) { openSettings() }
            GlassIconButton(icon: .trash, size: LauncherMetrics.inputButton, help: L.t("clear", lang)) {
                if sessionStore.clearScope != .nothing { confirmClear = true }
            }
            .disabled(sessionStore.clearScope == .nothing)
        }
    }

    private func openSettings() {
        inputFocused = false
        withAnimation(LayersDepth.spring) { showSettings = true }
    }

    private func closeSettings() {
        withAnimation(LayersDepth.spring) { showSettings = false }
        inputFocused = true
    }

    // MARK: - Размер панели

    private var resizeHandles: some View {
        let thickness: CGFloat = 6
        // угол скруглён: у самого края стекла нет, там клик уходит сквозь окно — зона глубже внутрь
        let corner: CGFloat = 24
        return ZStack {
            handle(.right).frame(width: thickness).padding(.bottom, corner)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            handle(.bottom).frame(height: thickness).padding(.trailing, corner)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            handle([.right, .bottom]).frame(width: corner, height: corner)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    private func handle(_ edges: ResizeEdges) -> some View {
        PanelResizeHandle(edges: edges,
                          onBegin: beginResize,
                          onDrag: { delta in
                              guard let start = resizeStart else { return }
                              let size = PanelSize.resized(start: start.size, by: delta, room: start.room, edges: edges)
                              if size.width != settings.panelWidth { settings.panelWidth = size.width }
                              if edges.contains(.bottom), size.height != settings.historyMaxHeight {
                                  settings.historyMaxHeight = size.height
                              }
                          },
                          onEnd: { resizeStart = nil })
    }

    /// Запоминаем размер и сколько места до края экрана: панель не вылезает за него.
    private func beginResize(_ window: NSWindow?) {
        // нижний край тянется от видимой высоты: предел мог быть больше, чем занято сейчас
        let height = min(settings.historyMaxHeight, max(historyVisibleHeight, PanelSize.historyHeightRange.lowerBound))
        var room = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        if let window, let visible = window.screen?.visibleFrame {
            let margin = LauncherMetrics.shadowMargin
            room = CGSize(width: visible.maxX - (window.frame.maxX - margin),
                          height: (window.frame.minY + margin) - visible.minY)
        }
        resizeStart = (CGSize(width: settings.panelWidth, height: height), room)
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
            compactLines: settings.previewLines,
            maxHeight: settings.historyMaxHeight,
            frames: frames,
            terminalFor: { runner.terminal(for: $0) },
            onToggle: { session in
                if expandedID == session.id { collapse() } else { expand(session.id) }
            },
            onKill: { runner.stop(sessionID: $0.id) },
            onRerun: rerun,
            onCopy: copyOutput,
            onPin: { sessionStore.togglePin(id: $0.id) },
            onFavorite: toggleFavoriteCommand,
            favoriteCommands: Set(settings.favoriteCommands),
            onDelete: requestDelete,
            onOpenDirectory: { directory in
                // как cd: дальше команды идут в этой папке; удалённая папка — звук, путь не меняем
                if !settings.navigate(to: directory) { NSSound.beep() }
                inputFocused = true
            },
            onPipeChange: { session, change in
                switch change {
                case .add(let command): runner.addPipeStage(sessionID: session.id, command: command)
                case .update(let index, let command):
                    runner.updatePipeStage(sessionID: session.id, index: index, command: command)
                case .remove(let index): runner.removePipeStage(sessionID: session.id, index: index)
                }
            },
            // шаг применили Enter-ом или отменили Esc у свёрнутого блока — печатать дальше в поле ввода
            onStageEditEnded: { if expandedID == nil { inputFocused = true } }
        )
    }

    // MARK: - Actions

    private func navigateHistory(_ direction: HistoryDirection) -> String? {
        let current = searchMode ? searchQuery : text
        let step: String?
        switch direction {
        case .older:
            let entries = sessionStore.filteredSessions.map {
                HistoryNavigator.Entry(id: $0.id, command: $0.command)
            }
            step = navigator.older(entries: entries, current: current)
        case .newer:
            step = navigator.newer()
        }
        // в поиске стрелки переходят по найденным блокам, а запрос остаётся
        return searchMode ? step.map { _ in searchQuery } : step
    }

    // MARK: - Очистка, избранное, сообщения

    /// `clear` и ⌃L: завершённые блоки убираются сразу, без вопроса; работающие и закреплённые
    /// остаются. 5 секунд можно вернуть всё «Отменить».
    private func quickClear() {
        let removed = sessionStore.sessions.filter { $0.state.isTerminal && !$0.isPinned }
        guard !removed.isEmpty else {
            showToast(L.t("clear_nothing", lang))
            return
        }
        if let expandedID, removed.contains(where: { $0.id == expandedID }) { collapse() }
        navigator.reset()
        withAnimation(LayersDepth.spring) { _ = sessionStore.clearFinished() }
        showToast(String(format: L.t("cleared", lang), removed.count)) {
            withAnimation(LayersDepth.spring) { sessionStore.restore(removed) }
        }
    }

    /// ⌘D и меню пути: папка в избранное или обратно.
    private func toggleFavoriteDirectory(_ path: String) {
        let added = settings.toggleFavoriteDirectory(path)
        showToast(added ? String(format: L.t("fav_dir_added", lang), PathBreadcrumbs.folderName(for: path))
                        : L.t("fav_dir_removed", lang))
    }

    /// ★ в кнопках блока: команда в избранное или обратно.
    private func toggleFavoriteCommand(_ session: Session) {
        let added = settings.toggleFavoriteCommand(session.command)
        showToast(added ? String(format: L.t("fav_cmd_added", lang), session.command) : L.t("fav_cmd_removed", lang))
    }

    private func showToast(_ text: String, undo: (() -> Void)? = nil) {
        let next = PanelToast(text: text, undo: undo)
        toast = next
        DispatchQueue.main.asyncAfter(deadline: .now() + PanelToast.duration) {
            if toast == next { toast = nil }
        }
    }

    private func undoToast(_ shown: PanelToast) {
        shown.undo?()
        if toast == shown { toast = nil }
    }

    // MARK: - Поиск

    /// ⌘F: поле ввода становится поиском по командам и выводу; повторно — обратно к команде.
    private func toggleSearch() {
        if searchMode { exitSearch(); return }
        navigator.reset()
        searchQuery = ""
        sessionStore.filterText = ""
        withAnimation(.easeOut(duration: 0.2)) { searchMode = true }
        inputFocused = true
    }

    /// Выход из поиска (Esc, ⌘F, «✕» на метке): история целиком, набранная команда на месте.
    /// Раскрытый из поиска блок остаётся раскрытым, и фокус — у него: поле ввода в фокусе
    /// и раскрытый блок вместе не бывают (клик в поле блок сворачивает).
    private func exitSearch() {
        guard searchMode else { return }
        navigator.reset()
        searchQuery = ""
        sessionStore.filterText = ""
        withAnimation(.easeOut(duration: 0.2)) { searchMode = false }
        if expandedID == nil { inputFocused = true }
    }

    /// Enter в поиске раскрывает выбранный стрелками блок, а без выбора — первый найденный.
    private func openFound() {
        guard let id = navigator.selectedID ?? sessionStore.filteredSessions.first?.id else {
            NSSound.beep()
            return
        }
        expand(id)
    }

    private var historyCommands: [String] {
        sessionStore.sessions.sorted { $0.createdAt > $1.createdAt }.map(\.command)
    }

    private var expandedSession: Session? {
        expandedID.flatMap { id in sessionStore.sessions.first { $0.id == id } }
    }

    private func run(_ command: String, directory: String? = nil) {
        // `clear` в Hatch — убрать завершённые блоки, а не очистить экран шелла
        if command.trimmingCharacters(in: .whitespacesAndNewlines) == "clear" {
            quickClear()
            return
        }
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
        withAnimation(LayersDepth.spring) { expandedID = id }
    }

    private func collapse() {
        guard expandedID != nil else { return }
        frames.expanded = .null
        withAnimation(LayersDepth.spring) { expandedID = nil }
        interruptedID = nil
        inputFocused = true
    }

    /// Горячие клавиши панели. keyCode, а не символ: работают в любой раскладке.
    /// - ⌘W сворачивает раскрытый блок; сочетания с ⌘ не уходят в программу терминала.
    /// - ⌃C прерывает команду раскрытого блока (SIGINT), как в терминале.
    private func installKeyShortcuts() {
        guard keyMonitor == nil else { return }
        // клик в панели вне раскрытого блока сворачивает его; нажатие идёт дальше как обычно
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            if expandedID != nil, !showSettings, shouldCollapse(on: event) { collapse() }
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if Self.arrowKeyCodes.contains(event.keyCode),
               modifiers.subtracting([.function, .numericPad]).isEmpty {
                return routeArrowToHistory(event) ? nil : event
            }
            // дерево папок — сочетание из настроек (по умолчанию ⌘P), пока открыта панель
            if !showSettings,
               KeyChordFormatter.matches(settings.folderTreeShortcut, modifiers: modifiers, keyCode: event.keyCode,
                                         characters: event.charactersIgnoringModifiers) {
                favoritesOpen = false
                folderTreeRequest += 1
                return nil
            }
            switch (event.keyCode, modifiers) {
            case (53, []) where showSettings && !HotKeyCapsField.isRecording:
                closeSettings()
                return nil
            case (53, []) where searchMode && !showSettings && event.window is LauncherPanel:
                exitSearch()
                return nil
            case (14, .command) where !showSettings:
                // ⌘E в раскрытом выводе — «искать выделенное», его не трогаем
                if Self.textViewHasFocus(event) { return event }
                favoritesOpen.toggle()
                return nil
            case (2, .command) where !showSettings:
                toggleFavoriteDirectory(settings.currentDirectory)
                return nil
            case (37, .control) where !showSettings:
                // в живом терминале ⌃L — очистка его экрана
                if let session = expandedSession, let terminal = runner.terminal(for: session.id),
                   event.window?.firstResponder === terminal.view {
                    return event
                }
                quickClear()
                return nil
            case (12, .command):
                // без значка в строке меню ⌘Q в панели — способ выйти
                NSApp.terminate(nil)
                return nil
            case (3, .command) where !showSettings:
                // в раскрытом выводе и живом терминале ⌘F — их собственный поиск
                if Self.textViewHasFocus(event) { return event }
                if let session = expandedSession, let terminal = runner.terminal(for: session.id),
                   event.window?.firstResponder === terminal.view {
                    return event
                }
                toggleSearch()
                return nil
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

    /// Клик в самой панели, но не по раскрытому блоку, полосе прокрутки или краю для изменения размера.
    private func shouldCollapse(on event: NSEvent) -> Bool {
        guard let window = event.window, window is LauncherPanel,
              let content = window.contentView, let frame = content.superview else { return false }
        if frame.hitTest(frame.convert(event.locationInWindow, from: nil)) is PanelResizeHandle.HandleView { return false }
        return PanelFrames.collapses(at: content.convert(event.locationInWindow, from: nil),
                                     expanded: frames.expanded, scrollbar: frames.scrollbar)
    }

    /// Фокус в тексте вывода раскрытого блока (не в поле ввода): там свои ⌘F и ⌘E.
    private static func textViewHasFocus(_ event: NSEvent) -> Bool {
        guard let responder = event.window?.firstResponder as? NSTextView else { return false }
        return !responder.isFieldEditor
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
        if showSettings { return false }
        // только в самой панели: в списке папок, диалогах и настройках стрелки свои
        guard let window = event.window, window is LauncherPanel else { return false }
        // фокус в тексте (поле ввода, вывод с выделением) — стрелки его
        if window.firstResponder is NSTextView { return false }
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
    /// Положение прокрутки — для стеклянной полосы и затухания краёв.
    @State private var metrics = ScrollMetrics()

    let lang: String
    var selectedID: UUID?
    var expandedID: UUID?
    /// Экранных строк вывода в свёрнутом блоке (настройка «Строк в превью»); свежий берёт больше.
    var compactLines = SettingsStore.defaultPreviewLines
    /// Предел высоты истории: дальше прокрутка. Раскрытый терминал занимает его целиком.
    var maxHeight: CGFloat = PanelSize.defaultHistoryHeight
    /// Куда записывать рамки раскрытого блока и полосы прокрутки (клик вне блока его сворачивает).
    var frames: PanelFrames?
    var terminalFor: (UUID) -> InteractiveTerminal? = { _ in nil }
    var onToggle: (Session) -> Void = { _ in }
    var onKill: (Session) -> Void = { _ in }
    var onRerun: (Session) -> Void = { _ in }
    var onCopy: (Session) -> Void = { _ in }
    var onPin: (Session) -> Void = { _ in }
    /// ★ в кнопках блока: команда в избранное; какие уже там — звезда закрашена.
    var onFavorite: (Session) -> Void = { _ in }
    var favoriteCommands: Set<String> = []
    var onDelete: (Session) -> Void = { _ in }
    var onOpenDirectory: (String) -> Void = { _ in }
    var onPipeChange: (Session, PipeChange) -> Void = { _, _ in }
    var onStageEditEnded: () -> Void = {}

    var body: some View {
        if sessionStore.filteredSessions.isEmpty {
            Text(L.t(sessionStore.filterText.isEmpty ? "history_empty" : "search_empty", lang))
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            let sessions = sessionStore.filteredSessions
            ScrollViewReader { proxy in
              ScrollView {
                // не Lazy: ленивый список держал старую оценку высоты свёрнутого блока,
                // и панель не уменьшалась обратно; блоков не больше лимита истории
                VStack(spacing: LauncherMetrics.blockSpacing) {
                    ForEach(sessions) { session in
                        SessionBlockView(session: session,
                                         lang: lang,
                                         isSelected: session.id == selectedID,
                                         isExpanded: session.id == expandedID,
                                         dimmed: expandedID != nil && session.id != expandedID,
                                         outputLines: session.id == sessions.first?.id
                                            ? freshBlockLines : compactLines,
                                         terminal: session.id == expandedID ? terminalFor(session.id) : nil,
                                         terminalHeight: LauncherMetrics.terminalHeight(historyHeight: maxHeight),
                                         onToggle: { onToggle(session) },
                                         onKill: { onKill(session) },
                                         onRerun: { onRerun(session) },
                                         onCopy: { onCopy(session) },
                                         onPin: { onPin(session) },
                                         isFavorite: favoriteCommands.contains(session.command.trimmingCharacters(in: .whitespacesAndNewlines)),
                                         onFavorite: { onFavorite(session) },
                                         onDelete: { onDelete(session) },
                                         onOpenDirectory: onOpenDirectory,
                                         onPipeChange: { onPipeChange(session, $0) },
                                         onStageEditEnded: onStageEditEnded,
                                         stageHistory: stageHistory)
                        .id(session.id)
                        .zIndex(session.id == expandedID ? 1 : 0)
                        .transition(.layersBlock)
                        .onGeometryChange(for: CGFloat.self) { Self.usableHeight($0.size.height, max: maxHeight) } action: {
                            blockHeights[session.id] = $0
                        }
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
                            if session.id == expandedID { frames?.expanded = frame }
                        }
                    }
                }
                .animation(LayersDepth.spring, value: sessions.map(\.id))
                .onGeometryChange(for: CGFloat.self) { Self.usableHeight($0.size.height, max: maxHeight) } action: {
                    contentHeight = $0
                }
              }
              // .never, а не .hidden: .hidden уступает настройке macOS «Показывать полосы прокрутки: всегда»
              .scrollIndicators(.never)
              .scrollPosition(Bindable(metrics).position)
              .onScrollGeometryChange(for: [CGFloat].self) {
                  [$0.contentOffset.y, $0.contentSize.height, $0.containerSize.height]
              } action: { _, value in
                  if abs(value[0] - metrics.offset) > 0.5 { metrics.lastScroll = Date() }
                  metrics.offset = value[0]; metrics.content = value[1]; metrics.visible = value[2]
              }
              .frame(height: min(contentHeight, maxHeight))
              // скруглён как панель: обрезанный снизу блок не даёт прямых углов
              .clipShape(RoundedRectangle(cornerRadius: LauncherMetrics.innerRadius))
              // полосы прокрутки нет: список листается колёсиком и трекпадом
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
    /// Высота, которая влияет на раскладку: выше предела панели всё равно прокрутка.
    /// Ленивый список уточняет оценку высоты большого текста с каждым проходом; если
    /// запоминать каждое уточнение, оно запускает новый проход — бесконечный цикл
    /// перерисовок (зависание на большом выводе). Поэтому — с потолком и округлением.
    static func usableHeight(_ height: CGFloat, max limit: CGFloat) -> CGFloat {
        min(height, limit).rounded()
    }

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
        // строка «скрыто N · Развернуть» выше обычной строки вывода
        let free = maxHeight - others - LauncherMetrics.blockChrome
            - (LauncherMetrics.markerRowHeight - LauncherMetrics.outputLineHeight)
        return max(compactLines, Int(free / LauncherMetrics.outputLineHeight))
    }
}

/// Мини-блок сессии. Клик раскрывает его на всю область истории,
/// клик по заголовку раскрытого — сворачивает.
struct SessionBlockView: View {
    let session: Session
    let lang: String
    var isSelected = false
    var isExpanded = false
    /// Раскрыт другой блок — этот уходит в тень.
    var dimmed = false
    /// Сколько строк вывода показать в свёрнутом виде (включая строку «скрыто N»).
    var outputLines = SettingsStore.defaultPreviewLines
    /// Живой терминал интерактивной сессии — показывается в раскрытом блоке.
    var terminal: InteractiveTerminal?
    var terminalHeight: CGFloat = LauncherMetrics.terminalHeight(historyHeight: PanelSize.defaultHistoryHeight)
    var onToggle: () -> Void = {}
    var onKill: () -> Void = {}
    var onRerun: () -> Void = {}
    var onCopy: () -> Void = {}
    var onPin: () -> Void = {}
    var isFavorite = false
    var onFavorite: () -> Void = {}
    var onDelete: () -> Void = {}
    /// Клик по папке в заголовке: перейти в неё, как `cd`.
    var onOpenDirectory: (String) -> Void = { _ in }
    var onPipeChange: (PipeChange) -> Void = { _ in }
    /// Правку шага закончили клавишей (Enter, Esc) — клавиатура возвращается в поле ввода.
    var onStageEditEnded: () -> Void = {}
    /// Применявшиеся шаги конвейера (по всем блокам) — первые в подсказках.
    var stageHistory: [String] = []
    /// Какой шаг конвейера редактируется: индекс, `pipeline.count` — новый шаг, nil — никакой.
    @State private var editingStage: Int?
    @State private var stageDraft = ""
    @FocusState private var stageFieldFocused: Bool
    @State private var stageEngine = ShellCompletionEngine()
    @State private var stageCandidates: [String] = []
    /// Сколько символов вывода влезает в строку превью (0 — ещё не измерено).
    @State private var previewColumns = 0
    @State private var stageSelected = 0
    /// Текст подставлен из варианта (TAB, клик) — варианты не пересчитываем.
    @State private var stageApplying = false
    @State private var hovered = false

    var body: some View {
        let _ = RenderProbe.hit("SessionBlockView")
        VStack(alignment: .leading, spacing: 8) {
            header

            // тонкий разделитель между заголовком и выводом, как между строками системных настроек
            if isExpanded || !session.output.isEmpty {
                Rectangle().fill(.white.opacity(0.05)).frame(height: 1)
                    .padding(.horizontal, -LauncherMetrics.blockPadding)
            }

            if editingStage != nil, !stageCandidates.isEmpty {
                stageSuggestionsRow
            }

            // вывод длиннее буфера: начало потеряно — говорим об этом, а не молчим
            if let dropped = session.outputDropped, !showsLiveTerminal {
                droppedNote(dropped)
            }

            if isExpanded {
                expandedBody
            } else if !session.output.isEmpty {
                outputPreview
            }
        }
        .padding(LauncherMetrics.blockPadding)
        // утоплен в окно: тень по верхней стенке, мягкий блик снизу; под курсором чуть светлее
        .sunken(blockShape, fill: hovered && !dimmed ? Tactile.sunkenHover : Tactile.sunken)
        // раскрытый выделен приглушёнными соседями, обводка — только у выбранного стрелками
        .selectionRing(cornerRadius: LauncherMetrics.innerRadius, visible: isSelected && !isExpanded)
        // при раскрытом блоке остальные приглушены
        .opacity(dimmed ? LayersDepth.dimmedOpacity : 1)
        .animation(LayersDepth.hoverSpring, value: DepthKey(hovered: hovered || isSelected, dimmed: dimmed, expanded: isExpanded))
        .contentShape(blockShape)
        .onHover { hovered = $0 }
        .onTapGesture { if !isExpanded { onToggle() } }
        // поле шага не остаётся висеть: ушёл фокус или блок свернули — набранное применяется,
        // пустое просто закрывается (иначе в свёрнутом блоке оставались поле с рамкой и подсказки)
        .onChange(of: stageFieldFocused) { _, focused in
            if !focused { commitStage() }
        }
        .onChange(of: isExpanded) { _, expanded in
            if !expanded { commitStage() }
        }
        // пока раскрыт другой блок, этот не нажимается: клик по нему лишь сворачивает раскрытый
        .allowsHitTesting(!dimmed)
    }

    private var blockShape: RoundedRectangle { RoundedRectangle(cornerRadius: LauncherMetrics.innerRadius) }

    private struct DepthKey: Equatable { let hovered: Bool, dimmed: Bool, expanded: Bool }


    /// Команда и под ней папка·время; справа шаги конвейера и общее место статуса и кнопок.
    private var header: some View {
        HStack(spacing: 8) {
            // треугольник раскрытия, как в списках Finder: поворачивается, когда блок раскрыт
            Image(systemName: "arrowtriangle.right.fill")
                .font(.system(size: 7))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))
                .animation(LayersDepth.spring, value: isExpanded)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.command)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    if let directory = session.directory {
                        directoryLabel(directory)
                    }
                    Text(session.createdAt.formatted(date: .omitted, time: .shortened))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                }
                .font(.system(size: 11.5))
            }

            Spacer(minLength: 4)

            pipelineChips

            statusSlot
        }
        .contentShape(Rectangle())
        // заголовок перехватывает клик у блока, поэтому сам переключает в обе стороны:
        // у свёрнутого блока без вывода, кроме заголовка, кликать не по чему
        .onTapGesture { onToggle() }
        .help(isExpanded ? L.t("collapse", lang) : "")
    }

    /// Статус и кнопки делят одно место у правого края: при наведении статус перелистывается
    /// вверх, а кнопки поднимаются снизу по одной — шаги конвейера и «+» остаются на месте.
    private var statusSlot: some View {
        let showActions = hovered || isExpanded || isSelected
        let actions = blockActions
        return ZStack(alignment: .trailing) {
            StatusCapsule(status: BlockStatus(session), lang: lang)
                .rotation3DEffect(.degrees(showActions ? 75 : 0), axis: (1, 0, 0), anchor: .top, perspective: 0.5)
                .offset(y: showActions ? -8 : 0)
                .opacity(showActions ? 0 : 1)
                .animation(.spring(response: 0.38, dampingFraction: 0.8), value: showActions)
            HStack(spacing: 4) {
                ForEach(Array(actions.enumerated()), id: \.offset) { index, action in
                    GlassIconButton(icon: action.icon, color: action.color, size: LauncherMetrics.blockButton,
                                    help: action.help, action: action.run)
                        .rotation3DEffect(.degrees(showActions ? 0 : -75), axis: (1, 0, 0), anchor: .bottom, perspective: 0.5)
                        .offset(y: showActions ? 0 : 8)
                        .opacity(showActions ? 1 : 0)
                        .animation(.spring(response: 0.38, dampingFraction: 0.72)
                                    .delay(showActions ? Double(actions.count - 1 - index) * 0.035 : 0),
                                   value: showActions)
                }
            }
            .allowsHitTesting(showActions)
        }
    }

    private struct BlockAction {
        let icon: KeyIcon
        var color: Color? = nil
        let help: String
        let run: () -> Void
    }

    private var blockActions: [BlockAction] {
        var list = [
            BlockAction(icon: .rerun, help: L.t("rerun", lang), run: onRerun),
            BlockAction(icon: .copy, help: L.t("copy", lang), run: onCopy),
            BlockAction(icon: isFavorite ? .starOn : .star, color: isFavorite ? Tactile.star : nil,
                        help: L.t(isFavorite ? "fav_remove" : "fav_cmd_toggle", lang), run: onFavorite),
            BlockAction(icon: session.isPinned ? .pinOn : .pin, color: session.isPinned ? LayersPalette.accent : nil,
                        help: L.t("pin", lang), run: onPin),
        ]
        if session.state.isActive {
            list.append(BlockAction(icon: .stop, color: LayersPalette.error, help: L.t("stop", lang), run: onKill))
        }
        list.append(BlockAction(icon: .trash, help: L.t("delete", lang), run: onDelete))
        return list
    }

    /// Папка, где выполнялась команда: только имя, полный путь — в подсказке; клик — перейти в неё.
    /// Уступает место команде: не влезает имя — остаётся значок, не влезает и он — ничего.
    private func directoryLabel(_ directory: String) -> some View {
        Button { onOpenDirectory(directory) } label: {
            ViewThatFits(in: .horizontal) {
                Label(PathBreadcrumbs.folderName(for: directory), systemImage: "folder")
                    .fixedSize()
                Image(systemName: "folder")
                Color.clear.frame(width: 0, height: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .font(.caption)
        .foregroundStyle(.secondary)
        .layoutPriority(-1)
        .help(String(format: L.t("go_to_folder", lang), PathBreadcrumbs.displayPath(for: directory)))
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
                // в макете — знак «+» шрифтом 15, а не жирный символ
                Text("+")
                    .font(.system(size: 15))
                    .foregroundStyle(Tactile.keyText)
                    .frame(width: LauncherMetrics.blockButton, height: LauncherMetrics.blockButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(KeyCapButtonStyle(cornerRadius: LauncherMetrics.buttonRadius(LauncherMetrics.blockButton)))
            .help(L.t("add_pipe_stage", lang))
        }
    }

    private func stageChip(_ stage: String, index: Int) -> some View {
        HStack(spacing: 4) {
            // токен по размеру текста; длинный шаг сокращается (целиком — при правке)
            Text("| " + (stage.count > 28 ? String(stage.prefix(27)) + "…" : stage))
                .font(.system(size: 12, design: .monospaced))
                .lineLimit(1)
                .fixedSize()
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
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .foregroundStyle(.white)
        .background(Tactile.accent.opacity(0.32), in: RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Tactile.accent.opacity(0.8), lineWidth: 0.5))
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
                .onSubmit { commitStage(); onStageEditEnded() }
                .onExitCommand { editingStage = nil; stageCandidates = []; onStageEditEnded() }
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
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .sunken(RoundedRectangle(cornerRadius: 6), fill: Tactile.field)
        .selectionRing(cornerRadius: 6, visible: true)
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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .tactileRaised(Capsule(), fill: next ? Tactile.raiseHover : Tactile.raise)
                        .onTapGesture { applyStageCandidate(candidate) }
                }
            }
        }
    }

    private func commitStage() {
        guard let index = editingStage else { return }
        editingStage = nil
        stageCandidates = []
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
            // в той же утопленной лунке, что и готовый вывод: блок не «всплывает», пока команда работает
            TerminalHostView(terminal: terminal)
                .id(ObjectIdentifier(terminal)) // после перезапуска — новый терминал
                .frame(maxWidth: .infinity)
                .frame(height: max(terminalHeight - 16, 80))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .sunken(RoundedRectangle(cornerRadius: 8), fill: Tactile.field)
        } else {
            // по высоте текста: список прокручивается дальше, к остальным блокам
            fullOutput
        }
    }

    /// В раскрытом блоке работающей команды — живой терминал (со своей прокруткой).
    private var showsLiveTerminal: Bool {
        isExpanded && terminal != nil && session.state.isActive
    }

    private func droppedNote(_ count: Int) -> some View {
        Label(String(format: L.t("dropped_lines", lang), count), systemImage: "scissors")
            .font(.system(size: LauncherMetrics.outputFontSize, weight: .medium))
            .foregroundStyle(.orange)
            .help(L.t("dropped_lines_hint", lang))
    }

    /// Весь вывод — в нативном текстовом поле: любой объём, выделение, поиск ⌘F.
    private var fullOutput: some View {
        OutputTextView(text: ANSIText.nsAttributed(
            session.outputANSI ?? session.output,
            font: NSFont.monospacedSystemFont(ofSize: LauncherMetrics.outputFontSize, weight: .regular)))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .sunken(RoundedRectangle(cornerRadius: 8), fill: Tactile.field)
    }

    /// Свёрнутый вывод: начало, «скрыто N строк» с кнопкой раскрыть, конец.
    /// Длинные строки переносятся по словам; лимит — в экранных строках.
    private var outputPreview: some View {
        let source = session.outputANSI ?? session.output
        let columns = previewColumns
        let limit = outputLines + 1
        let layout = OutputPreview.layout(lines: source.components(separatedBy: "\n"),
                                          gap: session.outputGap, maxLines: outputLines,
                                          rows: { columns > 0 ? wrappedRows($0, columns: columns, limit: limit).count : 1 })
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(layout.head.enumerated()), id: \.offset) { outputLine($0.element, rows: layout.headRows[$0.offset]) }
            if layout.hidden > 0 { hiddenLinesMarker(layout.hidden) }
            ForEach(Array(layout.tail.enumerated()), id: \.offset) { outputLine($0.element, rows: layout.tailRows[$0.offset]) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // сколько символов влезает в строку — от ширины блока
        .onGeometryChange(for: Int.self) { Int($0.size.width / LauncherMetrics.outputCharWidth) } action: {
            previewColumns = $0
        }
    }

    /// Экранные строки строки вывода: перенос по словам по видимому тексту (без ANSI-кодов).
    private func wrappedRows(_ line: String, columns: Int, limit: Int) -> [AttributedSubstring] {
        let text = session.outputANSI == nil ? AttributedString(line) : ANSIText.attributed(line)
        let chars = text.characters
        return OutputWrap.rows(String(chars), columns: columns, limit: limit).map { range in
            let from = chars.index(chars.startIndex, offsetBy: range.lowerBound)
            let to = chars.index(chars.startIndex, offsetBy: range.upperBound)
            return text[from..<to]
        }
    }

    /// Строка вывода: по экранной строке фиксированной высоты, перенос по словам;
    /// не влезла целиком — последняя показанная строка кончается «…» (целиком — в раскрытом блоке).
    @ViewBuilder
    private func outputLine(_ line: String, rows shown: Int) -> some View {
        let columns = previewColumns
        if columns > 0 {
            let rows = wrappedRows(line, columns: columns, limit: shown + 1)
            let clipped = rows.count > shown
            ForEach(0..<min(shown, rows.count), id: \.self) { index in
                let row = AttributedString(rows[index])
                outputRow(clipped && index == shown - 1 ? Self.ellipsized(row, columns: columns) : row)
            }
        } else {
            outputRow(session.outputANSI == nil ? AttributedString(line) : ANSIText.attributed(line))
        }
    }

    /// Последняя видимая строка обрезанной строки вывода: «…» в конце, в пределах ширины.
    private static func ellipsized(_ row: AttributedString, columns: Int) -> AttributedString {
        var row = row
        let chars = row.characters
        if chars.count >= columns {
            let cut = chars.index(chars.startIndex, offsetBy: max(columns - 1, 0))
            row = AttributedString(row[row.startIndex..<cut])
        }
        row.append(AttributedString("…"))
        return row
    }

    private func outputRow(_ text: AttributedString) -> some View {
        Text(text)
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
            Button(action: onToggle) {
                Text(L.t("expand", lang))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Tactile.keyText)
                    .padding(.horizontal, 10)
                    .frame(height: LauncherMetrics.markerButtonHeight)
            }
            .buttonStyle(KeyCapButtonStyle(cornerRadius: 7))
        }
        .font(.system(size: LauncherMetrics.outputFontSize, weight: .medium))
        // строка выше обычной: колпачку «Развернуть» нужно место под кромку и тень
        .frame(maxWidth: .infinity, minHeight: LauncherMetrics.markerRowHeight,
               maxHeight: LauncherMetrics.markerRowHeight, alignment: .leading)
    }

}

/// Поле ввода команды: стекло, призрак-превью, мульти-кандидаты с TAB-циклированием.
/// Направление шага по истории из поля ввода.
enum HistoryDirection {
    case older
    case newer
}

/// Что делает поле ввода: запускает команду или ищет по истории (⌘F).
enum InputMode {
    case command
    case search
}

struct CommandInputView: View {
    @Binding var text: String
    /// Текущая директория лаунчера: от неё дополняются относительные пути.
    var directory: String
    var mode: InputMode = .command
    var lang = "ru"
    var onSubmit: (String) -> Void
    /// Шаг по истории стрелкой: текст для поля или nil, если шагать некуда.
    var onHistory: (HistoryDirection) -> String? = { _ in nil }
    /// Пользователь сам поменял текст — навигация по истории сбрасывается.
    var onEdit: () -> Void = {}
    /// Выйти из поиска (клик по метке «Поиск ✕»).
    var onExitSearch: () -> Void = {}
    /// Команды из истории, от новых к старым: источник серой подсказки.
    var history: [String] = []
    /// Поле в фокусе — светится рамка.
    var isFocused = false
    /// Кнопки справа в поле (настройки, очистка).
    var trailing: AnyView?
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

    private var font: Font { .system(size: 17) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            inputField

            if let menu = completer.menu {
                candidatesDropdown(menu)
            }
        }
    }

    private var inputField: some View {
        HStack(spacing: 10) {
        Group {
            if searching {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Tactile.search)
            } else {
                Text("›")
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 16)
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

            TextField(searching ? L.t("search_placeholder", lang) : "Введите команду…", text: $text)
                .textFieldStyle(.plain)
                .font(font)
        }
        if searching { searchBadge }
        if let trailing { trailing }
        }
        .padding(.leading, 14)
        .padding(.trailing, trailing == nil ? 14 : 8)
        .padding(.vertical, 10)
        .sunken(RoundedRectangle(cornerRadius: LauncherMetrics.innerRadius), fill: Tactile.field)
        // в поиске рамка другого цвета и видна всегда: сразу понятно, в каком режиме поле
        .selectionRing(cornerRadius: LauncherMetrics.innerRadius, visible: isFocused || searching,
                       color: searching ? Tactile.search : Tactile.accent)
        .animation(.easeOut(duration: 0.3), value: isFocused)
        .animation(.easeOut(duration: 0.2), value: searching)
        .onChange(of: mode) { _, _ in
            completer.reset()
            historyCompletion = nil
            candidates = []
            candidatesText = nil
        }
        // Shift+TAB приходит как «backtab» (U+0019)
        .onKeyPress(keys: [.tab, KeyEquivalent("\u{19}")]) { press in
            // в поиске дополнять нечего; TAB не уводит фокус из поля
            if searching { return .handled }
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
            // поиск не дополняет пути и не подсказывает команды из истории
            if !searching { refresh(newValue) }
        }
    }

    private var searching: Bool { mode == .search }

    /// Метка режима поиска: клик по ней — выход из поиска.
    private var searchBadge: some View {
        Button(action: onExitSearch) {
            HStack(spacing: 5) {
                Text(L.t("search", lang))
                Text("✕").font(.system(size: 10))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Tactile.search)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(Tactile.search.opacity(0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(Tactile.search.opacity(0.55), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(L.t("search_exit", lang))
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
    }

    /// Остаток подсказки из истории после набранного.
    private var historyGhost: String? {
        guard !searching, completer.menu == nil, let completion = historyCompletion,
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
            .scrollIndicators(.never)
            .onChange(of: menu.index) { _, index in
                if let index { proxy.scrollTo(index) }
            }
        }
        .frame(maxHeight: 140)
        .background(Tactile.group, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Tactile.groupEdge)
        )
        .shadow(color: .black.opacity(0.45), radius: 10, y: 6)
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
        terminal.applyColors(dark: context.environment.colorScheme == .dark)
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

    func updateNSView(_ nsView: NSView, context: Context) {
        // сменили тему — терминал перекрашивается вместе с панелью
        terminal.applyColors(dark: context.environment.colorScheme == .dark)
    }
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

/// Счётчик вычислений `body` — ловит циклы перерисовок в тестах. В релизной сборке пустой.
enum RenderProbe {
    #if DEBUG
    private(set) static var counts: [String: Int] = [:]
    static func hit(_ name: String) { counts[name, default: 0] += 1 }
    static func reset() { counts = [:] }
    #else
    static func hit(_ name: String) {}
    #endif
}
