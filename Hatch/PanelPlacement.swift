import AppKit

/// Где показать панель: там, куда её передвинул пользователь, если это место ещё на экране,
/// иначе — по центру сверху главного экрана.
enum PanelPlacement {
    /// Сколько панели должно остаться на экране, чтобы её можно было ухватить и вернуть.
    private static let minVisible = NSSize(width: 100, height: 50)

    static func origin(saved: NSPoint?, panelSize: NSSize, visibleFrames: [NSRect], main: NSRect) -> NSPoint {
        if let saved {
            let rect = NSRect(origin: saved, size: panelSize)
            let onScreen = visibleFrames.contains { frame in
                let visible = frame.intersection(rect)
                return visible.width >= minVisible.width && visible.height >= minVisible.height
            }
            if onScreen { return saved }
        }
        return NSPoint(x: main.midX - panelSize.width / 2,
                       y: main.maxY - panelSize.height - 40)
    }
}
