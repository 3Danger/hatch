<p align="center"><img src="docs/media/icon.png" width="128" alt="Hatch icon"></p>

<h1 align="center">Hatch</h1>

<p align="center"><b>A terminal one keystroke away.</b> Press <kbd>⌥</kbd><kbd>Space</kbd>, run a command, close it.</p>

<p align="center">
  <a href="https://github.com/3Danger/hatch/releases/latest"><b>Download for macOS</b></a> · macOS 26+ · free, MIT
</p>

<p align="center"><img src="docs/media/demo.gif" width="800" alt="Hatch: a command in the panel, a grep filter, the clipboard, screenshots with ⇧⌘4, the folder tree, apps and the calculator"></p>
<p align="center"><a href="docs/media/demo.mp4">Full-quality video</a></p>

## Why

You need one command, but a terminal means a separate window, tabs, and hunting for where you ran what.
Hatch slides over any app, runs the command in your shell and keeps the output in its history.
Close it and you are right back where you were.

## Features

- **Your shell.** zsh or bash with your `~/.zshrc`: aliases, functions, colors. `ssh`, `vim` and `htop` open right in the panel.
- **History as blocks.** Every command is a block with its output and status: rerun, copy, pin.
- **Filters without rerunning.** The “+” on a block adds `grep`, `sort` or `jq` to the saved output. The command itself does not run again.
- **Folders from the keyboard.** <kbd>⌘T</kbd> opens the folder tree, ★ holds favorite folders and commands.
- **Search.** <kbd>⌘2</kbd> searches all commands and their output.
- **zsh-style completion.** TAB and suggestions from history, with no lag.
- **Clipboard.** <kbd>⌘3</kbd> shows everything you copied, with search, including screenshots and the text on them. Passwords from password managers are never saved.
- **Formatting.** JSON, SQL, YAML and XML in the clipboard and in command output, indented and highlighted; a `{}` button on every item and block.
- **Screenshots.** <kbd>⇧⌘4</kbd> puts a screen area straight into the clipboard and Hatch history; the thumbnail in the bottom-right corner opens it full size.
- **Apps and a calculator, like Spotlight.** `saf` and Enter opens Safari, `code .` opens the current folder in VS Code. `(1200-150)/3` shows 350 right away, Enter copies the result.

## Installation

