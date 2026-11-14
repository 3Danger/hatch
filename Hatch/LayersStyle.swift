import SwiftUI
import AppKit

// Стиль «Системный»: язык системных настроек macOS, без стекла. Окно сплошное, блоки и поле ввода
// утоплены в него (тень по верхней стенке, мягкий блик снизу — свет сверху), кнопки — колпачки клавиш.

/// Поведение блоков: при раскрытом блоке остальные приглушены.
enum LayersDepth {
    /// Соседи раскрытого блока приглушены слегка: раскрытый выделяет только это, без обводки.
    static let dimmedOpacity = 0.7

    static let spring = Animation.spring(response: 0.42, dampingFraction: 0.86)
    /// Приближение при наведении — в полтора раза быстрее раскрытия и появления.
    static let hoverSpring = Animation.spring(response: 0.28, dampingFraction: 0.86)
}

/// Состояние блока для капсулы статуса: цвет, значок и подпись.
enum BlockStatus: Equatable {
    case running, interactive, done, failed(Int32), stopped, interrupted

    init(_ session: Session) {
        switch session.state {
        case .running: self = .running
        case .interactive: self = .interactive
        case .stopped: self = .stopped
        case .interrupted: self = .interrupted
        case .completed:
            if let code = session.exitCode, code != 0 { self = .failed(code) } else { self = .done }
        }
    }

    var isActive: Bool { self == .running || self == .interactive }

    func label(_ lang: String) -> String {
        switch self {
        case .running: return L.t("st_running", lang)
        case .interactive: return L.t("st_interactive", lang)
        case .done: return L.t("st_done", lang)
        case .failed: return L.t("st_failed", lang)
        case .stopped: return L.t("st_stopped", lang)
        case .interrupted: return L.t("st_interrupted", lang)
        }
    }

    var color: Color {
        switch self {
        case .running: return LayersPalette.running
        case .interactive: return LayersPalette.accent
        case .done: return LayersPalette.ok
        case .failed: return LayersPalette.error
        case .stopped, .interrupted: return .secondary
        }
    }
}

/// Цвета «Объёма»: сплошные, свои для тёмной и светлой темы.
enum Tactile {
    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    private static func color(dark: UInt32, light: UInt32) -> Color {
        let darkColor = hex(dark), lightColor = hex(light)
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? darkColor : lightColor
        })
    }

    static let surfaceTop = color(dark: 0x333336, light: 0xf5f5f7)
    static let surfaceBottom = color(dark: 0x2a2a2d, light: 0xe9e9ed)
    static let surfaceEdge = color(dark: 0x424246, light: 0xc8c8ce)
    static let group = color(dark: 0x323235, light: 0xffffff)
    static let groupHover = color(dark: 0x38383c, light: 0xfbfbfd)
    static let groupEdge = color(dark: 0x3d3d41, light: 0xd5d5db)
    static let raiseTop = color(dark: 0x505055, light: 0xffffff)
    static let raiseBottom = color(dark: 0x3c3c40, light: 0xe8e8ed)
    static let raiseHoverTop = color(dark: 0x5a5a60, light: 0xffffff)
    static let raiseHoverBottom = color(dark: 0x444449, light: 0xf1f1f5)
    static let raiseEdge = color(dark: 0x5b5b61, light: 0xc3c3ca)
    static let raiseUnder = color(dark: 0x18181a, light: 0xa8a8b1)
    static let keyText = color(dark: 0xe6e6ea, light: 0x1d1d1f)
    static let keyTextHover = color(dark: 0xffffff, light: 0x000000)
    static let well = color(dark: 0x212123, light: 0xdcdce2)
    static let wellEdge = color(dark: 0x1a1a1c, light: 0xc6c6cd)
    static let blueTop = color(dark: 0x5b8fe0, light: 0x5b8fe0)
    static let blueBottom = color(dark: 0x3f6fc4, light: 0x3f6fc4)
    static let blueEdge = color(dark: 0x6d9ae6, light: 0x3b66b5)
    static let errorTop = color(dark: 0x7a3b46, light: 0xffe1e6)
    static let errorBottom = color(dark: 0x5c2b34, light: 0xf8c9d1)
    static let errorEdge = color(dark: 0x94505c, light: 0xe39aa8)
    static let errorText = color(dark: 0xffd2d8, light: 0x9b1c33)
    static let runTop = color(dark: 0x7a6630, light: 0xfff2cc)
    static let runBottom = color(dark: 0x5c4c22, light: 0xf7e2a6)
    static let runEdge = color(dark: 0x98823f, light: 0xd9b95c)
    static let runText = color(dark: 0xfff0c8, light: 0x6b4d00)
    static let okText = color(dark: 0x74e6ab, light: 0x17824a)

    // окно и утопленные поверхности
    static let window = color(dark: 0x2a2a2d, light: 0xececef)
    static let windowEdge = color(dark: 0x3f3f43, light: 0xc6c6cc)
    static let sunken = color(dark: 0x222224, light: 0xe1e1e5)
    static let sunkenHover = color(dark: 0x252528, light: 0xdcdce1)
    static let field = color(dark: 0x1d1d1f, light: 0xe6e6ea)
    // системные цвета
    static let accent = color(dark: 0x0a84ff, light: 0x007aff)
    /// Режим поиска в поле ввода: рамка и метка другого цвета, чтобы было видно, в каком ты режиме.
    static let search = color(dark: 0xff9f0a, light: 0xc93400)
    /// Режим буфера обмена (⌘4): отличается от оранжевого поиска.
    static let clip = color(dark: 0xbf5af2, light: 0x8944ab)
    /// Избранное: закрашенная звезда.
    static let star = color(dark: 0xffd60a, light: 0xc79500)
    /// Контекстное меню (своё, сплошное — системное в macOS 26 стеклянное).
    static let menu = color(dark: 0x2c2c2e, light: 0xf6f6f8)
    static let menuEdge = color(dark: 0x4a4a4e, light: 0xc8c8ce)
    /// Синий «папочный» градиент значка папки, как в строке пути Finder.
    static let folderTop = color(dark: 0x6fb3ff, light: 0x6fb3ff)
    static let folderBottom = color(dark: 0x3d8ef0, light: 0x3d8ef0)
    /// Всплывающее сообщение внизу панели.
    static let toast = color(dark: 0x3a3a3d, light: 0xffffff)
    static let green = color(dark: 0x30d158, light: 0x28a745)
    static let red = color(dark: 0xff453a, light: 0xff3b30)
    static let redText = color(dark: 0xff6961, light: 0xd70015)

    static let raise = LinearGradient(colors: [raiseTop, raiseBottom], startPoint: .top, endPoint: .bottom)
    static let raiseHover = LinearGradient(colors: [raiseHoverTop, raiseHoverBottom], startPoint: .top, endPoint: .bottom)
    static let blue = LinearGradient(colors: [blueTop, blueBottom], startPoint: .top, endPoint: .bottom)
    static let surface = LinearGradient(colors: [surfaceTop, surfaceBottom], startPoint: .top, endPoint: .bottom)
}

