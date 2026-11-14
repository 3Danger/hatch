import SwiftUI

/// Иконки кнопок-колпачков, нарисованные линией 1.5 на сетке 16×16 — как в макете «Системный».
/// Символы SF толще и другой формы, поэтому кнопки с ними выглядели иначе, чем в макете.
enum KeyIcon: Hashable {
    case rerun, copy, pin, pinOn, trash, stop, gear, star, starOn, braces, bookmarks, bookmarksOn, more

    /// Ширина линии в единицах сетки 16×16.
    var lineWidth: CGFloat {
        switch self {
        case .rerun: return 1.6
        case .gear, .star, .starOn, .braces, .bookmarks, .bookmarksOn: return 1.4
        default: return 1.5
        }
    }

    var filled: Bool { self == .stop || self == .pinOn || self == .starOn || self == .bookmarksOn || self == .more }

    var lineCap: CGLineCap { self == .rerun || self == .trash || self == .braces ? .round : .butt }
    var lineJoin: CGLineJoin { [.pin, .pinOn, .star, .starOn, .braces, .bookmarks, .bookmarksOn].contains(self) ? .round : .miter }

    /// Контур в координатах сетки 16×16.
    var path: Path {
        var p = Path()
        switch self {
        case .rerun:
            // дуга радиусом 5 вокруг центра почти по кругу и уголок-стрелка
            let start = 0.0, end = atan2(-3.6, 3.5) + 2 * .pi
            for i in 0...48 {
                let a = start + (end - start) * Double(i) / 48
                let pt = CGPoint(x: 8 + 5 * cos(a), y: 8 + 5 * sin(a))
                i == 0 ? p.move(to: pt) : p.addLine(to: pt)
            }
            p.move(to: CGPoint(x: 13, y: 2.5))
            p.addLine(to: CGPoint(x: 13, y: 5.5))
            p.addLine(to: CGPoint(x: 10, y: 5.5))
        case .copy:
            p.addRoundedRect(in: CGRect(x: 5, y: 5, width: 8.5, height: 8.5), cornerSize: CGSize(width: 2, height: 2),
                             style: .circular)
            p.move(to: CGPoint(x: 11, y: 5))
            p.addArc(tangent1End: CGPoint(x: 11, y: 2), tangent2End: CGPoint(x: 9.5, y: 2), radius: 1.5)
            p.addArc(tangent1End: CGPoint(x: 2, y: 2), tangent2End: CGPoint(x: 2, y: 3.5), radius: 1.5)
            p.addArc(tangent1End: CGPoint(x: 2, y: 11), tangent2End: CGPoint(x: 3.5, y: 11), radius: 1.5)
            p.addLine(to: CGPoint(x: 5, y: 11))
        case .pin, .pinOn:
            p.addLines([CGPoint(x: 6, y: 2), CGPoint(x: 10, y: 2), CGPoint(x: 9.5, y: 6), CGPoint(x: 12, y: 8.5),
                        CGPoint(x: 4, y: 8.5), CGPoint(x: 6.5, y: 6)])
            p.closeSubpath()
        case .trash:
            p.addLines([CGPoint(x: 2.5, y: 4), CGPoint(x: 13.5, y: 4)])
            p.addLines([CGPoint(x: 6, y: 4), CGPoint(x: 6, y: 2.5), CGPoint(x: 10, y: 2.5), CGPoint(x: 10, y: 4)])
            p.addLines([CGPoint(x: 4, y: 4), CGPoint(x: 4.7, y: 13.5), CGPoint(x: 11.3, y: 13.5), CGPoint(x: 12, y: 4)])
        case .stop:
            p.addRoundedRect(in: CGRect(x: 4, y: 4, width: 8, height: 8), cornerSize: CGSize(width: 1.5, height: 1.5),
                             style: .circular)
        case .star, .starOn:
            p.addLines([CGPoint(x: 8, y: 1.9), CGPoint(x: 9.85, y: 5.7), CGPoint(x: 14, y: 6.3), CGPoint(x: 11, y: 9.25),
                        CGPoint(x: 11.7, y: 13.4), CGPoint(x: 8, y: 11.45), CGPoint(x: 4.3, y: 13.4), CGPoint(x: 5, y: 9.25),
                        CGPoint(x: 2, y: 6.3), CGPoint(x: 6.15, y: 5.7)])
            p.closeSubpath()
        case .braces:
            // «{}» — форматирование вывода
            for mirror in [false, true] {
                let x = { (v: CGFloat) in mirror ? 16 - v : v }
                p.move(to: CGPoint(x: x(6.5), y: 2.5))
                p.addQuadCurve(to: CGPoint(x: x(4.8), y: 4), control: CGPoint(x: x(4.8), y: 2.5))
                p.addLine(to: CGPoint(x: x(4.8), y: 6.6))
                p.addQuadCurve(to: CGPoint(x: x(3), y: 8), control: CGPoint(x: x(4.8), y: 8))
                p.addQuadCurve(to: CGPoint(x: x(4.8), y: 9.4), control: CGPoint(x: x(4.8), y: 8))
                p.addLine(to: CGPoint(x: x(4.8), y: 12))
                p.addQuadCurve(to: CGPoint(x: x(6.5), y: 13.5), control: CGPoint(x: x(4.8), y: 13.5))
            }
        case .gear:
            // шестерёнка: кольцо с зубцами и ось — прежние лучи без кольца читались как «солнце» (яркость)
            p.addEllipse(in: CGRect(x: 8 - 2, y: 8 - 2, width: 4, height: 4))
            p.addEllipse(in: CGRect(x: 8 - 4.4, y: 8 - 4.4, width: 8.8, height: 8.8))
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                p.move(to: CGPoint(x: 8 + 4.4 * cos(a), y: 8 + 4.4 * sin(a)))
                p.addLine(to: CGPoint(x: 8 + 6.4 * cos(a), y: 8 + 6.4 * sin(a)))
            }
        case .bookmarks, .bookmarksOn:
            // закладка — список избранного (звёздочка — «добавить в избранное»)
            p.addLines([CGPoint(x: 4, y: 2.5), CGPoint(x: 12, y: 2.5), CGPoint(x: 12, y: 13.5),
                        CGPoint(x: 8, y: 10.9), CGPoint(x: 4, y: 13.5)])
            p.closeSubpath()
        case .more:
            // «⋯» — остальные действия блока меню
            for x in [3.0, 8.0, 13.0] {
                p.addEllipse(in: CGRect(x: x - 1.25, y: 8 - 1.25, width: 2.5, height: 2.5))
            }
        }
        return p
    }

    /// Хвостик булавки остаётся линией и у закрашенной булавки.
    var stem: Path? {
        guard self == .pin || self == .pinOn else { return nil }
        var p = Path()
        p.addLines([CGPoint(x: 8, y: 8.5), CGPoint(x: 8, y: 14)])
        return p
    }
}

/// Иконка на сетке 16×16, растянутая до `size` точек; линия масштабируется вместе с ней.
struct KeyIconView: View {
    let icon: KeyIcon
    var size: CGFloat = 13

    var body: some View {
        Canvas { context, canvas in
            let scale = canvas.width / 16
            let transform = CGAffineTransform(scaleX: scale, y: scale)
            let style = StrokeStyle(lineWidth: icon.lineWidth * scale, lineCap: icon.lineCap, lineJoin: icon.lineJoin)
            let shading = GraphicsContext.Shading.foreground
            let shape = icon.path.applying(transform)
            if icon.filled { context.fill(shape, with: shading) }
            if icon != .stop && icon != .more { context.stroke(shape, with: shading, style: style) }
            if let stem = icon.stem { context.stroke(stem.applying(transform), with: shading, style: style) }
        }
        .frame(width: size, height: size)
    }
}
