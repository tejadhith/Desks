import SwiftUI

struct Note: View {
    @EnvironmentObject var store: Store
    @State private var draft: String?
    @FocusState private var typing: Bool
    @AppStorage("folded.upcoming") private var folded = false

    private var closed: Bool { folded && !store.peek.contains(.upcoming) }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.collapsed {
                if store.overflow {
                    ScrollViewReader { proxy in
                        ScrollView { list }
                            .scrollIndicators(.never)
                            .frame(height: store.limit)
                            .onAppear { reveal(proxy) }
                            .onChange(of: store.reveal) { reveal(proxy) }
                    }
                } else {
                    list
                        .onChange(of: store.reveal) { reveal(nil) }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(name: Style.space)
        .overlay(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                if let label = store.carrying.map({ $0.title.isEmpty ? $0.app : $0.title }) ?? store.held.map({ $0.title.isEmpty ? $0.agent.name : $0.title }) {
                    Text(label)
                        .font(.grotesk(11, .medium))
                        .lineLimit(1)
                        .frame(maxWidth: 180)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .foregroundStyle(Color.paper)
                        .background(Color.ink, in: RoundedRectangle(cornerRadius: 4))
                        .fixedSize()
                        .position(x: store.pointer.x, y: store.pointer.y - 14)
                }
            }
            .allowsHitTesting(false)
        }
        .background(Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.mist))
        .foregroundStyle(Color.ink)
        .tint(Color.ink)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var list: some View {
        VStack(spacing: 0) {
            if !store.trusted { locked }
            if let notice = store.notice { banner(notice) }
            if draft != nil { composer }
            ForEach($store.items) { $item in
                if store.started(item) {
                    VStack(spacing: 0) {
                        Card(item: $item)
                        line
                    }
                    .slide(item.id, in: store)
                }
            }
            if store.items.isEmpty && draft == nil { empty }
            ForEach(store.loose, id: \.id) { space in
                Loose(space: space, home: false)
                line
            }
            if let home = store.home {
                Loose(space: home, home: true)
            }
            ForEach(Agent.allCases.filter { !store.inbox($0).isEmpty || (store.held?.agent == $0 && store.running.contains($0)) }, id: \.self) { agent in
                line
                Inbox(agent: agent)
            }
            if !store.upcoming.isEmpty {
                line
                upcoming
                if !closed {
                    ForEach($store.items) { $item in
                        if !store.started(item) {
                            VStack(spacing: 0) {
                                line
                                Card(item: $item)
                            }
                            .slide(item.id, in: store)
                            .transition(store.rise(.upcoming))
                        }
                    }
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { store.height = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in store.height = height }
        })
        .onContinuousHover(coordinateSpace: .named(Style.space)) { phase in
            switch phase {
            case .active(let point): store.graze(point)
            case .ended: store.graze(nil)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            if let mark = Style.mark {
                Image(nsImage: mark)
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 15.6, height: 11.5)
            }
            Text("Tasks")
                .font(.grotesk(13, .semibold))
            Text("\(store.items.count)")
                .font(.grotesk(11, .medium))
                .monospacedDigit()
                .opacity(0.7)
            if let here = store.here {
                Text("·")
                    .font(.grotesk(11, .medium))
                    .opacity(0.4)
                Text(here)
                    .font(.grotesk(11, .medium))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .opacity(0.7)
                    .layoutPriority(-1)
                    .help("The desktop you are on")
            }
            if store.busy {
                ProgressView()
                    .controlSize(.mini)
                    .tint(Color.ink)
            }
            Spacer()
            if !store.anchored {
                Button {
                    store.snap()
                } label: {
                    Image(systemName: "arrow.up.right")
                }
                .help("Snap back to the top-right corner")
            }
            Button(action: begin) {
                Image(systemName: "plus")
            }
            .disabled(store.busy || !store.trusted)
            .help("New task")
            Button {
                store.collapsed.toggle()
            } label: {
                Image(systemName: store.collapsed ? "chevron.down" : "chevron.up")
            }
            .help(store.collapsed ? "Expand" : "Collapse")
        }
        .buttonStyle(Glyph())
        .padding(.horizontal, 12)
        .frame(height: Style.header)
        .background(Handle { store.collapsed.toggle() })
        .background(Color.deep)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            Badge(label: "+", active: false)
            TextField("What are you working on?", text: Binding(get: { draft ?? "" }, set: { draft = $0 }))
                .textFieldStyle(.plain)
                .font(.grotesk(13, .semibold))
                .focused($typing)
                .onSubmit { commit(later: false) }
                .onExitCommand { draft = nil }
                .onChange(of: typing) { _, now in
                    if !now && (draft ?? "").isEmpty { draft = nil }
                }
            Button {
                commit(later: true)
            } label: {
                Image(systemName: "tray.and.arrow.down")
            }
            .keyboardShortcut(typing ? KeyboardShortcut(.return, modifiers: .command) : nil)
            .help("Save for later · ⌘↩")
            Button {
                commit(later: false)
            } label: {
                Image(systemName: "play.fill")
            }
            .help("Start now on a new desktop · ↩")
        }
        .buttonStyle(Glyph())
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.wash)
    }

    private var upcoming: some View {
        HStack(spacing: 8) {
            Button(action: toss) {
                HStack(spacing: 8) {
                    Text("Upcoming")
                        .font(.grotesk(12, .medium))
                        .opacity(0.7)
                    Text("\(store.upcoming.count)")
                        .font(.grotesk(11, .medium))
                        .monospacedDigit()
                        .opacity(0.5)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: toss) {
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(closed ? 0 : 180))
            }
            .buttonStyle(Glyph())
            .opacity(0.8)
            .help(folded && store.peek.contains(.upcoming) ? "Keep expanded" : folded ? "Expand" : "Collapse")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.deep.opacity(0.35))
        .leaf(.upcoming, in: store)
    }

    private func toss() {
        store.toss(.upcoming)
    }

    private var locked: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
            Text("Allow Accessibility to manage desktops")
            Spacer()
            Button("Allow") {
                Access.prompt()
                Access.settings()
            }
            .buttonStyle(.plain)
            .font(.grotesk(12, .semibold))
            .underline()
        }
        .font(.grotesk(12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.wash)
    }

    private func banner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(Color.ink)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.grotesk(12))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.wash)
    }

    private var empty: some View {
        VStack(spacing: 4) {
            Text("No tasks yet")
                .font(.grotesk(12, .semibold))
            Text("Press + to start one on its own desktop")
                .font(.grotesk(11))
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var line: some View {
        Rectangle()
            .fill(Color.mist)
            .frame(height: 1)
    }

    private func reveal(_ proxy: ScrollViewProxy?) {
        DispatchQueue.main.async {
            guard let leaf = store.reveal, proxy != nil || !store.overflow else { return }
            store.reveal = nil
            guard let proxy, let (id, anchor) = store.scroll(to: leaf) else { return }
            withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(id, anchor: anchor) }
        }
    }

    private func begin() {
        draft = ""
        Panel.focus()
        DispatchQueue.main.async { typing = true }
    }

    private func commit(later: Bool) {
        let title = (draft ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        draft = nil
        guard !title.isEmpty else { return }
        if later { folded = false }
        store.add(title, later: later)
    }
}

struct Loose: View {
    @EnvironmentObject var store: Store
    @Environment(\.aside) private var aside
    let space: Sky.Space
    let home: Bool
    @AppStorage private var folded: Bool

    init(space: Sky.Space, home: Bool) {
        self.space = space
        self.home = home
        _folded = AppStorage(wrappedValue: false, "folded." + (home ? "home" : space.uuid))
    }

    private var windows: [Sky.Window] { store.windows(on: space) }
    private var targeted: Bool { store.hovered == space.id }
    private var closed: Bool { !aside && folded && !store.peek.contains(.desk(space.id)) }

    private var label: String {
        let kind = home ? "unsorted" : "not a task"
        return closed ? kind.prefix(1).uppercased() + kind.dropFirst() : "Desktop \(space.number ?? 0) · \(kind)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    store.open(space)
                } label: {
                    HStack(spacing: 8) {
                        Badge(label: space.number.map(String.init) ?? "–", active: store.current == space.id)
                        Text(label)
                            .font(.grotesk(12, .medium))
                            .lineLimit(1)
                            .opacity(0.7)
                            .contentTransition(.identity)
                        if closed && !store.moving(.desk(space.id)) {
                            Apps(windows: windows)
                                .transition(Store.blink)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if !home {
                    Button {
                        Panel.focus()
                        store.adopt(space)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(Glyph())
                    .help("Turn this desktop into a task")
                }
                Button {
                    store.toss(.desk(space.id))
                } label: {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(closed ? 0 : 180))
                }
                .buttonStyle(Glyph())
                .opacity(0.8)
                .help(folded && !closed ? "Keep expanded" : folded ? "Expand" : "Collapse")
            }
            if !closed {
                VStack(spacing: 0) {
                    ForEach(windows) { Row(window: $0) }
                }
                .padding(.leading, Style.indent - 6)
                .transition(store.rise(.desk(space.id)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, closed ? 6 : 10)
        .background(targeted ? Color.mist : .clear)
        .clipped()
        .overlay {
            if targeted { Rectangle().strokeBorder(Color.ink, lineWidth: 2) }
        }
        .zone(space.id, in: store)
        .leaf(.desk(space.id), in: store)
        .contextMenu {
            if !home {
                Button("Remove Desktop", role: .destructive) { store.remove(space) }
                    .disabled(store.busy)
            }
        }
    }
}
