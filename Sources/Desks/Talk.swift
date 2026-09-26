import SwiftUI

struct Talk: View {
    @EnvironmentObject var store: Store
    let chat: Chat
    let item: Item?
    @State private var hover = false

    private var title: String { chat.title.isEmpty ? "Untitled" : chat.title }
    private var status: Status? { store.beats[chat.id]?.status }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                store.open(chat, in: item)
            } label: {
                HStack(spacing: 6) {
                    Image(agent: chat.agent)
                        .resizable()
                        .frame(width: 14, height: 14)
                    Text(title)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    if let status { Dot(status: status) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .highPriorityGesture(
                DragGesture(minimumDistance: 4, coordinateSpace: .named(Style.space))
                    .onChanged { store.track(chat, at: $0.location) }
                    .onEnded { store.release(chat, at: $0.location) }
            )
            .help("\(chat.agent.name) · \(title)\(status.map { " · " + $0.label } ?? "") · click to open\(item == nil ? " where \(chat.agent.name) is" : " on this task's desktop") · drag to a task")
            if item != nil {
                Button {
                    store.detach(chat)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hover ? 0.7 : 0)
                .help("Unlink from this task")
            }
        }
        .font(.grotesk(11))
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(Color.ink.opacity(hover ? 0.12 : 0), in: RoundedRectangle(cornerRadius: 4))
        .opacity(store.held?.id == chat.id ? 0.4 : 1)
        .onHover { hover = $0 }
        .contextMenu {
            Menu("Move to") {
                ForEach(store.homes(for: chat)) { home in
                    Button(home.title.isEmpty ? "Untitled" : home.title) { store.attach(chat, to: home.id) }
                }
            }
            .disabled(store.homes(for: chat).isEmpty)
            if item != nil {
                Button("Unlink") { store.detach(chat) }
            }
        }
    }
}

struct Inbox: View {
    @EnvironmentObject var store: Store
    let agent: Agent
    @AppStorage private var folded: Bool

    init(agent: Agent) {
        self.agent = agent
        _folded = AppStorage(wrappedValue: false, "folded.agent." + agent.rawValue)
    }

    private var chats: [Chat] { store.inbox(agent) }
    private var targeted: Bool { store.aim == .inbox(agent) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    withAnimation(Style.fold(folded)) { folded.toggle() }
                } label: {
                    HStack(spacing: 8) {
                        Image(agent: agent)
                            .resizable()
                            .frame(width: 22, height: 22)
                            .frame(width: 26, height: 18)
                        Text(folded ? agent.name : "\(agent.name) · unsorted")
                            .font(.grotesk(12, .medium))
                            .lineLimit(1)
                            .opacity(0.7)
                        Text("\(chats.count)")
                            .font(.grotesk(11, .medium))
                            .monospacedDigit()
                            .opacity(0.5)
                        if folded, let status = Status.urgent(chats.compactMap { store.beats[$0.id]?.status }) {
                            Dot(status: status)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Conversations in \(agent.name) not linked to a task · drag one onto a task")
                Button {
                    withAnimation(Style.fold(folded)) { folded.toggle() }
                } label: {
                    Image(systemName: folded ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(Glyph())
                .opacity(0.8)
                .help(folded ? "Expand" : "Collapse")
            }
            if !folded && !chats.isEmpty {
                VStack(spacing: 0) {
                    ForEach(chats) { Talk(chat: $0, item: nil) }
                }
                .padding(.leading, Style.indent - 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, folded || chats.isEmpty ? 6 : 10)
        .background(targeted ? Color.mist : .clear)
        .overlay {
            if targeted { Rectangle().strokeBorder(Color.ink, lineWidth: 2) }
        }
        .inbox(agent, in: store)
    }
}

struct Dot: View {
    let status: Status

    var body: some View {
        Group {
            switch status {
            case .running:
                Spin()
            case .waiting:
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color.amber)
            case .done:
                Image(systemName: "checkmark.circle")
            case .idle, .ended:
                Circle()
                    .stroke(Color.ink.opacity(0.3), lineWidth: 1.6)
                    .frame(width: 9, height: 9)
            }
        }
        .font(.system(size: 10, weight: .semibold))
        .frame(width: 14, height: 14)
        .help(status.label)
        .accessibilityHidden(true)
    }
}

private struct Spin: View {
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1)
            ZStack {
                Circle()
                    .stroke(Color.ink.opacity(0.3), lineWidth: 1.6)
                Circle()
                    .trim(from: 0, to: 0.3)
                    .stroke(Color.ink, style: StrokeStyle(lineWidth: 1.6, lineCap: .round))
                    .rotationEffect(.degrees(turn * 360))
            }
            .frame(width: 9, height: 9)
        }
    }
}

extension Status {
    static func urgent(_ statuses: [Status]) -> Status? {
        [.waiting, .running, .done].first { statuses.contains($0) }
    }
}

extension Image {
    @MainActor
    init(agent: Agent) {
        if let icon = Icons.all[agent] ?? agent.icon {
            Icons.all[agent] = icon
            self.init(nsImage: icon)
        } else {
            self.init(systemName: "bubble.left")
        }
    }
}

@MainActor
private enum Icons {
    static var all: [Agent: NSImage] = [:]
}
