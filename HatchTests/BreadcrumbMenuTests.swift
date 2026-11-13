import XCTest
import SwiftUI
import Observation
@testable import Hatch

/// Меню папки по правому клику открывается у любой папки пути — и после перехода глубже.
@MainActor
final class BreadcrumbMenuTests: XCTestCase {
    @Observable final class Model {
        var path = "/usr/local"
        var request = 0
    }

    private struct Host: View {
        let model: Model
        var body: some View {
            DirectoryBreadcrumbsView(path: model.path, recent: [], lang: "ru", onNavigate: { model.path = $0 },
                                     treeRequest: model.request)
                .frame(width: 600)
                .padding(10)
        }
    }

    private func anchors(in view: NSView) -> [PopupAnchorView] {
        var found: [PopupAnchorView] = []
        func walk(_ view: NSView) {
            if let anchor = view as? PopupAnchorView { found.append(anchor) }
            view.subviews.forEach(walk)
        }
        walk(view)
        return found
    }

    private func rightClick(at anchor: PopupAnchorView, in window: NSWindow) -> NSEvent {
        let frame = anchor.convert(anchor.bounds, to: nil)
        return NSEvent.mouseEvent(with: .rightMouseDown, location: NSPoint(x: frame.midX, y: frame.midY),
                                  modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                                  clickCount: 1, pressure: 1)!
    }

    private func spin() { RunLoop.main.run(until: Date().addingTimeInterval(0.3)) }

    /// Ждать, пока условие не выполнится (до 2 с): окна показываются после прохода раскладки,
    /// а на медленной машине (раннер CI) это дольше фиксированной паузы.
    private func wait(until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(2)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    /// У каждой папки ровно один якорь берёт правый клик, и он открывает меню.
    private func assertEveryCrumbOpensMenu(_ host: NSView, _ window: NSWindow, crumbs: Int,
                                           file: StaticString = #filePath, line: UInt = #line) {
        let all = anchors(in: host)
        let menus = all.filter { $0.onSecondaryClick != nil }
        XCTAssertEqual(menus.count, crumbs, "по якорю меню на папку", file: file, line: line)
        for anchor in menus {
            let event = rightClick(at: anchor, in: window)
            // никакой другой якорь в той же точке клик не перехватывает
            XCTAssertEqual(all.filter { $0.handlesSecondaryClick(event) }, [anchor], file: file, line: line)
            anchor.onSecondaryClick?(NSPoint(x: 300, y: 300))
            wait { window.childWindows?.count == 1 }
            XCTAssertEqual(window.childWindows?.count, 1, "меню открылось", file: file, line: line)
            NotificationCenter.default.post(name: .hatchDidHide, object: nil)
            wait { (window.childWindows?.count ?? 0) == 0 }
            XCTAssertEqual(window.childWindows?.count ?? 0, 0, file: file, line: line)
        }
    }

    func testMenuOpensOnEveryCrumbAfterNavigatingDeeper() {
        let model = Model()
        let host = NSHostingView(rootView: Host(model: model))
        let window = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 640, height: 60),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        spin()
        assertEveryCrumbOpensMenu(host, window, crumbs: 3) // / › usr › local

        model.path = "/usr/local/bin"
        spin()
        assertEveryCrumbOpensMenu(host, window, crumbs: 4)
    }

    /// ⌘P открывает дерево папок у текущей папки, повторное ⌘P — закрывает.
    func testShortcutTogglesFolderTree() {
        let model = Model()
        let host = NSHostingView(rootView: Host(model: model))
        let window = NSPanel(contentRect: NSRect(x: 100, y: 100, width: 640, height: 60),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        spin()
        model.request += 1
        wait { window.childWindows?.count == 1 }
        XCTAssertEqual(window.childWindows?.count, 1, "дерево открылось")
        model.request += 1
        wait { (window.childWindows?.count ?? 0) == 0 }
        XCTAssertEqual(window.childWindows?.count ?? 0, 0, "и закрылось")
    }

    private func press(_ window: NSWindow, _ code: UInt16, command: Bool = false) {
        let character = String(UnicodeScalar(code == 123 ? NSLeftArrowFunctionKey : NSRightArrowFunctionKey)!)
        let flags: NSEvent.ModifierFlags = command ? [.command, .function, .numericPad] : [.function, .numericPad]
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags,
                                     timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                     context: nil, characters: character, charactersIgnoringModifiers: character,
                                     isARepeat: false, keyCode: code)!
        window.sendEvent(event)
        spin()
    }

    /// Середины папок пути на экране — по якорям дерева (у якорей меню есть свой обработчик правого клика).
    private func crumbCenters(_ host: NSView, _ window: NSWindow) -> [CGFloat] {
        anchors(in: host).filter { $0.onSecondaryClick == nil }
            .map { window.convertToScreen($0.convert($0.bounds, to: nil)).midX }
            .sorted()
    }