extension View {
    /// Приподнятая плашка, как колпачок в макете: градиент светлее сверху, кромка 1 точка внутри,
    /// жёсткая тень снизу. Светлая линия сверху в макете перекрыта кромкой, поэтому её нет.
    func tactileRaised<S: InsettableShape>(_ shape: S, fill: some ShapeStyle = Tactile.raise, edge: Color = Tactile.raiseEdge,
                                           edgeWidth: CGFloat = 1, under: CGFloat = 2, pressed: Bool = false) -> some View {
        background {
            shape.fill(fill)
                .overlay(shape.strokeBorder(edge, lineWidth: edgeWidth))
                .background(shape.fill(Tactile.raiseUnder).offset(y: pressed ? 0 : under))
        }
        .offset(y: pressed ? under : 0)
    }

    /// Утоплено в окно, свет сверху: тень по верхней внутренней стенке, мягкий бархатный блик
    /// на нижней стенке и на нижней кромке снаружи.
    func sunken<S: Shape>(_ shape: S, fill: Color = Tactile.sunken) -> some View {
        background {
            shape.fill(fill
                .shadow(.inner(color: .black.opacity(0.48), radius: 3.5, y: 2.6))
                .shadow(.inner(color: .white.opacity(0.06), radius: 1.5, y: -2)))
                .overlay(shape.stroke(.black.opacity(0.6), lineWidth: 0.5))
                .background(shape.fill(.white.opacity(0.1)).offset(y: 1.5).blur(radius: 1.5))
        }
    }

    /// Фокус: тонкая полупрозрачная линия по краю, без кольца снаружи
    /// (поле в фокусе, блок, выбранный стрелками, поле шага).
    func selectionRing(cornerRadius: CGFloat, visible: Bool, color: Color = Tactile.accent) -> some View {
        overlay {
            if visible {
                RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(color.opacity(0.55), lineWidth: 1)
            }
        }
    }

    /// Утопленная лунка: тёмная подложка с внутренней тенью.
    func tactileWell<S: Shape>(_ shape: S) -> some View {
        background {
            shape.fill(Tactile.well.shadow(.inner(color: .black.opacity(0.6), radius: 3, y: 2)))
                .overlay(shape.stroke(Tactile.wellEdge, lineWidth: 1))
        }
    }
}

