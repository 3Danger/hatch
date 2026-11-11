import SwiftUI
import AppKit

// Стиль «Слои»: блоки стоят чуть в глубине и выходят вперёд при наведении,
// раскрытый блок поднимается над остальными. Здесь — общие для панели детали.

/// Глубина блоков: все на одном среднем расстоянии, наведённый и раскрытый — впереди.
enum LayersDepth {
    static let restingScale: CGFloat = 0.975
    static let restingOpacity = 0.9

    /// Пока один блок раскрыт, остальные отходят в тень.
    static let dimmedScale: CGFloat = 0.965
    static let dimmedOpacity = 0.32

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

/// Капсула статуса: работает (крутилка), готово (галочка), ошибка (код), остановлена.
struct StatusCapsule: View {
    let status: BlockStatus
    let lang: String

    var body: some View {
        HStack(spacing: 5) {
            switch status {
            case .running, .interactive:
                Spinner(color: status.color)
            case .done:
                Image(systemName: "checkmark")
                    .font(.system(size: 9, weight: .heavy))
                    .symbolEffect(.bounce, value: status)
            case .failed(let code):
                Text("\(code)").fontWeight(.heavy)
            case .stopped, .interrupted:
                EmptyView()
            }
            Text(status.label(lang))
        }
        .font(.system(size: 11.5, weight: .semibold))
        .foregroundStyle(status.color)
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .background(status.color.opacity(status == .stopped || status == .interrupted ? 0.08 : 0.13), in: Capsule())
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
}

struct Spinner: View {
    let color: Color
    @State private var spinning = false

    var body: some View {
        Circle()
            .trim(from: 0.18, to: 1)
            .stroke(color, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
            .frame(width: 9, height: 9)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 0.8).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

/// Блик по стеклу: бежит по работающему блоку, один раз — когда команда завершилась.
struct GlassSheen: View {
    var repeating = true
    @State private var moved = false

    var body: some View {
        GeometryReader { geo in
            LinearGradient(colors: [.clear, .white.opacity(0.11), .clear], startPoint: .leading, endPoint: .trailing)
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

/// Появление: блок откидывается из-под поля ввода, как карточка.
private struct FlipIn: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees((1 - progress) * -32), axis: (1, 0, 0), anchor: .top, perspective: 0.6)
            .offset(y: (1 - progress) * -18)
            .scaleEffect(0.94 + 0.06 * progress, anchor: .top)
            .opacity(progress)
    }
}

/// Удаление: блок заваливается назад и тонет.
private struct SinkAway: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees(progress * 26), axis: (1, 0, 0), anchor: .bottom, perspective: 0.6)
            .offset(y: progress * 16)
            .scaleEffect(1 - 0.1 * progress)
            .opacity(1 - progress)
    }
}

/// Настройки выдвигаются от шестерёнки слоем стекла и уходят обратно.
private struct CardIn: ViewModifier {
    let progress: Double
    func body(content: Content) -> some View {
        content
            .rotation3DEffect(.degrees((1 - progress) * -12), axis: (1, 0, 0), anchor: .top, perspective: 0.6)
            .offset(y: (1 - progress) * -18)
            .scaleEffect(0.9 + 0.1 * progress, anchor: .topTrailing)
            .opacity(progress)
    }
}

extension AnyTransition {
    static var settingsLayer: AnyTransition {
        .modifier(active: CardIn(progress: 0), identity: CardIn(progress: 1))
    }

    static var layersBlock: AnyTransition {
        .asymmetric(insertion: .modifier(active: FlipIn(progress: 0), identity: FlipIn(progress: 1)),
                    removal: .modifier(active: SinkAway(progress: 1), identity: SinkAway(progress: 0)))
    }
}

/// Кнопка-иконка на стекле: прозрачная, при наведении — лёгкая подложка.
struct GlassIconButton: View {
    let systemName: String
    var color: Color = .secondary
    var size: CGFloat = 26
    let help: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(hovered && color == .secondary ? Color.primary : color)
                .frame(width: size, height: size)
                .background(.white.opacity(hovered ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(help)
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

/// Тонкий стеклянный бегунок поверх списка: появляется при прокрутке и гаснет,
/// при наведении шире, тянется мышью. Клик по дорожке листает на страницу.
struct GlassScrollbar: View {
    let metrics: ScrollMetrics
    let scrollTo: (CGFloat) -> Void
    @State private var hovered = false
    @State private var dragStart: CGFloat?
    @State private var recentlyScrolled = false

    var body: some View {
        GeometryReader { geo in
            let track = geo.size.height
            let thumb = ScrollMetrics.thumb(offset: metrics.offset, content: metrics.content,
                                            visible: metrics.visible, track: track)
            let wide = hovered || dragStart != nil
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white.opacity(wide ? 0.05 : 0))
                    .contentShape(Rectangle())
                    .onTapGesture(coordinateSpace: .local) { point in
                        let page = metrics.visible * 0.85
                        scrollTo(metrics.offset + (point.y < thumb.y ? -page : page))
                    }
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(dragStart != nil ? 0.75 : 0.55),
                                                  .white.opacity(dragStart != nil ? 0.45 : 0.3)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 2)
                    .frame(width: wide ? 8 : 5, height: thumb.height)
                    .padding(.trailing, wide ? 3 : 4)
                    .offset(y: thumb.y)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if dragStart == nil { dragStart = metrics.offset }
                                scrollTo(ScrollMetrics.offset(dragging: value.translation.height, from: dragStart ?? 0,
                                                              content: metrics.content, visible: metrics.visible,
                                                              track: track))
                            }
                            .onEnded { _ in dragStart = nil }
                    )
            }
            .animation(.easeOut(duration: 0.2), value: wide)
        }
        .frame(width: 14)
        .opacity(metrics.overflows && (hovered || dragStart != nil || recentlyScrolled) ? 1 : 0)
        .animation(.easeOut(duration: recentlyScrolled || hovered ? 0.15 : 0.45), value: recentlyScrolled || hovered)
        .onHover { hovered = $0 }
        .task(id: metrics.lastScroll) {
            guard metrics.lastScroll != .distantPast else { return }
            recentlyScrolled = true
            try? await Task.sleep(for: .milliseconds(900))
            if !Task.isCancelled { recentlyScrolled = false }
        }
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
