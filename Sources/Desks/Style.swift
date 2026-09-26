import SwiftUI

enum Style {
    static let header: CGFloat = 44
    static let indent: CGFloat = 34
    static let space = "note"

    static func fold(_ folded: Bool) -> Animation? {
        folded ? nil : .easeInOut(duration: 0.15)
    }
}

extension View {
    func wrap(_ text: String, lines: Int? = nil) -> some View {
        Text(text.isEmpty ? " " : text)
            .lineLimit(lines)
            .hidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topLeading) { self }
    }

    func slide(_ id: UUID, in store: Store) -> some View {
        let lifted = store.lift?.id == id
        return offset(y: store.offset(for: id))
            .zIndex(lifted ? 1 : 0)
            .animation(lifted ? nil : .easeInOut(duration: 0.18), value: store.lift?.slot)
    }

    func shelf(_ id: UUID, in store: Store) -> some View {
        modifier(Spot(key: id) { store.place(shelf: $0, $1, by: $2) })
    }

    func card(_ id: UUID, in store: Store) -> some View {
        modifier(Spot(key: id) { store.place(card: $0, $1, by: $2) })
    }

    func inbox(_ agent: Agent, in store: Store) -> some View {
        modifier(Spot(key: agent) { store.place(inbox: $0, $1, by: $2) })
    }

    func zone(_ id: UInt64?, in store: Store) -> some View {
        modifier(Spot(key: id) { store.place($0, $1, by: $2) })
    }
}

private struct Spot<Key: Hashable>: ViewModifier {
    let key: Key
    let place: (Key, CGRect?, UUID) -> Void
    @State private var token = UUID()

    func body(content: Content) -> some View {
        content.background(GeometryReader { proxy in
            let frame = proxy.frame(in: .named(Style.space))
            Color.clear
                .onAppear { place(key, frame, token) }
                .onChange(of: frame) { _, frame in place(key, frame, token) }
                .onChange(of: key) { old, new in
                    place(old, nil, token)
                    place(new, frame, token)
                }
                .onDisappear { place(key, nil, token) }
        })
    }
}

extension Color {
    static let paper = Color(.sRGB, red: 0.141, green: 0.329, blue: 0.902)
    static let deep = Color(.sRGB, red: 0.090, green: 0.220, blue: 0.702)
    static let wash = Color.white.opacity(0.12)
    static let mist = Color.white.opacity(0.22)
    static let ink = Color.white
    static let amber = Color(.sRGB, red: 1.0, green: 0.76, blue: 0.2)
}

extension Font {
    static func grotesk(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        switch weight {
        case .semibold, .bold, .heavy, .black: .custom("SpaceGrotesk-Bold", size: size)
        case .medium: .custom("SpaceGrotesk-Medium", size: size)
        default: .custom("SpaceGrotesk-Regular", size: size)
        }
    }
}

struct Glyph: ButtonStyle {
    var tone: Color = .ink

    func makeBody(configuration: Configuration) -> some View {
        Face(configuration: configuration, tone: tone)
    }

    private struct Face: View {
        let configuration: ButtonStyleConfiguration
        let tone: Color
        @State private var hover = false
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(tone)
                .frame(width: 22, height: 22)
                .background(
                    tone.opacity(configuration.isPressed ? 0.2 : hover ? 0.1 : 0),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .opacity(enabled ? 1 : 0.35)
                .contentShape(Rectangle())
                .onHover { hover = $0 }
        }
    }
}

struct Apps: View {
    let windows: [Sky.Window]

    private var apps: [(pid: pid_t, name: String)] {
        var seen = Set<pid_t>()
        return windows.compactMap { seen.insert($0.pid).inserted ? ($0.pid, $0.app) : nil }
    }

    var body: some View {
        let apps = apps
        HStack(spacing: 3) {
            ForEach(apps.prefix(5), id: \.pid) { app in
                Image(app: app.pid)
                    .resizable()
                    .frame(width: 14, height: 14)
            }
            if apps.count > 5 {
                Text("+\(apps.count - 5)")
                    .font(.grotesk(10, .medium))
                    .opacity(0.7)
            }
        }
        .help(apps.map(\.name).joined(separator: ", "))
    }
}

extension Image {
    init(app pid: pid_t) {
        if let icon = NSRunningApplication(processIdentifier: pid)?.icon {
            self.init(nsImage: icon)
        } else {
            self.init(systemName: "macwindow")
        }
    }
}

struct Badge: View {
    let label: String
    let active: Bool

    var body: some View {
        Text(label)
            .font(.grotesk(11, .bold))
            .monospacedDigit()
            .frame(width: 26, height: 18)
            .foregroundStyle(active ? Color.paper : Color.ink)
            .background(active ? Color.ink : Color.wash, in: RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(active ? Color.clear : Color.mist))
    }
}

struct Ticker: View {
    let text: String
    let rolling: Bool
    @State private var room: CGFloat = 0
    @State private var full: CGFloat = 0
    @State private var shift: CGFloat = 0
    @State private var moving = false
    private static let gap: CGFloat = 32

    var body: some View {
        Text(text)
            .lineLimit(1)
            .opacity(moving ? 0 : 1)
            .background(GeometryReader { proxy in
                Color.clear
                    .onAppear { room = proxy.size.width }
                    .onChange(of: proxy.size.width) { _, width in room = width }
            })
            .overlay(alignment: .leading) {
                HStack(spacing: Self.gap) {
                    Text(text)
                        .lineLimit(1)
                        .fixedSize()
                        .background(GeometryReader { proxy in
                            Color.clear
                                .onAppear { full = proxy.size.width }
                                .onChange(of: proxy.size.width) { _, width in full = width }
                        })
                    Text(text)
                        .lineLimit(1)
                        .fixedSize()
                }
                .offset(x: shift)
                    .opacity(moving ? 1 : 0)
            }
            .clipped()
            .task(id: rolling) {
                moving = false
                shift = 0
                guard rolling, full - room > 1 else { return }
                try? await Task.sleep(for: .milliseconds(500))
                let lap = full + Self.gap
                let duration = Double(lap / 40)
                while !Task.isCancelled {
                    moving = true
                    withAnimation(.linear(duration: duration)) { shift = -lap }
                    try? await Task.sleep(for: .seconds(duration))
                    guard !Task.isCancelled else { break }
                    shift = 0
                    try? await Task.sleep(for: .seconds(1.2))
                }
            }
    }
}