/// Кнопка-колпачок: при нажатии проседает и теряет тень. Углы обычные (не «суперэллипс»), как border-radius в макете.
struct KeyCapButtonStyle: ButtonStyle {
    var cornerRadius: CGFloat = 8
    var hovered = false
    var primary = false
    var under: CGFloat = 2

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .tactileRaised(RoundedRectangle(cornerRadius: cornerRadius, style: .circular),
                           fill: primary ? Tactile.blue : (hovered ? Tactile.raiseHover : Tactile.raise),
                           edge: primary ? Tactile.blueEdge : Tactile.raiseEdge,
                           under: under, pressed: configuration.isPressed)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}

enum LayersPalette {
    static let running = Color(red: 1, green: 0.82, blue: 0.4)
    static let ok = Color(red: 0.37, green: 0.88, blue: 0.63)
    static let error = Color(red: 1, green: 0.44, blue: 0.53)
    static let accent = Color(red: 0.55, green: 0.78, blue: 1)
}

/// Горячая клавиша колпачками: "alt-space" → ⌥ Space.
enum HotKeyCaps {
    static func keys(for spec: String) -> [String] {
        spec.split(separator: "-").map { part in
            switch part.lowercased() {
            case "ctrl", "control": return "⌃"
            case "alt", "option", "opt": return "⌥"
            case "shift": return "⇧"
            case "cmd", "command": return "⌘"
            case "space": return "Space"
            case "return", "enter": return "↩"
            case "tab": return "⇥"
            case "escape", "esc": return "⎋"
            case "delete": return "⌫"
            default: return part.uppercased()
            }
        }
    }
}

/// Статус без плашки, как в системных настройках: значок и подпись.
/// Готово — зелёная галочка, ошибка — красный кружок с кодом, работает — системная крутилка.
struct StatusCapsule: View {
    let status: BlockStatus
    let lang: String
    /// В строке под командой: мельче, по размеру подписи папки и времени.
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            switch status {
            case .running, .interactive:
                ProgressView().controlSize(.small).scaleEffect(0.75).frame(width: 14, height: 14)
            case .done:
                Image(systemName: "checkmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Tactile.green)
                    .font(.system(size: compact ? 11.5 : 13))
                    .symbolEffect(.bounce, value: status)
            case .failed(let code):
                Text("\(code)")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Tactile.red, in: Capsule())
            case .stopped, .interrupted:
                // остановил пользователь — серый квадрат «стоп», не путать с красной ошибкой
                Image(systemName: "stop.circle.fill")
                    .foregroundStyle(.secondary)
                    .font(.system(size: compact ? 11.5 : 13))
            }
            Text(status.label(lang))
                .foregroundStyle(textColor)
        }
        .font(.system(size: compact ? 11.5 : 12))
        .padding(.horizontal, 2)
        .fixedSize()
        .offset(x: shake)
        // ошибка коротко вздрагивает, когда команда только что завершилась
        .onChange(of: status) { _, new in
            guard case .failed = new else { return }
            Task { @MainActor in
                for x: CGFloat in [-3, 3, -2, 0] {
                    withAnimation(.easeInOut(duration: 0.07)) { shake = x }
                    try? await Task.sleep(for: .milliseconds(70))
                }
            }
        }
    }

    @State private var shake: CGFloat = 0

    private var textColor: Color {
        switch status {
        case .failed: return Tactile.redText
        case .interactive: return Tactile.accent
        default: return .secondary
        }
    }
}

/// Блик по стеклу: бежит по работающему блоку, один раз — когда команда завершилась.
struct GlassSheen: View {
    var repeating = true
    @State private var moved = false

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.07), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: geo.size.width * 0.32)
                .rotationEffect(.degrees(14))
                .offset(x: moved ? geo.size.width * 1.15 : -geo.size.width * 0.45)
                .frame(maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .onAppear {
            let animation = Animation.easeInOut(duration: repeating ? 2.4 : 0.9)
            withAnimation(repeating ? animation.repeatForever(autoreverses: false) : animation) { moved = true }
        }
    }
}

/// Появление: раздел раздвигает список и проявляется, как строка системной таблицы.
private struct RowIn: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content.offset(y: (1 - progress) * -6).opacity(progress)
    }
}

/// Удаление: раздел уезжает влево и гаснет.
private struct RowOut: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content.offset(x: progress * -40).opacity(1 - progress)
    }
}

extension AnyTransition {
    static var layersBlock: AnyTransition {
        .asymmetric(insertion: .modifier(active: RowIn(progress: 0), identity: RowIn(progress: 1)),
                    removal: .modifier(active: RowOut(progress: 1), identity: RowOut(progress: 0)))
    }
}

