# Разработка Hatch

## Требования

- macOS 26 (Tahoe) или новее
- Xcode 26+ и Metal Toolchain: `xcodebuild -downloadComponent MetalToolchain`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — проект генерируется из `project.yml`
- [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.18.0 — Swift Package, подтягивается сам

## Сборка и запуск

```bash
brew install xcodegen
```

```bash
xcodegen generate
```

```bash
xcodebuild build -scheme Hatch -destination 'platform=macOS' -derivedDataPath build
```

```bash
open build/Build/Products/Debug/Hatch.app
```

Или откройте `Hatch.xcodeproj` в Xcode и запустите схему **Hatch**. Новая сборка при запуске сама
закрывает уже работающий Hatch.

## Тесты

```bash
xcodebuild test -scheme Hatch -destination 'platform=macOS' -derivedDataPath build
```

- Запускайте тесты в отдельной папке сборки: `xcodebuild test` закрывает Hatch, собранный в той же папке.
- Под тестами Hatch только хост: без панели, хоткея, значка и настоящей истории.
- Тесты не зависят от `~/.zshrc`: `ZDOTDIR` указывает на пустую папку.
- Самопроверка сценариев без XCTest: `build/Build/Products/Debug/Hatch.app/Contents/MacOS/Hatch --selftest`

## Выпуск версии

```bash
git tag v0.2.0 && git push origin v0.2.0
```

GitHub Actions (`.github/workflows/release.yml`) прогоняет тесты, собирает Hatch под Apple Silicon
и Intel с ad-hoc подписью и выкладывает `Hatch-<версия>.zip` в Releases. Версия приложения берётся из тега.

## Демо-ролик и значок

Ролик в README и значок приложения нарисованы HTML-макетами в `docs/demo/`:
`hatch-demo.html` — ролик (кнопка «Старт», с `?rec` в адресе стартует сам), `icon.html` — значок.

```bash
npm i --no-save playwright && npx playwright install chromium
```

```bash
node docs/demo/record.js
```

Скрипт перезаписывает `docs/media/demo.mp4`, `demo.gif` и `icon-1024.png` (нужен `ffmpeg`).
Значки приложения разных размеров — в `Hatch/Assets.xcassets/AppIcon.appiconset`, нарезаются
из `icon-1024.png` через `sips -z`.

## Права macOS

- **Уведомления** — о завершении долгих команд, запрос при первом запуске.
- **Доступ к папкам** («Рабочий стол», «Документы») — macOS спросит, когда команда или `~/.zshrc`
  впервые обратится к защищённой папке. Пока запрос не подтверждён, команда ждёт.
- **Буфер обмена** — Hatch раз в полсекунды сверяет счётчик изменений буфера и читает его после
  копирования. История лежит в `~/Library/Application Support/Hatch/clipboard.json`, картинки — PNG
  в `clipboard-images/` рядом (права 0600). Текст на картинках распознаётся локально (Vision), без сети.
- Сборка подписана ad-hoc, поэтому после пересборки macOS может спросить разрешения заново.

## Перенос с MacUtils

Раньше приложение называлось MacUtils. При первом запуске Hatch переносит историю
(`~/Library/Application Support/MacUtils/` → `…/Hatch/`) и настройки; существующие данные Hatch
не перезаписываются.

## Устройство

| Файл | Назначение |
|---|---|
| `AppDelegate.swift`, `AppMain.swift`, `SingleInstance.swift` | запуск, строка меню, хоткей, один экземпляр |
| `FloatingWindowController.swift`, `PanelPlacement.swift` | панель: показ, скрытие, позиция |
| `LauncherViews.swift` | интерфейс: поле ввода, история блоками, раскрытие |
| `LayersStyle.swift`, `KeyIcons.swift`, `SettingsView.swift` | стиль: палитра, колпачки, утопленные поверхности, иконки, настройки |
| `PopupPanel.swift`, `FolderMenuView.swift`, `FavoritesView.swift` | свои всплывающие окна и меню, избранное |
| `ProcessRunner.swift` | команды в PTY, `cd`, перезапуск, Ctrl-C, конвейер |
| `InteractiveTerminal.swift` | терминал сессии на SwiftTerm |
| `TerminalSnapshot.swift`, `ANSIText.swift` | экран терминала → текст с цветом и обратно |
| `OutputPreview.swift`, `OutputPipeline.swift` | превью вывода, шаги конвейера |
| `ShellCompletionEngine.swift`, `TabCompleter.swift` | автодополнение и TAB как в zsh |
| `HistoryNavigator.swift`, `HistorySuggestion.swift` | ↑/↓ по истории, серая подсказка |
| `QuickActions.swift`, `QuickActionLabel.swift`, `Calculator.swift` | приложения и калькулятор в поле ввода: список приложений, разбор строки, подпись справа |
| `CommandNotFound.swift` | опечатка в имени команды: распознать «command not found», похожие имена |
| `ClipboardHistory.swift`, `ClipboardView.swift`, `TextRecognizer.swift` | буфер обмена (⌘4): слежение за копированием, хранение текста и картинок, список, распознавание текста на картинках (Vision) |
| `Screenshots.swift` | скриншоты по сочетанию: `screencapture -i`, стопка миниатюр справа внизу, занятость сочетания в macOS |
| `ClipPreviewWindow.swift` | окно просмотра картинки из буфера: шапка с подсказками, размер в пропорциях, закрепление поверх окон |
| `LiveTextImage.swift` | картинка с выделением текста на ней (Live Text, VisionKit) и меню правого клика |
| `DirectoryBreadcrumbsView.swift`, `FolderTreeView.swift`, `FolderTree.swift` | путь над полем ввода и дерево папок |
| `KeyboardLayoutSwitcher.swift`, `HotKeyRecorder.swift` | латиница в поле ввода, запись сочетаний |
| `SessionStore.swift`, `HistoryStore.swift`, `SettingsStore.swift` | состояние и хранение |
| `LegacyMigration.swift` | перенос данных с имени MacUtils |

## Известные ограничения

- SwiftTerm закреплён на 1.18.0: с 1.19 в пакете есть плагин сборки, который нужно один раз
  подтвердить в Xcode («Trust & Enable»).
- Автодополнение не понимает пути с пробелами.
- Лимит истории из настроек пока не применяется: хранятся последние 50 завершённых сессий
  (закреплённые и активные — все).
- `~/.zshrc` не должен ждать ввода: вопрос из rc-файла остановит команду
  (автообновление oh-my-zsh для команд Hatch отключено).