    /// После ← на верхнем уровне дерево относится к папке выше — ⌘←/⌘→ считают соседей от неё,
    /// а не от папки, у которой дерево открыли.
    func testSwitchCrumbAfterTreeWentUp() throws {
        let model = Model() // / › usr › local
        let host = NSHostingView(rootView: Host(model: model))
        let window = NSPanel(contentRect: NSRect(x: 300, y: 500, width: 640, height: 60),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        spin()
        let centers = crumbCenters(host, window)
        XCTAssertEqual(centers.count, 3)
        model.request += 1 // ⌘P — дерево у local
        wait { window.childWindows?.count == 1 }
        var tree = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(tree.frame.midX, centers[2], accuracy: 1)
        press(tree, 123) // ← на верхнем уровне: дерево уровнем выше, в пути — usr
        press(tree, 123, command: true) // ⌘← — дерево у «/»
        wait { abs((window.childWindows?.first?.frame.midX ?? 0) - centers[0]) < 1 }
        tree = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(tree.frame.midX, centers[0], accuracy: 1, "⌘← от usr — к «/»")
        press(tree, 124, command: true) // ⌘→ — обратно к usr
        wait { abs((window.childWindows?.first?.frame.midX ?? 0) - centers[1]) < 1 }
        tree = try XCTUnwrap(window.childWindows?.first)
        XCTAssertEqual(tree.frame.midX, centers[1], accuracy: 1, "⌘→ от «/» — к usr")
    }

    /// ⌘1, ← (дерево поднялось к usr), ⌘→ — обратно к local: дерево снова у local, а не застряло выше.
    /// Какое дерево показано, видно по высоте окна: в /usr и «/» разное число папок.
    func testSwitchBackToOpenedCrumbResetsTree() throws {
        let model = Model() // / › usr › local
        let host = NSHostingView(rootView: Host(model: model))
        let window = NSPanel(contentRect: NSRect(x: 300, y: 500, width: 640, height: 60),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        spin()
        model.request += 1 // ⌘1 — дерево у local: папки /usr
        wait { window.childWindows?.count == 1 }
        let atLocal = try XCTUnwrap(window.childWindows?.first).frame.height
        press(try XCTUnwrap(window.childWindows?.first), 123) // ← — дерево у usr: папки «/»
        wait { (window.childWindows?.first?.frame.height ?? atLocal) != atLocal }
        XCTAssertNotEqual(window.childWindows?.first?.frame.height ?? atLocal, atLocal, "дерево поднялось к «/»")
        press(try XCTUnwrap(window.childWindows?.first), 124, command: true) // ⌘→ — снова у local
        wait { (window.childWindows?.first?.frame.height ?? 0) == atLocal }
        XCTAssertEqual(window.childWindows?.first?.frame.height ?? 0, atLocal, accuracy: 1, "дерево снова у local")
    }

    /// ← на верхнем уровне: окно дерева переезжает к папке выше в пути, как при ⌘←.
    func testTreeWindowFollowsLeftArrowUp() throws {
        let model = Model() // / › usr › local
        let host = NSHostingView(rootView: Host(model: model))
        let window = NSPanel(contentRect: NSRect(x: 300, y: 500, width: 640, height: 60),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        spin()
        let centers = crumbCenters(host, window)
        model.request += 1 // ⌘1 — дерево у local
        wait { window.childWindows?.count == 1 }
        XCTAssertEqual(try XCTUnwrap(window.childWindows?.first).frame.midX, centers[2], accuracy: 1)
        press(try XCTUnwrap(window.childWindows?.first), 123) // ← — дерево у usr
        wait { abs((window.childWindows?.first?.frame.midX ?? 0) - centers[1]) < 1 }
        XCTAssertEqual(window.childWindows?.first?.frame.midX ?? 0, centers[1], accuracy: 1, "окно у usr")
        XCTAssertEqual(window.childWindows?.count, 1, "окно одно, старое закрылось")
    }

    /// Длинный путь с «…»: ← раз за разом ведёт дерево по всем папкам пути, и по спрятанным за «…» тоже
    /// (путь раскрывается). Окно у спрятанной папки не открывалось: её элемент только появлялся.
    func testLeftArrowWalksThroughCollapsedCrumbs() throws {
        let model = Model()
        model.path = "/System/Library/Frameworks/AppKit.framework/Versions" // / › … › AppKit.framework › Versions
        let host = NSHostingView(rootView: Host(model: model))
        let window = NSPanel(contentRect: NSRect(x: 300, y: 500, width: 640, height: 60),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        spin()
        model.request += 1 // ⌘T — дерево у Versions
        wait { window.childWindows?.count == 1 }
        // AppKit.framework (путь ещё свёрнут: «/», AppKit.framework, Versions), затем спрятанные — путь целиком
        for (step, crumb) in [(1, 1), (2, 3), (3, 2), (4, 1)] {
            press(try XCTUnwrap(window.childWindows?.first, "шаг \(step): дерево открыто"), 123)
            let target = { () -> CGFloat? in
                let centers = self.crumbCenters(host, window)
                return centers.indices.contains(crumb) ? centers[crumb] : nil
            }
            wait { abs((window.childWindows?.first?.frame.midX ?? 0) - (target() ?? -1)) < 1 }
            let tree = try XCTUnwrap(window.childWindows?.first, "шаг \(step): дерево открыто")
            XCTAssertEqual(tree.frame.midX, try XCTUnwrap(target()), accuracy: 1, "шаг \(step): дерево у своей папки")
            XCTAssertEqual(window.childWindows?.count, 1, "шаг \(step): окно одно")
        }
    }
}