1. Download `Hatch-<version>.zip` from [Releases](https://github.com/3Danger/hatch/releases/latest) and move `Hatch.app` to Applications.
2. Hatch is not signed with an Apple certificate, so macOS blocks the first launch. Allow it in System Settings → Privacy & Security → Open Anyway, or with this command:

```bash
xattr -dr com.apple.quarantine /Applications/Hatch.app
```

3. Press <kbd>⌥</kbd><kbd>Space</kbd>. Hatch lives in the menu bar, not in the Dock.

macOS will ask for permission to send notifications (when long commands finish) and to access folders the first time a command touches them.

## Main shortcuts

| Keys | What it does |
|---|---|
| <kbd>⌥</kbd><kbd>Space</kbd> | show or hide Hatch (configurable) |
| <kbd>Enter</kbd> · <kbd>Tab</kbd> | run the command · complete |
| <kbd>↑</kbd> <kbd>↓</kbd> | browse command history |
| <kbd>⌘1</kbd> · <kbd>⌘2</kbd> · <kbd>⌘3</kbd> | modes: commands · search commands and output · clipboard; the key of the current mode goes back to commands |
| <kbd>⌘T</kbd> | folder tree (configurable) |
| <kbd>⌘E</kbd> · <kbd>⌘D</kbd> | favorites · add the current folder to favorites |
| <kbd>⌃L</kbd> | clear finished blocks (can be undone) |
| <kbd>⌘/</kbd> | every shortcut of the current mode |

<details>
<summary><b>All shortcuts</b></summary>

| Keys | Where | What it does |
|---|---|---|
| ⌥Space (configurable) | anywhere | show or hide the panel |
| Enter | input field | run the command; with a hint on the right, open the app or copy the result |
| Tab · ⇧Tab | input field | complete; with several options, the common part first, then cycle forward and back |
| → | input field | accept the gray suggestion: from history or an app name (Tab completes it too) |
| ↑ / ↓ | panel | browse command history; the block of that command is selected |
| ⌘C · ⌘R · ⌘S · ⌘⌫ | selected block | copy its output · rerun it in the same block · pin it · delete it (can be undone) |
| ⌃C | expanded block | interrupt the command |
| ⌘1 · ⌘2 · ⌘3 | panel | commands · search history · clipboard; the current mode's key goes back to commands (⌘F and ⌘4 work too; inside expanded output ⌘F searches that output) |
| ⌘E | panel | favorites: folders and commands |
| ↑ / ↓ · ⌘↑ / ⌘↓ · Enter | favorites | select · move up or down (or drag with the mouse) · go to or run |
| letters · Backspace · Esc | lists | filter favorites, the folder tree and the app picker · delete a letter · clear the filter, a second Esc closes |
| ↑ / ↓ · Enter · ⌘C · ⌘Enter · Esc | clipboard | move between items · paste into the app you were in · only copy · insert into the input field · leave |
| Tab · ⇧Tab · ⌘Y | clipboard | next · previous item type · open the item full size |
| ⇧⌘R | clipboard, block | formatted or as is |
| ⌘S · ⌘⌫ · ⌃L | clipboard | pin · delete the selected item · clear the clipboard (pinned items stay); in a preview, ⌘S keeps the window on top of others |
| Esc · ⌘W | anywhere | close the top layer, one per press: popup or settings → TAB suggestions → expanded block → search or clipboard → the “No command” line; after that, hide the panel (typed text stays). In a live terminal (vim, ssh) Esc goes to the program, ⌘W collapses the block |
| ⌘T (configurable) | panel | folder tree at the current folder |
| ⌘D | panel | add the current folder to favorites or remove it |
| ⌃L | panel | clear finished blocks (like the `clear` command) |
| ⌘Q | panel | hide the panel; quit from settings or the menu bar icon |
| ⌘, | panel | settings and back |
| ⌘/ | panel | shortcut sheet for the current mode |
| ⌃Tab · ⌃⇧Tab | settings | next · previous section |
| ↑ / ↓ · Enter · Esc | search | move between found blocks · expand · leave |
| ↑ ↓ → ← · Space · letters | folder tree | move by row, expand and enter, go up · collapse · filter (parents of matches are dimmed) |
| Enter · ⌘← ⌘→ · Esc | folder tree | go there, like `cd` · neighboring folder of the path · close |

</details>

<details>
<summary><b>All features</b></summary>

**Commands**
- Run in your shell (`$SHELL`) in a real pseudo-terminal: colors, progress bars, `less`, `ssh`, <kbd>⌃C</kbd>.
- `cd` changes Hatch's folder, including in chains (`cd sub && ls`). The last folder is remembered.
- Interactive programs (`vim`, `top`, `ssh`, `man`, REPLs) open as a live terminal inside the block.
- A command waiting for input expands by itself: full-screen programs (`claude`, `htop`, `fzf`) behave like `vim`, questions (`Continue? [y/N]`, a `sudo` password) get a cursor for the answer. If the panel is hidden, you get a notification.
- The pager is off (`PAGER=cat`): `git log` prints in full.
- A notification when a long command (5 seconds or more) finishes while the panel is not focused.

**History**
- A block shows the command and, under it, the folder, the time (with the day for older blocks), how long it ran and its status; a running command shows a stopwatch. Long output shows the beginning and the end, the middle is collapsed.
- Compact history (on by default): output shows only on the latest, selected, pinned and running blocks, the rest take one line each. Old blocks without visible output take a single line: the command on the left, folder and status on the right. Turn it off in settings.
- Click a block to expand it: a finished one shows all its output, a running one shows the live terminal.
- A failed command is marked red with its exit code; one you stopped yourself (<kbd>⌃C</kbd>, Stop) is gray.
- <kbd>↑</kbd> <kbd>↓</kbd> select a block (its command goes to the input); the selected block shows its keys: <kbd>⌘C</kbd> copy output, <kbd>⌘R</kbd> rerun. Everything else (copy the command, filter, format, favorites, pin, delete) is in the “⋯” menu and on right-click on the block header.
- Rerun in the same block, pin, clear by levels. `clear` and <kbd>⌃L</kbd> remove finished blocks, with 5 seconds to undo.
- Above the input: the current folder (the middle of a long path folds into `…`) and the mode switcher — commands (<kbd>⌘1</kbd>), search (<kbd>⌘2</kbd>), clipboard (<kbd>⌘3</kbd>). Search highlights matches and shows only the matching lines of each block, with a count. If nothing is found but the clipboard has matches, a button (or <kbd>⌘3</kbd>) searches the clipboard for the same text.

**Pipeline**
- `grep`, `sort` and `jq` steps work on the saved output, so it is safe even for `rm`, `curl -X POST` and deploys.
- Steps show as chips you can edit or remove. Suggestions: recent steps, common filters, commands and files.

**Buttons**
- Hovering any button shows what it does and its key, in a small dark tip above it after a third of a second; moving to the next button shows its tip right away.

**Input**
- Completion for commands, aliases, files and folders, without starting a shell on every keystroke.
- A gray suggestion from history, like zsh-autosuggestions.
- The current folder is shown above the field. Click it or press <kbd>⌘T</kbd> for the folder tree, <kbd>⌘</kbd>-click to copy the path, right-click for the folder menu (favorites, Finder, editors, Share, recent folders).
- The Latin keyboard layout switches on in the field by itself and is restored when Hatch hides.

**Typos**
- A command with a typo in its name (`gti status`) does not stay in history: the text returns to the field with “No command gti. Did you mean: git” below it. Tab inserts the suggestion.
- If a command inside a script is not found, the block stays as usual.

**Clipboard**
- <kbd>⌘3</kbd> shows what you copied in any app while Hatch is running: newest first, with the app and time. Typing filters it.
- Above the field, instead of the path, a filter: all, text (and file paths), images, pinned; <kbd>Tab</kbd> and <kbd>⇧Tab</kbd> switch it.
- Enter or a double-click pastes the item into the app you were in before Hatch; <kbd>⌘C</kbd> only copies it. Pasting needs Accessibility access: until it is granted, Enter only copies and a line under the list offers to allow it. The setting “Enter pastes” turns this off. <kbd>⌘Enter</kbd> inserts the item into the input field. A click only selects a row; the selected and hovered rows show buttons for the same actions.
- An item shows up to 10 lines of its text (“Lines on an item” in settings); formatted JSON or SQL shows formatted, as in the preview. The preview window has a Copy all button in its header.
- Copying something again moves it to the top. Files from Finder are saved as paths.
- Each row has pin (<kbd>⌘S</kbd>) and delete. Pinned items stay grouped at the top and are never removed by clearing, age or the limit.
- <kbd>⌃L</kbd> in clipboard mode clears the clipboard (5 seconds to undo), not the command history. Deleting a single item can be undone too.
- Images (screenshots with <kbd>⌘⇧⌃4</kbd>, Copy Image) appear as thumbnails with their size and app. The text on them is recognized on this Mac, offline, and is searchable. <kbd>⌘Y</kbd> or a click on the thumbnail opens it full size, Enter copies it again, <kbd>⌘Enter</kbd> puts the image file path into the field. The preview is a window above the list: the image fills the window, and its header shows the keys that work right now. Drag the window by its header and resize it by its corners, always keeping the image proportions; a double-click on the header restores the original size. Select text on the image with the mouse, like in Preview: <kbd>⌘C</kbd> copies the selection (only the preview closes, Hatch stays), <kbd>⌘V</kbd> inserts it into the field, <kbd>⌘A</kbd> selects all of it. <kbd>⌘S</kbd> keeps the window on top of others: it stays when Hatch hides, shows on every desktop, and you can have several; <kbd>⌘V</kbd> and <kbd>⌘Enter</kbd> from it bring Hatch back and insert into the field. Esc and <kbd>⌘W</kbd> (and <kbd>⌘Q</kbd> for a pinned window) close the window, Esc clears the selection first; an unpinned preview also closes on a click outside it. Right-click shows the same actions as a menu, plus Copy Recognized Text and Pin in Clipboard. If the clipboard holds both text and an image (table cells), the text is saved. Up to 50 images, 20 MB each at most.
- Passwords (password managers mark them as concealed) and copies from excluded apps are never saved.
- Stored locally, up to 200 items for 7 days (configurable), and can be cleared in settings.

**Formatting**
- Hatch recognizes JSON (including logs made of JSON lines), SQL, YAML and XML by itself. In the clipboard the row is highlighted, with JSON and SQL on one line; in the output of a finished command, JSON, YAML and XML are shown formatted. A program's own colored output and the live terminal are left alone.
- <kbd>⌘Y</kbd> in the clipboard opens any text in the same window as images: in full, wrapped to the width, selectable with the mouse (<kbd>⌘A</kbd>, <kbd>⌘C</kbd> for the selection, ↩ for the whole text as shown, <kbd>⌘↩</kbd> into the field), <kbd>⌘S</kbd> keeps it on top of other windows, resize by the corners.
- The `{}` button on an item, in the preview window and on a command block, and <kbd>⇧⌘R</kbd>, switch between formatted and as is; the choice is remembered. What you see is what gets copied.
- SQL is broken into clauses, with keywords in UPPER CASE by default (lower case or unchanged in settings); dialects: standard, PostgreSQL, MySQL, ClickHouse.
- “SQL format: HatchPG · beta” in settings is Hatch's own style for PostgreSQL: columns with a leading comma, `JOIN … ON TRUE` and `WHERE TRUE` with `  AND …` conditions one per line, three or more ORs in parentheses as `(FALSE` with `OR …` one per line, three or more ANDs (or ANDs with a subquery, also after NOT) as `(TRUE` with `AND …` one per line, CASE across lines. A short subquery (one column, one table, no conditions) stays on one line: `IN (SELECT guid FROM d_rr)`. `EXISTS (SELECT 1 …)` becomes `EXISTS (SELECT FROM …)`: PostgreSQL needs no columns there (with the MySQL and ClickHouse dialects `SELECT 1` stays). A script is split at `;`: each query (also after `CREATE [TEMP] TABLE … AS`, one level deeper, and after `EXPLAIN`) is formatted with the comments above it, everything else (psql commands like `\set`, `BEGIN`, `ANALYZE`, `VACUUM`) stays as written, and blank lines between statements stay where they were. The query never changes in meaning: the result is checked against the original word for word (except that dropped constant in EXISTS), and if they do not match or a construct is unfamiliar, the standard format is shown.
- In settings: whether to format by default, which formats to recognize (“Code” highlights shell, Go, Python and others, off by default), and commands (`cat`, `less`) and apps whose content is shown as is. Anything over 1 MB is shown as is.

**Screenshots**
- <kbd>⇧⌘4</kbd> works even when Hatch is hidden. Select an area with the system crosshair: Space captures a whole window, Esc cancels.
- The screenshot goes straight to the clipboard and Hatch history, and its text is recognized. No file is saved to the Desktop.
- A thumbnail appears in the bottom-right corner with a timer bar (10 seconds, configurable), showing “✓ In clipboard” for the first 2 seconds. Hovering pauses the timer; a click opens the screenshot in a preview window without the Hatch panel: select text, <kbd>⌘C</kbd>, <kbd>⌘S</kbd> to keep it on top; a click outside (even in another app) or Esc closes it. Swipe right with two fingers to dismiss, drag it into any app as a PNG file.
- Several screenshots in a row stack up, newest at the bottom, up to three visible.
- macOS itself uses <kbd>⇧⌘4</kbd>: turn it off in System Settings → Keyboard → Keyboard Shortcuts… → Screenshots; Hatch points you there in its settings. The shortcut can be changed there too.

**Apps and calculator**
- An app name and Enter opens the app: `safari`, `calculator`, `visual studio code`. The right side of the field shows in advance what will happen; launches do not go into history.
- The first letters get a suggestion: `saf` completes to `safari` with Tab or →. If there is only one option and it is not a shell command, Enter opens the app right away, like Spotlight.
- A name with paths opens them in the app: `code .`, `zed ~/proj`. If the argument is not an existing path (`docker ps`), it is a command.
- When a name matches both an app and a command, the app wins. Names that should stay commands go into the exceptions in settings; by default those are `claude`, `ollama` and `opencode`.
- App aliases are configurable; by default `code` and `vscode` mean VS Code.
- Apps are found in Applications, system applications and `~/Applications`, one level deep.
- Calculator: `+ - * / ^ %` and parentheses, `4500*15%` = 675, digit groups separated by spaces: `1 000 000 / 3`. Enter copies the result and hides the panel.
- The decimal separator follows what you typed: `1.5*2` gives a point, `1,5*2` a comma. Without decimals in the input (`7/2`), the separator comes from settings, along with an “Always” option.

**Panel**
- Solid, without glass, in the style of macOS System Settings. Its height follows the content; size and position are remembered.
- Hides on a click in another app (except system permission and password prompts), when switching desktops, on <kbd>⌘Q</kbd>, and on <kbd>Esc</kbd> and <kbd>⌘W</kbd> when there is nothing left to close. The hotkey opens it on the current desktop, including over a full-screen app.
- The menu bar icon can be hidden: Hatch then opens with the hotkey or by launching it again.
- Settings (<kbd>⌘,</kbd> or the gear) open as a separate layer over the panel without resizing it. Settings: hotkey, folder tree shortcut (one button resets all shortcuts), icon, theme, language (RU/EN), preview lines, shell, timeout, Latin layout in the field, apps and calculator, aliases, exceptions, clipboard, formatting, screenshots.

</details>

## For developers

Building, tests, code structure and releases are covered in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) (in Russian).

## License

[MIT](LICENSE). The terminal is [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm), also MIT. SQL formatting uses [sql-formatter](https://github.com/sql-formatter-org/sql-formatter) (MIT) and highlighting uses [highlight.js](https://github.com/highlightjs/highlight.js) (BSD-3-Clause); their licenses are next to them in `Hatch/Syntax`.