/// Кнопка-иконка — колпачок клавиши: проседает при нажатии, светлеет при наведении.
/// Иконка рисуется линией (`KeyIcon`): 13 точек в кнопке 24, 16 — в кнопке 28, как в макете.
struct GlassIconButton: View {
    let icon: KeyIcon
    var color: Color? = nil
    var size: CGFloat = 26
    let help: String
    /// Подсказка Hatch при наведении (вместо системной `.help`).
    var tip: HatchTip? = nil
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            KeyIconView(icon: icon, size: size >= 28 ? 16 : 13)
                .foregroundStyle(color ?? (hovered ? Tactile.keyTextHover : Tactile.keyText))
                .frame(width: size, height: size)
                .contentShape(Rectangle())
        }
        .buttonStyle(KeyCapButtonStyle(cornerRadius: LauncherMetrics.buttonRadius(size), hovered: hovered))
        .onHover { hovered = $0 }
        .help(tip == nil ? help : "")
        .hatchTip(tip)
        .accessibilityLabel(help)
    }
}

/// Где на панели раскрытый блок и полоса прокрутки (в координатах панели, начало — сверху слева).
/// Класс, а не состояние вида: рамки меняются при каждой прокрутке и не должны перерисовывать панель.
final class PanelFrames {
    var expanded: CGRect = .null
    var scrollbar: CGRect = .null

    /// Клик сворачивает раскрытый блок, если он не по самому блоку и не по полосе прокрутки.
    static func collapses(at point: CGPoint, expanded: CGRect, scrollbar: CGRect) -> Bool {
        guard !expanded.isNull else { return false }
        return !expanded.contains(point) && !scrollbar.contains(point)
    }
}

// MARK: - Стеклянная полоса прокрутки

/// Положение прокрутки списка. Отдельный объект: прокрутка перерисовывает только полосу
/// и затухание краёв, а не все блоки истории.
@Observable
final class ScrollMetrics {
    var offset: CGFloat = 0
    var content: CGFloat = 0
    var visible: CGFloat = 0
    /// Последняя прокрутка — полоса видна ещё немного после неё.
    var lastScroll = Date.distantPast
    /// Куда прокручен список: бегунок полосы двигает его через это значение.
    var position = ScrollPosition(edge: .top)

    var overflows: Bool { content > visible + 1 }
    var atTop: Bool { offset <= 2 }
    var atBottom: Bool { offset + visible >= content - 2 }

    /// Бегунок: высота и положение на дорожке длины `track`.
    static func thumb(offset: CGFloat, content: CGFloat, visible: CGFloat, track: CGFloat) -> (y: CGFloat, height: CGFloat) {
        guard content > visible, track > 0 else { return (0, track) }
        let height = max(28, track * visible / content)
        let progress = min(max(offset / (content - visible), 0), 1)
        return ((track - height) * progress, height)
    }

    /// Смещение прокрутки для бегунка, сдвинутого на `dy` от начального положения.
    static func offset(dragging dy: CGFloat, from start: CGFloat, content: CGFloat, visible: CGFloat, track: CGFloat) -> CGFloat {
        let thumbHeight = thumb(offset: 0, content: content, visible: visible, track: track).height
        guard track > thumbHeight else { return start }
        let target = start + dy * (content - visible) / (track - thumbHeight)
        return min(max(target, 0), max(content - visible, 0))
    }
}

/// Края списка затухают, если сверху или снизу есть ещё блоки.
struct EdgeFadeMask: View {
    let metrics: ScrollMetrics
    private let fade: CGFloat = 22

    var body: some View {
        let top = metrics.overflows && !metrics.atTop
        let bottom = metrics.overflows && !metrics.atBottom
        VStack(spacing: 0) {
            LinearGradient(colors: [top ? .clear : .black, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
            Color.black
            LinearGradient(colors: [.black, bottom ? .clear : .black], startPoint: .top, endPoint: .bottom)
                .frame(height: fade)
        }
    }
}

/// Значок папки, как в макете: синий прямоугольник с градиентом и светлой кромкой сверху.
struct FolderGlyph: View {
    var width: CGFloat = 18
    var height: CGFloat = 14

    var body: some View {
        let radius = (height * 0.2).rounded()
        RoundedRectangle(cornerRadius: radius, style: .circular)
            .fill(LinearGradient(colors: [Tactile.folderTop, Tactile.folderBottom], startPoint: .top, endPoint: .bottom))
            // светлая кромка сверху, как inset-тень в макете
            .overlay(alignment: .top) {
                Rectangle().fill(.white.opacity(0.35)).frame(height: 2)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .circular))
            .frame(width: width, height: height)
    }
}

/// Клавиша-подсказка в подвале всплывающего окна (↑, ↩, esc): маленькая лунка с символом.
struct KeyHint: View {
    let key: String

    var body: some View {
        Text(key)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 16)
            .fixedSize()
            .tactileWell(RoundedRectangle(cornerRadius: 4, style: .circular))
    }
}
