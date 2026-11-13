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
    @Environment(ClipboardHistory.self) private var clipboard

    @State private var text = ""
    /// Режим поиска (⌘F): то же поле ввода ищет по истории; набранная команда ждёт в `text`.
    @State private var searchMode = false
    @State private var searchQuery = ""
    /// Режим буфера обмена (⌘4): поле ищет по скопированному, вместо истории — фрагменты.
    @State private var clipboardMode = false
    @State private var clipboardQuery = ""
    /// Выбранный фрагмент (↑/↓) в отфильтрованном списке.
    @State private var clipSelection = 0
    /// Картинка из буфера, открытая крупно (Space, ⌘Y).
    @State private var previewClipID: UUID?
    /// Выделение текста на картинке в просмотре (Live Text).
    @State private var previews = ClipPreviews()
    /// Тип фрагментов в фильтре над полем (Tab, ⇧Tab, клик).
    @State private var clipKind: ClipKind = .all
    /// ⌘1 (или сочетание из настроек): дерево папок у текущей папки; счётчик — каждое нажатие.
    @State private var folderTreeRequest = 0
    /// Список «Избранное» (кнопка ★, ⌘E).
    @State private var favoritesOpen = false
    /// Шпаргалка по клавишам (⌘/).
    @State private var keysOpen = false
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
    /// Похожие имена считаются один раз на опечатку, а не на каждую перерисовку.
    @State private var missingSuggestionsCache: (word: String, list: [String])?
    /// Открыт список вариантов TAB: Esc сначала возвращает набранное.
    @State private var completionMenuOpen = false

    private var lang: String { settings.languageCode }

    var body: some View {
        // Высота панели — по содержимому (до предела истории); окно следует за ней.
        // Настройки — отдельное окно поверх панели: их высота панель не растягивает.
        // Панель за ними темнеет; клик по ней, Esc, ✕ и «Готово» закрывают настройки.
        attachLifecycle(ZStack(alignment: .top) {
            panelContent
                .brightness(showSettings ? -0.35 : 0)
                .allowsHitTesting(!showSettings)
                .hatchPopup(isPresented: Binding(get: { showSettings }, set: { if !$0 { closeSettings() } }),
                            placement: .overTop) { _ in
                    // своё окно — своё окружение: хранилища передаются явно
                    SettingsView(onClose: closeSettings)
                        .environment(settings)
                        .environment(clipboard)
                        .padding(PopupController.margin)
                        .fixedSize()
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
            // строка над полем: слева — что важно в режиме (путь, счётчик поиска, фильтр буфера),
            // справа — переключатель режимов. Всё в одной строке, её высота не меняется
            HStack(spacing: 10) {
                ZStack(alignment: .leading) {
                    DirectoryBreadcrumbsView(path: settings.currentDirectory,
                                             recent: settings.recentDirectories,
                                             favorites: settings.favoriteDirectories,
                                             lang: lang,
                                             onNavigate: { settings.currentDirectory = $0 },
                                             onToggleFavorite: toggleFavoriteDirectory,
                                             treeRequest: folderTreeRequest)
                        .opacity(clipboardMode || searchMode ? 0 : 1)
                        .allowsHitTesting(!clipboardMode && !searchMode)
                    if clipboardMode { clipboardFilterBar }
                    if searchMode { searchSummary }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ModeSwitcher(mode: inputMode, lang: lang, onSelect: switchMode)
                    // ⌘/ — шпаргалка по клавишам текущего режима, под переключателем
                    .hatchPopup(isPresented: $keysOpen) { _ in
                        PopupCard {
                            KeysSheetView(mode: inputMode, hotkey: SystemScreenshotShortcuts.display(settings.hotkeyString), lang: lang)
                        }
                    }
            }
                .padding(.leading, 14) // по левому краю текста в поле ввода
                .padding(.trailing, 2)
                .padding(.bottom, -4)  // ближе к полю, чем к краю панели

            CommandInputView(text: searchMode ? $searchQuery : clipboardMode ? $clipboardQuery : $text,
                             directory: settings.currentDirectory,
                             mode: searchMode ? .search : clipboardMode ? .clipboard : .command,
                             lang: lang,
                             onSubmit: { command in
                                 if searchMode { openFound(); return }
                                 if clipboardMode { copyClip(nil); return }
                                 navigator.reset()
                                 if performQuickAction(command) { return }
                                 run(command)
                                 text = ""
                             },
                             onHistory: navigateHistory,
                             onEdit: {
                                 navigator.reset()
                                 // начали править — строка «Команды нет» больше не про это
                                 if let missing = runner.missingCommand, text != missing.command {
                                     runner.dismissMissingCommand()
                                 }
                                 // фильтрует историю только поиск; набор команды список не трогает
                                 if searchMode { sessionStore.filterText = searchQuery.trimmingCharacters(in: .whitespaces) }
                                 if clipboardMode { clipSelection = 0 }
                             },
                             onExitSearch: { clipboardMode ? exitClipboard() : exitSearch() },
                             history: historyCommands,
                             quickAction: { commandMode ? resolveQuickAction($0) : nil },
                             fix: commandMode ? missingFix : nil,
                             alert: commandMode && runner.missingCommand != nil,
                             isFocused: inputFocused,
                             onCompletionMenu: { completionMenuOpen = $0 },
                             trailing: AnyView(inputButtons))
            .focused($inputFocused)

            if let missing = runner.missingCommand, commandMode {
                MissingCommandRow(missing: missing, suggestions: missingSuggestions, lang: lang) { word in
                    text = CommandNotFound.replacingFirstWord(in: missing.command, with: word)
                    inputFocused = true
                }
            }

            Group {
                if clipboardMode { clipboardArea } else { historyArea }
            }
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
        .animation(.easeOut(duration: 0.15), value: runner.missingCommand)
    }

    /// Жизненный цикл, горячие клавиши и диалоги панели — отдельно от раскладки.
    private func attachLifecycle<V: View>(_ content: V) -> some View {
        content
        .onAppear {
            inputFocused = true
            previews.onTransientGone = { previewClipID = nil }
            previews.menuItems = { previewMenuItems(for: $0) }
            previews.onToggleFormat = { togglePreviewFormat($0) }
            NotificationService().requestPermission()
            installKeyShortcuts()
            AppCatalog.shared.refresh()
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
        // клик по миниатюре скриншота: снимок окном просмотра, панель остаётся скрытой
        .onReceive(NotificationCenter.default.publisher(for: .hatchOpenClip)) { note in
            guard let id = note.object as? UUID else { return }
            previewDetached(id, screen: (note.userInfo?["screen"] as? NSValue)?.rectValue)
        }
        // ⌘1 открыл или закрыл просмотр картинки — окно просмотра следом
        .onChange(of: previewClipID) { _, id in syncPreview(id) }
        .onReceive(NotificationCenter.default.publisher(for: .hatchDidShow)) { _ in
            // панель открывается заново — в обычном режиме, с набранной командой
            if searchMode { exitSearch() }
            if clipboardMode { exitClipboard() }
            inputFocused = true
            switchToLatinIfEnabled() // фокус мог уже стоять в поле — onChange не сработает
            AppCatalog.shared.refresh() // приложения могли поставить или удалить
        }
        // курсор в поле ввода — латинская раскладка (если включено в настройках)
        .onChange(of: inputFocused) { _, focused in
            if focused { switchToLatinIfEnabled() }
        }
        .onChange(of: settings.latinLayoutInInput) { _, enabled in
            if enabled { switchToLatinIfEnabled() } else { KeyboardLayoutSwitcher.shared.restore() }
        }
        // команда ждёт ввода (вопрос, пароль, полноэкранная программа) — раскрыть её блок
        .onChange(of: runner.inputRequest) { _, request in
            guard let request, sessionStore.sessions.contains(where: { $0.id == request.sessionID }) else { return }
            if searchMode { exitSearch() }
            if expandedID != request.sessionID { expand(request.sessionID) }
        }
        // команды нет: блока в истории нет, набранное возвращается в поле, если оно ещё пустое
        .onChange(of: runner.missingCommand) { _, missing in
            guard let missing else { missingSuggestionsCache = nil; return }
            missingSuggestionsCache = (missing.word, CommandNotFound.suggestions(
                for: missing.word, commands: CommandIndex.shared(for: settings.shellPath).allCommands, apps: appNames))
            if text.isEmpty, commandMode {
                text = missing.command
                inputFocused = true
            } else {
                runner.dismissMissingCommand()
            }
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
    private var inputMode: InputMode { searchMode ? .search : clipboardMode ? .clipboard : .command }

    /// Клик по переключателю режимов: тот же переход, что по ⌘F, ⌘4 или Esc.
    private func switchMode(_ mode: InputMode) {
        guard mode != inputMode else { return }
        switch mode {
        case .command:
            if searchMode { exitSearch() }
            if clipboardMode { exitClipboard() }
        case .search: toggleSearch()
        case .clipboard: toggleClipboard()
        }
    }

    /// В поиске над полем: сколько нашлось. Пустой запрос — подсказка, где ищем.
    private var searchSummary: some View {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        let stats = SearchStats.count(query, in: sessionStore.filteredSessions)
        return Group {
            if query.isEmpty {
                Text(L.t("search_scope", lang))
            } else {
                Text(SearchStats.summary(stats, lang: lang)).foregroundStyle(stats.blocks > 0 ? Tactile.search : .secondary)
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .lineLimit(1)
    }

    private var inputButtons: some View {
        HStack(spacing: 6) {
            // список избранного — закладки: звёздочка значит «добавить в избранное» (у пути и у блока)
            GlassIconButton(icon: favoritesOpen ? .bookmarksOn : .bookmarks, color: favoritesOpen ? Tactile.star : nil,
                            size: LauncherMetrics.inputButton, help: L.t("favorites", lang) + " (⌘E)") { favoritesOpen.toggle() }
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
                                  onRemoveCommand: { settings.toggleFavoriteCommand($0) },
                                  onMoveDirectory: { settings.moveFavoriteDirectory(from: $0, to: $1) },
                                  onMoveCommand: { settings.moveFavoriteCommand(from: $0, to: $1) })
                    }
                }
            GlassIconButton(icon: .gear, size: LauncherMetrics.inputButton, help: L.t("settings", lang) + " (⌘,)") { openSettings() }
            // очистка — ⌃L и команда clear, корзины у поля нет: разрушительное действие рядом с настройками
        }
    }

    private func openSettings() {
        inputFocused = false
        withAnimation(LayersDepth.spring) { showSettings = true }
    }

    private func closeSettings() {
        guard showSettings else { return }
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
            onStageEditEnded: { if expandedID == nil { inputFocused = true } },
            blockSyntax: { blockSyntax($0) },
            onToggleFormat: { toggleBlockFormat($0) },
            highlight: searchMode ? searchQuery.trimmingCharacters(in: .whitespaces) : nil,
            clipboardMatches: searchMode && !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
                ? clipboard.matching(searchQuery.trimmingCharacters(in: .whitespaces), kind: .all).count : 0
        )
    }

    // MARK: - Actions

    private func navigateHistory(_ direction: HistoryDirection) -> String? {
        if clipboardMode {
            // в буфере стрелки двигают выбор, запрос остаётся
            let count = visibleClips.count
            guard count > 0 else { return clipboardQuery }
            clipSelection = min(max(clipSelection + (direction == .older ? 1 : -1), 0), count - 1)
            return clipboardQuery
        }
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
        if clipboardMode { exitClipboard() }
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

    // MARK: - Буфер обмена (⌘4)

    /// Поле ввода — для команды (не поиск и не буфер): подсказки, приложения, калькулятор.
    private var commandMode: Bool { !searchMode && !clipboardMode }

    private var visibleClips: [Clip] { clipboard.matching(clipboardQuery, kind: clipKind) }

    /// Над полем в режиме буфера: тип фрагментов с числами (по набранному запросу) и срок хранения.
    private var clipboardFilterBar: some View {
        let counts = clipboard.counts(clipboardQuery)
        let kinds: [(ClipKind, String)] = [(.all, L.t("clip_kind_all", lang)), (.text, L.t("clip_kind_text", lang)),
                                           (.images, L.t("clip_kind_images", lang)), (.pinned, "📌")]
        return HStack(spacing: 8) {
            GlassSegmented(options: kinds.map { (id: $0.0.rawValue, title: $0.1) },
                           selection: Binding(get: { clipKind.rawValue },
                                              set: { clipKind = ClipKind(rawValue: $0) ?? .all; clipSelection = 0 }),
                           details: Dictionary(uniqueKeysWithValues: kinds.map { ($0.0.rawValue, "\(counts[$0.0] ?? 0)") }),
                           compact: true)
                .help(L.t("clip_kind_help", lang))
            Spacer(minLength: 0)
            Text(String(format: L.t("clip_days", lang), settings.clipboardDays))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private var selectedClip: Clip? {
        let clips = visibleClips
        return clips.indices.contains(clipSelection) ? clips[clipSelection] : clips.first
    }

    private var clipboardArea: some View {
        ClipboardListView(clips: visibleClips, total: clipboard.clips.count, query: clipboardQuery,
                          selection: clipSelection, days: settings.clipboardDays, lang: lang,
                          maxHeight: settings.historyMaxHeight, onCopy: { copyClip($0) },
                          onSelect: { clipSelection = $0 }, onInsert: { insertClip($0) },
                          onPreview: { clip in
                              // клик по миниатюре открытой картинки: просмотр уже закрыл сам клик мимо
                              if previews.closedByClickJustNow(clip.id) { return }
                              previewClipID = previewClipID == clip.id ? nil : clip.id
                          },
                          onTogglePin: { togglePin($0) }, onDelete: deleteClip,
                          imageURL: { clipboard.imageURL($0) },
                          syntax: { clipSyntax($0) }, onToggleFormat: { toggleClipFormat($0) })
        // ⌘1 — картинка крупно, окном над списком (см. ClipPreviewWindow); ⌘1, Esc, ⌘W или клик мимо — закрыть
        .background(ClipPreviewAnchor(previews: previews))
    }

    /// Меню по правому клику на картинке: с выделением — сначала действия с ним, затем действия с картинкой
    /// с их клавишами; «Удалить» — в конце, после системных пунктов Live Text.
    private func previewMenuItems(for preview: ClipPreviewWindow) -> (leading: [NSMenuItem], trailing: [NSMenuItem]) {
        // у текста своё меню — системное меню текстового поля
        guard let url = preview.model.url else { return ([], []) }
        let live = preview.model.liveText
        let clip = clip(of: preview)
        var leading: [NSMenuItem] = []
        if live.hasSelection {
            let selected = live.selectedText
            leading.append(ClosureMenuItem(L.t("clip_menu_copy_selection", lang), key: "c", modifiers: .command) {
                copyPreviewText(selected, from: preview)
            })
            leading.append(ClosureMenuItem(L.t("clip_menu_insert_selection", lang), key: "v", modifiers: .command) {
                fromPreview(preview) { insertText(selected) }
            })
            leading.append(.separator())
        }
        leading.append(ClosureMenuItem(L.t("clip_menu_copy", lang), key: "\r") { copyPreviewImage(preview) })
        leading.append(ClosureMenuItem(L.t("clip_menu_insert_path", lang), key: "\r", modifiers: .command) {
            fromPreview(preview) { insertPath(url) }
        })
        if let text = clip?.image?.text, !text.isEmpty {
            leading.append(ClosureMenuItem(L.t("clip_menu_copy_text", lang)) { copyPreviewText(text, from: preview) })
        }
        leading.append(.separator())
        leading.append(ClosureMenuItem(L.t(preview.model.isPinned ? "clip_menu_unfloat" : "clip_menu_float", lang),
                                       key: "s", modifiers: .command) { previews.togglePin(preview) })
        if let clip {
            leading.append(ClosureMenuItem(L.t(clip.isPinned ? "clip_menu_unpin" : "clip_menu_pin", lang)) { togglePin(clip) })
        }
        let delete = ClosureMenuItem(L.t("clip_menu_delete", lang), key: "\u{8}", modifiers: .command) {
            deletePreviewClip(preview)
        }
        return (leading, [delete])
    }

    /// Фрагмент окна просмотра (могли уже удалить — тогда окно показывает только картинку).
    private func clip(of preview: ClipPreviewWindow) -> Clip? {
        clipboard.clips.first { $0.id == preview.model.clipID }
    }

    /// Картинку — окном просмотра без панели, по центру `screen` (видимой части экрана).
    private func previewDetached(_ id: UUID, screen: NSRect?) {
        guard let clip = clipboard.clips.first(where: { $0.id == id }), let model = previewModel(for: clip),
              let visible = screen ?? NSScreen.main?.visibleFrame else { return }
        previews.showDetached(model, lang: lang, in: visible)
    }

    private func previewModel(for clip: Clip) -> ClipPreviewModel? {
        if !clip.isImage {
            // текст: формат узнан — отформатирован (как в настройках или по {} у записи)
            let options = settings.syntaxOptions
            let syntax = SyntaxService.shared
            let kind = syntax.kind(of: clip.text, options: options)
            let language = kind == .code ? syntax.codeLanguage(of: clip.text) : nil
            let what = kind.map { $0.label(code: language) }
                ?? L.t("preview_text", lang) + " · " + String(format: L.t("clip_lines", lang), clip.lineCount)
            let caption = [what, clip.app].compactMap { $0 }.joined(separator: " · ")
            return ClipPreviewModel(clipID: clip.id, text: clip.text, caption: caption, kind: kind, codeLanguage: language,
                                    formatted: clip.formatted ?? settings.formatsByDefault(bundleID: clip.bundleID),
                                    options: options)
        }
        guard let image = clip.image, let url = clipboard.imageURL(clip), let picture = NSImage(contentsOf: url) else { return nil }
        let caption = [image.summary(lang: lang), clip.app].compactMap { $0 }.joined(separator: " · ")
        return ClipPreviewModel(clipID: clip.id, image: picture, url: url, caption: caption)
    }

    /// Панель открыла или закрыла просмотр (`previewClipID`) — окно следом.
    private func syncPreview(_ id: UUID?) {
        guard let id else { previews.closeTransient(); return }
        if previews.transient?.model.clipID == id { return }
        guard let clip = clipboard.clips.first(where: { $0.id == id }), let model = previewModel(for: clip) else {
            previewClipID = nil
            return
        }
        let parent = previews.anchor?.window ?? NSApp.windows.first { $0 is LauncherPanel && $0.isVisible }
        previews.show(model, lang: lang, parent: parent)
    }

    /// Клавиши окна просмотра — и открытого из панели, и закреплённого. true — нажатие обработано.
    private func handlePreviewKey(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags, _ preview: ClipPreviewWindow) -> Bool {
        if preview.model.isText { return handleTextPreviewKey(code, modifiers, preview) }
        let live = preview.model.liveText
        let fromPanel = previews.isTransient(preview)
        switch (code, modifiers) {
        case (53, []), (13, .command):
            // Esc и ⌘W: сначала снять выделение, затем закрыть. Сами: до окна Esc не доходит —
            // его забирает слой выделения текста
            if live.hasSelection { live.resetSelection() } else { previews.close(preview) }
        case (12, .command) where !fromPanel:
            // ⌘Q в закреплённом окне закрывает его (из панели ⌘Q, как везде, скрывает Hatch)
            if live.hasSelection { live.resetSelection() } else { previews.close(preview) }
        case (1, .command):
            // ⌘S — закрепить окно поверх остальных или открепить
            previews.togglePin(preview)
        case (8, .command):
            // ⌘C: выделенный текст, без выделения — картинка (как Enter)
            if live.hasSelection { copyPreviewText(live.selectedText, from: preview) } else { copyPreviewImage(preview) }
        case (36, []):
            copyPreviewImage(preview)
        case (9, .command):
            // ⌘V: выделенный текст — в поле ввода
            guard live.hasSelection else { NSSound.beep(); return true }
            let selected = live.selectedText
            fromPreview(preview) { insertText(selected) }
        case (36, .command):
            guard let url = preview.model.url else { NSSound.beep(); return true }
            fromPreview(preview) { insertPath(url) }
        case (0, .command):
            // ⌘A: весь текст на картинке
            if !live.selectAll() { NSSound.beep() }
        case (51, .command):
            deletePreviewClip(preview)
        default:
            return false
        }
        return true
    }

    /// Клавиши окна текста: то же, что у картинки; ↩ и ⌘C без выделения — то, что видно, ⌘R — {}.
    private func handleTextPreviewKey(_ code: UInt16, _ modifiers: NSEvent.ModifierFlags, _ preview: ClipPreviewWindow) -> Bool {
        let model = preview.model
        let fromPanel = previews.isTransient(preview)
        switch (code, modifiers) {
        case (53, []), (13, .command):
            if model.hasTextSelection { model.clearTextSelection() } else { previews.close(preview) }
        case (12, .command) where !fromPanel:
            if model.hasTextSelection { model.clearTextSelection() } else { previews.close(preview) }
        case (1, .command):
            previews.togglePin(preview)
        case (8, .command):
            // ⌘C: выделенное; без выделения — весь текст, как он виден
            copyPreviewText(model.hasTextSelection ? model.selectedText : model.shownText, from: preview)
        case (36, []):
            copyShownText(preview)
        case (9, .command):
            guard model.hasTextSelection else { NSSound.beep(); return true }
            let selected = model.selectedText
            fromPreview(preview) { insertText(selected) }
        case (36, .command):
            let text = model.text ?? ""
            fromPreview(preview) { insertText(text) }
        case (0, .command):
            if !model.selectAllText() { NSSound.beep() }
        case (15, [.command, .shift]):
            // ⌘R — форматировать или как есть
            if model.syntaxKind == nil { NSSound.beep() } else { togglePreviewFormat(preview) }
        case (51, .command):
            deletePreviewClip(preview)
        default:
            return false
        }
        return true
    }

    /// ↩ в окне текста: весь текст, как он виден. Из панели — как ↩ в списке (Hatch скрывается).
    private func copyShownText(_ preview: ClipPreviewWindow) {
        let text = preview.model.shownText
        guard !text.isEmpty else { NSSound.beep(); return }
        guard previews.isTransient(preview) else {
            Clipboard.copy(text)
            preview.showToast(L.t("preview_text_copied", lang))
            return
        }
        previews.close(preview)
        Clipboard.copy(text)
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        showToast(String(format: L.t("clip_copied", lang), line))
        exitClipboard()
        hidePanel()
    }

    /// {} и ⌘R: у записи — форматировать или как есть (запоминается в записи).
    private func togglePreviewFormat(_ preview: ClipPreviewWindow) {
        let on = !preview.model.formatted
        preview.model.setFormatted(on)
        clipboard.setFormatted(on, for: preview.model.clipID)
    }

    /// {} у строки списка и ⌘R в буфере.
    private func toggleClipFormat(_ clip: Clip) {
        let on = !clipFormatted(clip)
        clipboard.setFormatted(on, for: clip.id)
        previews.all.filter { $0.model.clipID == clip.id && $0.model.isText }.forEach { $0.model.setFormatted(on) }
    }

    private func clipFormatted(_ clip: Clip) -> Bool {
        clip.formatted ?? settings.formatsByDefault(bundleID: clip.bundleID)
    }

    /// Формат строки списка: метка, включено ли, и строка с подсветкой (когда готова).
    private func clipSyntax(_ clip: Clip) -> ClipSyntax? {
        guard !clip.isImage, clip.text.utf8.count <= ClipSyntax.rowLimit else { return nil }
        let options = settings.syntaxOptions
        let syntax = SyntaxService.shared
        guard let kind = syntax.kind(of: clip.text, options: options) else { return nil }
        let language = kind == .code ? syntax.codeLanguage(of: clip.text) : nil
        let on = clipFormatted(clip)
        let compact = on ? syntax.rendered(clip.text, kind: kind, mode: .compact, options: options).map(SyntaxRender.swiftUI) : nil
        return ClipSyntax(label: kind.label(code: language), on: on, text: compact)
    }

    /// Текст с картинки — в буфер. Из панели: закрывается только просмотр, Hatch остаётся, внизу тост.
    /// Закреплённое окно остаётся, тост — на нём самом.
    private func copyPreviewText(_ copied: String, from preview: ClipPreviewWindow) {
        guard !copied.isEmpty else { NSSound.beep(); return }
        Clipboard.copy(copied)
        if previews.isTransient(preview) {
            previews.close(preview)
            let line = copied.split(separator: "\n").first.map(String.init) ?? copied
            showToast(String(format: L.t("clip_text_copied", lang), line))
        } else {
            preview.showToast(L.t("preview_text_copied", lang))
        }
    }

    /// ↩ и ⌘C без выделения: картинку — в буфер. Из панели — как ↩ в списке (Hatch скрывается),
    /// из закреплённого окна — окно остаётся.
    private func copyPreviewImage(_ preview: ClipPreviewWindow) {
        if previews.isTransient(preview) {
            if let clip = clip(of: preview) { copyClip(clip) } else { NSSound.beep() }
            return
        }
        guard let url = preview.model.url, Clipboard.copyImage(at: url) else { NSSound.beep(); return }
        preview.showToast(L.t("preview_image_copied", lang))
    }

    /// ⌘V и ⌘↩ — в поле ввода. Из закреплённого окна при скрытом Hatch — сначала показать Hatch.
    private func fromPreview(_ preview: ClipPreviewWindow, _ insert: @escaping () -> Void) {
        if previews.isTransient(preview) { insert(); return }
        NotificationCenter.default.post(name: .hatchRequestShow, object: nil)
        // показ сбрасывает режимы панели — вставляем после него
        DispatchQueue.main.async { insert() }
    }

    private func deletePreviewClip(_ preview: ClipPreviewWindow) {
        if let clip = clip(of: preview) { deleteClip(clip) } else { previews.close(preview) }
    }

    private var previewClip: Clip? {
        previewClipID.flatMap { id in clipboard.clips.first { $0.id == id } }
    }

    /// ⌘1 в режиме буфера: открыть или закрыть выбранную запись крупно — картинку или текст.
    private func togglePreview() -> Bool {
        if previewClipID != nil { previewClipID = nil; return true }
        guard let clip = selectedClip else { return false }
        previewClipID = clip.id
        return true
    }

    /// Фрагмент для клавиш действий: открытая крупно картинка, иначе выбранная строка.
    private var activeClip: Clip? { previewClip ?? selectedClip }

    /// ⌘S: закрепить или открепить. Строка переезжает между группами — выбор идёт за ней.
    private func togglePin(_ clip: Clip) {
        clipboard.togglePin(clip)
        let clips = visibleClips
        clipSelection = clips.firstIndex { $0.id == clip.id } ?? min(clipSelection, max(clips.count - 1, 0))
    }

    private func deleteClip(_ clip: Clip) {
        if previewClipID == clip.id { previewClipID = nil }
        previews.closeAll(clipID: clip.id)
        clipboard.remove(clip)
        clipSelection = min(clipSelection, max(visibleClips.count - 1, 0))
        // как у очистки буфера: 5 секунд можно вернуть (файл картинки удаляется не сразу)
        showToast(L.t("clip_deleted", lang), undo: { clipboard.restore([clip]) })
    }

    /// Корзина и ⌃L в режиме буфера: незакреплённые убираются, 5 секунд можно вернуть.
    private func clearClipboard() {
        let removed = clipboard.clearUnpinned()
        guard !removed.isEmpty else { NSSound.beep(); return }
        clipSelection = 0
        showToast(L.t("clip_cleared", lang), undo: { clipboard.restore(removed) })
    }

    private func hidePanel() {
        NotificationCenter.default.post(name: .hatchRequestHide, object: nil)
    }

    /// ⌘4: поле ищет по скопированному; повторно или Esc — обратно к команде, набранное на месте.
    private func toggleClipboard() {
        if clipboardMode { exitClipboard(); return }
        guard settings.clipboardEnabled else { NSSound.beep(); return }
        if searchMode { exitSearch() }
        favoritesOpen = false
        clipboardQuery = ""
        clipSelection = 0
        clipKind = .all
        withAnimation(.easeOut(duration: 0.2)) { clipboardMode = true }
        inputFocused = true
        reclaimInputFocus { clipboardMode && !showSettings }
    }

    /// Список с прокруткой, появляясь при смене режима, забирает клавиатуру у поля, когда в macOS
    /// включена навигация с клавиатуры: она падает на само окно, а SwiftUI считает, что поле
    /// по-прежнему в фокусе, — `inputFocused = true` ничего не меняет. Поэтому снимаем фокус и ставим
    /// заново. Случается не сразу (миниатюры догружаются), отсюда несколько коротких попыток.
    /// Клавиатуру, которую взял кто-то другой (просмотр, настройки), не трогаем: только ничью.
    private func reclaimInputFocus(attempts: Int = 10, while wanted: @escaping () -> Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            guard wanted(), let window = NSApp.keyWindow as? LauncherPanel else { return }
            let responder = window.firstResponder
            if responder === window || responder === window.contentView {
                inputFocused = false
                DispatchQueue.main.async { if wanted() { inputFocused = true } }
            }
            if attempts > 1 { reclaimInputFocus(attempts: attempts - 1, while: wanted) }
        }
    }

    private func exitClipboard() {
        guard clipboardMode else { return }
        previewClipID = nil
        clipboardQuery = ""
        withAnimation(.easeOut(duration: 0.2)) { clipboardMode = false }
        if expandedID == nil {
            inputFocused = true
            reclaimInputFocus { !clipboardMode && expandedID == nil && !showSettings }
        }
    }

    /// Enter или клик: фрагмент снова в буфере, панель скрывается — остаётся ⌘V там, где вы были.
    private func copyClip(_ clip: Clip?) {
        guard let clip = clip ?? selectedClip else { NSSound.beep(); return }
        if let image = clip.image {
            guard let url = clipboard.imageURL(clip), Clipboard.copyImage(at: url) else { NSSound.beep(); return }
            showToast(String(format: L.t("clip_image_copied", lang), "\(image.width) × \(image.height)"))
        } else {
            Clipboard.copy(clip.text)
            let line = clip.text.split(separator: "\n").first.map(String.init) ?? clip.text
            showToast(String(format: L.t("clip_copied", lang), line))
        }
        exitClipboard()
        NotificationCenter.default.post(name: .hatchRequestHide, object: nil)
    }

    /// ⌘V в просмотре: выделенный на картинке текст — в поле ввода как команда.
    private func insertText(_ selected: String) {
        guard !selected.isEmpty else { NSSound.beep(); return }
        previewClipID = nil
        exitClipboard()
        text = selected.split(whereSeparator: \.isNewline).joined(separator: " ")
        inputFocused = true
    }

    /// ⌘Enter: фрагмент — в поле ввода как команда (переводы строк — пробелами: поле однострочное).
    private func insertClip(_ chosen: Clip? = nil) {
        guard let clip = chosen ?? selectedClip else { NSSound.beep(); return }
        previewClipID = nil
        exitClipboard()
        if clip.isImage, let url = clipboard.imageURL(clip) {
            insertPath(url)
            return
        }
        text = clip.text.split(whereSeparator: \.isNewline).joined(separator: " ")
        inputFocused = true
    }

    /// Картинка — путём к файлу, готовым для команды: `open …`, `cp … .`, `curl -F file=@…`.
    private func insertPath(_ url: URL) {
        previewClipID = nil
        exitClipboard()
        text = Self.shellEscaped(ShellCompletionEngine.normalizeHomePath(url.path))
        inputFocused = true
    }

    /// Путь для шелла: пробелы и спецсимволы — через `\`, `~` в начале остаётся (раскрывается шеллом).
    static func shellEscaped(_ path: String) -> String {
        let special = Set(" '\"\\()[]{}&;<>|*?$!#`")
        return String(path.flatMap { special.contains($0) ? ["\\", $0] : [$0] })
    }

    // MARK: - Приложения и калькулятор

    private func resolveQuickAction(_ text: String) -> QuickAction? {
        var resolver = settings.quickActionResolver(apps: AppCatalog.shared.apps)
        let index = CommandIndex.shared(for: settings.shellPath)
        resolver.isCommand = { index.isKnown($0) }
        return resolver.resolve(text, directory: settings.currentDirectory)
    }

    // MARK: - Команды нет

    /// Похожие имена для строки «Команды gti нет. Похоже: git».
    private var missingSuggestions: [String] {
        guard let missing = runner.missingCommand else { return [] }
        if let cached = missingSuggestionsCache, cached.word == missing.word { return cached.list }
        return CommandNotFound.suggestions(for: missing.word,
                                           commands: CommandIndex.shared(for: settings.shellPath).allCommands,
                                           apps: appNames)
    }

    /// Имена и алиасы приложений: по началу подсказываются только они.
    private var appNames: [String] {
        let apps = AppCatalog.shared.apps
        return apps.flatMap(\.names) + settings.appAliases.keys.filter { alias in
            apps.contains { $0.identifier == settings.appAliases[alias] }
        }
    }

    /// Строка в поле с первым похожим вместо опечатки — её подставит Tab.
    private var missingFix: String? {
        guard let missing = runner.missingCommand, text == missing.command,
              let first = missingSuggestions.first else { return nil }
        return CommandNotFound.replacingFirstWord(in: missing.command, with: first)
    }

    /// Enter открыл приложение или скопировал результат расчёта: в историю не попадает,
    /// панель скрывается. false — это команда.
    private func performQuickAction(_ command: String) -> Bool {
        guard let action = resolveQuickAction(command), action.handlesEnter else { return false }
        action.perform()
        // деление на ноль: звук, набранное остаётся исправить
        if action == .divisionByZero { return true }
        text = ""
        if case .calculate(let value, let separator) = action {
            showToast(String(format: L.t("calc_copied", lang), Calculator.display(value, separator: separator)))
        }
        NotificationCenter.default.post(name: .hatchRequestHide, object: nil)
        return true
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
            // идёт запись хоткея в настройках — любое сочетание (⌘W, ⌘Q, Esc) принадлежит записи
            if HotKeyCapsField.isRecording { return event }
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            // окно просмотра картинки: свои клавиши; закреплённое — само по себе, клавиши панели не для него
            // ⌃Tab / ⌃⇧Tab в настройках — соседний раздел
            if showSettings, event.keyCode == 48, modifiers == .control || modifiers == [.control, .shift] {
                NotificationCenter.default.post(name: .hatchSettingsStep, object: modifiers.contains(.shift) ? -1 : 1)
                return nil
            }
            if let preview = previews.window(for: event.window) {
                // стрелки — окну (прокрутка текста), а не списку под ним
                if Self.arrowKeyCodes.contains(event.keyCode) { return event }
                if handlePreviewKey(event.keyCode, modifiers, preview) { return nil }
                if !previews.isTransient(preview) { return event }
            }
            if Self.arrowKeyCodes.contains(event.keyCode),
               modifiers.subtracting([.function, .numericPad]).isEmpty {
                return routeArrowToHistory(event) ? nil : event
            }
            // дерево папок — сочетание из настроек (по умолчанию ⌘1), пока открыта панель
            if !showSettings, !clipboardMode,
               KeyChordFormatter.matches(settings.folderTreeShortcut, modifiers: modifiers, keyCode: event.keyCode,
                                         characters: event.charactersIgnoringModifiers) {
                favoritesOpen = false
                folderTreeRequest += 1
                return nil
            }
            switch (event.keyCode, modifiers) {
            // Esc в самих настройках; во вложенном окне (выбор приложения) — сначала его фильтр и само окно
            case (53, []) where showSettings && !HotKeyCapsField.isRecording && !(event.window?.parent is PopupPanel):
                closeSettings()
                return nil
            case (53, []) where !showSettings && event.window is LauncherPanel:
                return escape(event) ? nil : event
            case (21, .command) where !showSettings:
                toggleClipboard()
                return nil
            case (36, .command) where clipboardMode && !showSettings:
                insertClip(activeClip)
                return nil
            case (1, .command) where clipboardMode && !showSettings:
                // ⌘S — закрепить или открепить выбранный фрагмент (в окне просмотра ⌘S закрепляет окно)
                if let clip = activeClip { togglePin(clip) } else { NSSound.beep() }
                return nil
            case (18, .command) where clipboardMode && !showSettings:
                // ⌘1 в буфере — картинка крупно (дерево папок здесь не нужно); не картинка — звук
                if !togglePreview() { NSSound.beep() }
                return nil
            case (48, []) where clipboardMode && !showSettings, (48, .shift) where clipboardMode && !showSettings:
                // Tab и ⇧Tab в буфере — следующий и предыдущий тип фрагментов
                clipKind = clipKind.next(modifiers.contains(.shift) ? -1 : 1)
                clipSelection = 0
                return nil
            case (14, .command) where !showSettings:
                // ⌘E в раскрытом выводе — «искать выделенное», его не трогаем
                if Self.textViewHasFocus(event) { return event }
                favoritesOpen.toggle()
                return nil
            case (2, .command) where !showSettings:
                toggleFavoriteDirectory(settings.currentDirectory)
                return nil
            case (37, .control) where clipboardMode && !showSettings:
                clearClipboard()
                return nil
            case (15, [.command, .shift]) where clipboardMode && !showSettings:
                // ⇧⌘R — у выбранной записи: форматировать или как есть (⌘R — повтор команды)
                if let clip = selectedClip, clipSyntax(clip) != nil { toggleClipFormat(clip) } else { NSSound.beep() }
                return nil
            case (15, .command) where !showSettings && !clipboardMode:
                // ⌘R — повторить команду раскрытого или выбранного стрелками блока, как «обновить» в macOS
                guard let id = expandedID ?? navigator.selectedID,
                      let session = sessionStore.filteredSessions.first(where: { $0.id == id }) else {
                    NSSound.beep()
                    return nil
                }
                rerun(session)
                return nil
            case (8, .command) where !showSettings && !clipboardMode && expandedID == nil && navigator.isNavigating
                && ((event.window?.firstResponder as? NSTextView)?.selectedRange().length ?? 0) == 0:
                // ⌘C у выбранного стрелками блока (в поле ничего не выделено) — скопировать его вывод
                if let id = navigator.selectedID, let session = sessionStore.filteredSessions.first(where: { $0.id == id }) {
                    copyOutput(session)
                } else {
                    NSSound.beep()
                }
                return nil
            case (1, .command) where !showSettings && !clipboardMode && navigator.isNavigating:
                // ⌘S — закрепить или открепить выбранный стрелками блок
                if let id = navigator.selectedID { sessionStore.togglePin(id: id) }
                return nil
            case (15, [.command, .shift]) where !showSettings && !searchMode:
                // ⇧⌘R — у раскрытого, выбранного стрелками или последнего блока
                let id = expandedID ?? navigator.selectedID ?? sessionStore.filteredSessions.first?.id
                if let session = sessionStore.filteredSessions.first(where: { $0.id == id }), blockSyntax(session) != nil {
                    toggleBlockFormat(session)
                } else {
                    NSSound.beep()
                }
                return nil
            case (51, .command) where clipboardMode && !showSettings:
                // ⌘⌫ в буфере — удалить выбранный фрагмент (или открытый крупно)
                if let clip = activeClip { deleteClip(clip) } else { NSSound.beep() }
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
                // ⌘Q только скрывает панель: случайное нажатие не останавливает Hatch и его команды.
                // Выйти — «Выйти из Hatch» в настройках или значок в строке меню.
                hidePanel()
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
            case (13, .command) where expandedID != nil && event.window is LauncherPanel:
                // раскрытый блок ⌘W сворачивает всегда, и живой терминал тоже (Esc там — программе)
                collapse()
                return nil
            case (13, .command):
                // ⌘W — то же, что Esc: закрыть верхний слой (окно, настройки, режим), иначе скрыть панель
                Self.sendEscape(to: event.window)
                return nil
            case (44, .command) where !showSettings:
                // ⌘/ — шпаргалка по клавишам режима; повторно — закрыть
                favoritesOpen = false
                keysOpen.toggle()
                return nil
            case (43, .command):
                // ⌘, — настройки, как в приложениях macOS; повторно — закрыть
                if showSettings { closeSettings() } else { openSettings() }
                return nil
            case (8, .control):
                return interruptByKeyboard(event) ? nil : event
            default:
                return event
            }
        }
    }

    // MARK: - Esc и ⌘W

    /// Esc в панели закрывает верхний слой, по одному за нажатие; закрывать нечего — скрывает панель
    /// (набранное остаётся). ⌘W делает то же самое. Всплывающие окна, настройки и диалоги
    /// закрываются своим Esc раньше, в своих окнах. false — нажатие идёт дальше как обычно.
    private func escape(_ event: NSEvent) -> Bool {
        // варианты TAB и правка шага конвейера — Esc у поля: вернуть набранное
        if completionMenuOpen { return false }
        if let editor = event.window?.firstResponder as? NSTextView, editor.isFieldEditor, !inputFocused { return false }
        // раскрытый блок: в живом терминале Esc нужен программе (vim, ssh); иначе — свернуть
        if let session = expandedSession {
            if let terminal = runner.terminal(for: session.id), event.window?.firstResponder === terminal.view {
                return false
            }
            collapse()
            return true
        }
        if searchMode { exitSearch(); return true }
        if clipboardMode { exitClipboard(); return true }
        if runner.missingCommand != nil { runner.dismissMissingCommand(); return true }
        hidePanel()
        return true
    }

    /// ⌘W как Esc: нажатие Esc уходит в то же окно (всплывающее, настройки, диалог или панель).
    private static func sendEscape(to window: NSWindow?) {
        guard let window,
              let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
                                            timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: window.windowNumber, context: nil,
                                            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}",
                                            isARepeat: false, keyCode: 53) else { return }
        // после текущего нажатия: так Esc проходит обычный путь, через мониторы клавиш
        DispatchQueue.main.async { NSApp.sendEvent(escape) }
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

    /// Формат вывода завершённой команды: JSON, YAML, XML (вывод с цветами самой программы — как есть).
    private func blockSyntax(_ session: Session) -> BlockSyntax? {
        guard session.state.isTerminal, session.outputDropped == nil, !session.output.isEmpty,
              !(session.outputANSI.map(ANSIText.hasColor) ?? false) else { return nil }
        var options = settings.syntaxOptions
        options.allowed.formIntersection([.json, .jsonLines, .yaml, .xml])
        let syntax = SyntaxService.shared
        guard let kind = syntax.kind(of: session.output, options: options) else { return nil }
        let on = session.formatted ?? settings.formatsByDefault(command: session.command)
        guard on else { return BlockSyntax(label: kind.label(code: nil), on: false, ansi: nil, text: nil) }
        return BlockSyntax(label: kind.label(code: nil), on: true,
                           ansi: syntax.renderedANSI(session.output, kind: kind, options: options),
                           text: syntax.rendered(session.output, kind: kind, mode: .full, options: options)?.text)
    }

    /// {} у блока и ⌘R: форматировать вывод или показывать как есть (запоминается в блоке).
    private func toggleBlockFormat(_ session: Session) {
        let on = !(session.formatted ?? settings.formatsByDefault(command: session.command))
        sessionStore.update(id: session.id) { $0.formatted = on }
    }

    /// Без цвета; у работающей команды — весь экран, а не превью.
    private func copyOutput(_ session: Session) {
        // отформатированный вывод копируется таким, каким виден
        if let syntax = blockSyntax(session), syntax.on, let shown = syntax.text {
            Clipboard.copy(shown)
        } else {
            Clipboard.copy(runner.terminal(for: session.id)?.snapshot().plain ?? session.output)
        }
        showToast(String(format: L.t("output_copied", lang), session.command))
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
    /// Формат вывода блока (JSON, YAML, XML) и {} — форматировать или как есть.
    var blockSyntax: (Session) -> BlockSyntax? = { _ in nil }
    var onToggleFormat: (Session) -> Void = { _ in }
    /// Поиск: что подсветить в командах и выводе (у вывода — только строки с совпадением).
    var highlight: String?
    /// Поиск ничего не нашёл в истории — сколько нашлось бы в буфере.
    var clipboardMatches = 0

    var body: some View {
        if sessionStore.filteredSessions.isEmpty {
            if sessionStore.filterText.isEmpty {
                EmptyHistoryView(lang: lang)
            } else {
                VStack(spacing: 6) {
                    Text(L.t("search_empty", lang))
                    // искомое могло быть скопировано, а не выполнено
                    if clipboardMatches > 0 {
                        Text(String(format: L.t("search_in_clipboard", lang), clipboardMatches))
                            .foregroundStyle(Tactile.clip)
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
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
                                         stageHistory: stageHistory,
                                         syntax: blockSyntax(session),
                                         onToggleFormat: { onToggleFormat(session) },
                                         highlight: highlight)
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
    /// Вывод — JSON, YAML или XML: отформатирован и подсвечен (кнопка {} — как есть).
    var syntax: BlockSyntax?
    var onToggleFormat: () -> Void = {}
    /// Поиск: подсветить совпадения в команде и показать только строки вывода с ними.
    var highlight: String?
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
                Text(Self.marked(AttributedString(session.command), highlight))
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
        // выбран стрелками и не под мышью — кнопки с клавишами, как у строк буфера: клавиши видны там,
        // где ими пользуются
        let keyed = isSelected && !hovered && !isExpanded && session.state.isTerminal
        let actions = keyed ? blockActions.filter { $0.icon != .rerun && $0.icon != .copy } : blockActions
        return ZStack(alignment: .trailing) {
            StatusCapsule(status: BlockStatus(session), lang: lang)
                .rotation3DEffect(.degrees(showActions ? 75 : 0), axis: (1, 0, 0), anchor: .top, perspective: 0.5)
                .offset(y: showActions ? -8 : 0)
                .opacity(showActions ? 0 : 1)
                .animation(.spring(response: 0.38, dampingFraction: 0.8), value: showActions)
            HStack(spacing: 4) {
                if keyed {
                    keyButton("⌘C", L.t("block_copy_output", lang), perform: onCopy)
                    keyButton("⌘R", L.t("rerun_short", lang), perform: onRerun)
                }
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

    /// Кнопка-колпачок «клавиша + подпись» — то же, что сочетание (как у строк буфера).
    private func keyButton(_ key: String, _ title: String, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            HStack(spacing: 5) {
                KeyHint(key: key)
                Text(title)
                    .font(.system(size: 11.5))
                    .foregroundStyle(Tactile.keyText)
                    .lineLimit(1)
            }
            .padding(.leading, 4)
            .padding(.trailing, 8)
            .frame(height: LauncherMetrics.blockButton)
            .contentShape(Rectangle())
        }
        .buttonStyle(KeyCapButtonStyle(cornerRadius: 7))
        .fixedSize()
    }

    private struct BlockAction {
        let icon: KeyIcon
        var color: Color? = nil
        let help: String
        let run: () -> Void
    }

    /// Что показывать: отформатированный вывод (цветами ANSI) или как есть.
    private var shownOutput: String {
        if let syntax, syntax.on, let ansi = syntax.ansi { return ansi }
        return session.outputANSI ?? session.output
    }

    private var shownIsANSI: Bool { session.outputANSI != nil || (syntax?.on == true && syntax?.ansi != nil) }

    private var blockActions: [BlockAction] {
        var list: [BlockAction] = []
        if let syntax {
            list.append(BlockAction(icon: .braces, color: syntax.on ? Tactile.clip : nil,
                                    help: "\(syntax.label) · " + L.t("format_toggle_help", lang), run: onToggleFormat))
        }
        list += [
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
                // «фильтр»: просто «+» не говорил, что он добавит
                // подпись — у блока под мышью и выбранного, у остальных значок: список не пестрит
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 10, weight: .semibold))
                    if hovered || isSelected {
                        Text(L.t("filter", lang))
                            .font(.system(size: 11.5))
                    }
                }
                    .foregroundStyle(Tactile.keyText)
                    .frame(minWidth: LauncherMetrics.blockButton)
                    .padding(.horizontal, hovered || isSelected ? 7 : 0)
                    .frame(height: LauncherMetrics.blockButton)
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
            shownOutput,
            font: NSFont.monospacedSystemFont(ofSize: LauncherMetrics.outputFontSize, weight: .regular)))
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .sunken(RoundedRectangle(cornerRadius: 8), fill: Tactile.field)
    }

    /// Свёрнутый вывод: начало, «скрыто N строк» с кнопкой раскрыть, конец.
    /// Длинные строки переносятся по словам; лимит — в экранных строках.
    private var outputPreview: some View {
        let source = shownOutput
        let columns = previewColumns
        let limit = outputLines + 1
        let all = source.components(separatedBy: "\n")
        // поиск: только строки с совпадением, как grep, — видно, почему блок нашёлся
        let found = highlight.flatMap { query in
            query.isEmpty ? nil : all.filter { plain($0).range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        } ?? []
        let layout = OutputPreview.layout(lines: found.isEmpty ? all : found,
                                          gap: found.isEmpty ? session.outputGap : nil, maxLines: outputLines,
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
        let text = shownIsANSI ? ANSIText.attributed(line) : AttributedString(line)
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
            outputRow(shownIsANSI ? ANSIText.attributed(line) : AttributedString(line))
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

    /// Видимый текст строки вывода (без ANSI-кодов).
    private func plain(_ line: String) -> String {
        shownIsANSI ? String(ANSIText.attributed(line).characters) : line
    }

    /// Совпадения с запросом поиска — подсвечены, как в списках Hatch.
    static func marked(_ text: AttributedString, _ query: String?) -> AttributedString {
        guard let query, !query.isEmpty else { return text }
        var result = text
        let plain = String(result.characters)
        var range = plain.startIndex..<plain.endIndex
        while let found = plain.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], range: range) {
            let from = plain.distance(from: plain.startIndex, to: found.lowerBound)
            let length = plain.distance(from: found.lowerBound, to: found.upperBound)
            let chars = result.characters
            let lower = chars.index(chars.startIndex, offsetBy: from)
            let upper = chars.index(lower, offsetBy: length)
            result[lower..<upper].backgroundColor = Tactile.search.opacity(0.45)
            result[lower..<upper].foregroundColor = .white
            range = found.upperBound..<plain.endIndex
        }
        return result
    }

    private func outputRow(_ text: AttributedString) -> some View {
        Text(Self.marked(text, highlight))
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

/// Что делает поле ввода: запускает команду, ищет по истории (⌘F) или по буферу обмена (⌘4).
enum InputMode {
    case command
    case search
    case clipboard
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
    /// Что сделает Enter вместо команды: открыть приложение, скопировать результат (подпись справа).
    var quickAction: (String) -> QuickAction? = { _ in nil }
    /// После «Команды нет»: исправленная строка, которую подставит Tab («git status»).
    var fix: String?
    /// Последний запуск не нашёл команду — рамка поля красная.
    var alert = false
    /// Поле в фокусе — светится рамка.
    var isFocused = false
    /// Список вариантов TAB открылся или закрылся.
    var onCompletionMenu: (Bool) -> Void = { _ in }
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
                Image(systemName: mode == .clipboard ? "doc.on.clipboard" : "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(modeColor)
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

            if let ghost = historyGhost ?? appGhost {
                Text(ghost)
                    .font(font)
                    .foregroundStyle(.tertiary)
                    .offset(x: typedWidth)
                    .allowsHitTesting(false)
            }

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(font)
        }
        // исправление опечатки показывает строка «Команды … нет» под полем — в поле второй раз не нужно
        // (Tab по-прежнему подставляет его)
        if fix == nil, let quick, showsQuickLabel {
            QuickActionLabel(action: quick, lang: lang)
        }
        if let trailing { trailing }
        }
        .padding(.leading, 14)
        .padding(.trailing, trailing == nil ? 14 : 8)
        .padding(.vertical, 10)
        .sunken(RoundedRectangle(cornerRadius: LauncherMetrics.innerRadius), fill: Tactile.field)
        // в поиске рамка другого цвета и видна всегда: сразу понятно, в каком режиме поле
        .selectionRing(cornerRadius: LauncherMetrics.innerRadius, visible: isFocused || searching || alert,
                       color: searching ? modeColor : alert ? Tactile.red : Tactile.accent)
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
        .onChange(of: completer.menu != nil) { _, open in onCompletionMenu(open) }
        .onSubmit {
            // однозначное начало имени приложения: Enter дописывает, повторный — открывает
            if let completion = enterCompletion {
                text = completion
                return
            }
            onSubmit(text)
        }
        .onChange(of: text) { _, newValue in
            if settingText { settingText = false; return }
            // пользователь печатает: выбранный вариант принят, перебор окончен
            completer.reset()
            onEdit()
            // поиск не дополняет пути и не подсказывает команды из истории
            if !searching { refresh(newValue) }
        }
    }

    /// Поле не для команды (поиск, буфер): без дополнения, подсказок и подписи справа.
    private var searching: Bool { mode != .command }

    private var modeColor: Color { mode == .clipboard ? Tactile.clip : Tactile.search }

    private var placeholder: String {
        switch mode {
        case .command: "Введите команду…"
        case .search: L.t("search_placeholder", lang)
        case .clipboard: L.t("clip_placeholder", lang)
        }
    }

    private var quick: QuickAction? { searching ? nil : quickAction(text) }

    /// Подсказка приложения по набранному началу: «saf» → «safari».
    private var appSuggestion: AppSuggestion? {
        guard fix == nil, completer.menu == nil, case .suggestApp(let suggestion) = quick,
              suggestion.completion.hasPrefix(text), suggestion.completion.count > text.count else { return nil }
        return suggestion
    }

    private var appCompletion: String? { appSuggestion?.completion }

    /// Остаток имени приложения — серым, если нет подсказки из истории.
    private var appGhost: String? {
        guard historyGhost == nil, let completion = appCompletion else { return nil }
        return String(completion.dropFirst(text.count))
    }

    /// Что Enter допишет вместо запуска: вариант один и виден серым.
    private var enterCompletion: String? {
        guard appGhost != nil, let suggestion = appSuggestion, suggestion.completesOnEnter else { return nil }
        return suggestion.completion
    }

    /// Подпись подсказки приложения — только когда её имя видно серым (иначе Tab сделает другое).
    private var showsQuickLabel: Bool {
        if case .suggestApp = quick { return appGhost != nil }
        return true
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
        // после «Команды нет»: Tab подставляет похожее имя («gti» → «git»)
        if direction == .forward, completer.menu == nil, let fix {
            text = fix
            return .handled
        }
        // серым видно имя приложения — TAB дописывает его, как в подписи «⇥ Safari»
        if direction == .forward, appGhost != nil, let completion = appCompletion {
            text = completion
            return .handled
        }
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
        if appGhost != nil, let completion = appCompletion {
            text = completion
            return .handled
        }
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
        Self.claimKeyboard(terminalView, attempts: 8)
        return container
    }

    /// Клавиатура — терминалу блока, сразу после раскрытия. Поле ввода при раскрытии теряет фокус,
    /// и SwiftUI, снимая его, может сделать это уже после нас: клавиатура падала на само окно,
    /// и в терминал приходилось кликать. Поэтому несколько коротких попыток, пока клавиатура ничья.
    /// Отнимать её у того, кто взял её сам (клик в поле ввода), не будем.
    private static func claimKeyboard(_ view: NSView, attempts: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak view] in
            guard let view, let window = view.window else { return }
            let responder = window.firstResponder
            if responder === view { return }
            if responder == nil || responder === window {
                window.makeFirstResponder(view)
            }
            if attempts > 1 { claimKeyboard(view, attempts: attempts - 1) }
        }
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
