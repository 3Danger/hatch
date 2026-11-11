import SwiftUI

/// Контекстное меню в стиле меню macOS, но сплошное (системное в macOS 26 стеклянное).
/// Строка под курсором подсвечивается синим; подменю раскрывается прямо под строкой.
struct FolderMenuView: View {
    struct Item: Identifiable {
        let id = UUID()
        var title: String
        /// Звезда в колонке значков: true — закрашенная, false — контур, nil — без звезды.
        var star: Bool?
        var folder = false
        /// Подсказка справа: сочетание клавиш или папка, в которой лежит.
        var detail: String?
        var help: String?
        var children: [Item] = []
        var action: (() -> Void)?

        init(title: String, star: Bool? = nil, folder: Bool = false, detail: String? = nil, help: String? = nil,
             children: [Item] = [], action: (() -> Void)? = nil) {
            self.title = title
            self.star = star
            self.folder = folder
            self.detail = detail
            self.help = help
            self.children = children
            self.action = action
        }
    }

    struct Section: Identifiable {
        let id = UUID()
        var header: String?
        var items: [Item]

        init(header: String? = nil, items: [Item]) {
            self.header = header
            self.items = items
        }
    }

    let sections: [Section]
    @State private var hovered: UUID?
    @State private var openSubmenu: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                if index > 0 {
                    Rectangle().fill(Tactile.menuEdge).frame(height: 1).padding(.horizontal, 8).padding(.vertical, 5)
                }
                if let header = section.header {
                    Text(header)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 9)
                        .padding(.top, 2)
                        .padding(.bottom, 2)
                }
                ForEach(section.items) { item in
                    row(item, indent: 0)
                    if openSubmenu == item.id {
                        ForEach(item.children) { row($0, indent: 1) }
                    }
                }
            }
        }
        .frame(minWidth: 230, alignment: .leading)
        .fixedSize()
    }

    private var hasIconColumn: Bool {
        sections.contains { $0.items.contains { $0.star != nil || $0.folder } }
    }

    private func row(_ item: Item, indent: Int) -> some View {
        let lit = hovered == item.id
        return HStack(spacing: 8) {
            if hasIconColumn || indent > 0 {
                Group {
                    if let star = item.star {
                        KeyIconView(icon: star ? .starOn : .star, size: 13)
                            .foregroundStyle(lit ? .white : Tactile.star)
                    } else if item.folder {
                        FolderGlyph(width: 15, height: 11)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 16)
            }
            Text(item.title)
                .lineLimit(1)
                .padding(.leading, CGFloat(indent) * 6)
            Spacer(minLength: 18)
            if !item.children.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(openSubmenu == item.id ? 90 : 0))
                    .foregroundStyle(lit ? .white.opacity(0.85) : .secondary)
            } else if let detail = item.detail {
                Text(detail)
                    .lineLimit(1)
                    .foregroundStyle(lit ? .white.opacity(0.8) : .secondary.opacity(0.75))
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(lit ? .white : .primary)
        .padding(.horizontal, 9)
        .frame(height: 24)
        .background(lit ? Tactile.accent : .clear, in: RoundedRectangle(cornerRadius: 5, style: .circular))
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
        .onTapGesture {
            if !item.children.isEmpty {
                withAnimation(.easeOut(duration: 0.15)) { openSubmenu = openSubmenu == item.id ? nil : item.id }
            } else {
                item.action?()
            }
        }
        .help(item.help ?? "")
    }
}
