import SwiftUI

struct Row: View {
    @EnvironmentObject var store: Store
    let window: Sky.Window
    @State private var hover = false

    var body: some View {
        Button {
            store.focus(window)
        } label: {
            HStack(spacing: 6) {
                Image(app: window.pid)
                    .resizable()
                    .frame(width: 14, height: 14)
                Text(window.title.isEmpty ? window.app : window.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .font(.grotesk(11))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(hover ? Color.ink.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .highPriorityGesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .named(Style.space))
                .onChanged { store.track(window, at: $0.location) }
                .onEnded { store.release(window, at: $0.location) }
        )
        .opacity(store.carrying?.id == window.id ? 0.4 : 1)
        .onHover { hover = $0 }
        .help(window.title.isEmpty ? window.app : "\(window.app) · \(window.title)")
        .contextMenu {
            Menu("Send to") {
                ForEach(store.targets(for: window), id: \.space.id) { target in
                    Button("\(target.name) · Desktop \(target.space.number ?? 0)") {
                        store.send(window, to: target.space)
                    }
                }
            }
            .disabled(store.targets(for: window).isEmpty || store.busy)
        }
    }
}
