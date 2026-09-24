import SwiftUI

struct Note: View {
    @EnvironmentObject var store: Store
    @State private var draft: String?
    @FocusState private var typing: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if !store.collapsed {
                if store.overflow {
                    ScrollView { list }
                        .scrollIndicators(.never)
                        .frame(height: store.limit)
                } else {
                    list
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .coordinateSpace(name: Style.space)
        .overlay(alignment: .topLeading) {
            if let window = store.carrying {
                Text(window.title.isEmpty ? window.app : window.title)
                    .font(.grotesk(11, .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 180)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .foregroundStyle(Color.paper)
                    .background(Color.ink, in: RoundedRectangle(cornerRadius: 4))
                    .fixedSize()
                    .position(x: store.pointer.x, y: store.pointer.y - 14)
                    .allowsHitTesting(false)
            }
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
                Card(item: $item)
                line
            }
            if store.items.isEmpty && draft == nil { empty }
            ForEach(store.loose, id: \.id) { space in
                Loose(space: space, home: false)
                line
            }
            if let home = store.home {
                Loose(space: home, home: true)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { proxy in
            Color.clear
                .onAppear { store.height = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in store.height = height }
        })
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "note.text")
                .font(.grotesk(13, .semibold))
            Text("Tasks")
                .font(.grotesk(13, .semibold))
            Text("\(store.items.count)")
                .font(.grotesk(11, .medium))
                .monospacedDigit()
                .opacity(0.7)
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
            .help("New task on a new desktop")
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
        .background(Handle())
        .background(Color.deep)
    }

    private var composer: some View {
        HStack(spacing: 8) {
            Badge(label: "+", active: false)
            TextField("What are you working on?", text: Binding(get: { draft ?? "" }, set: { draft = $0 }))
                .textFieldStyle(.plain)
                .font(.grotesk(13, .semibold))
                .focused($typing)
                .onSubmit(commit)
                .onExitCommand { draft = nil }
                .onChange(of: typing) { _, now in
                    if !now && (draft ?? "").isEmpty { draft = nil }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.wash)
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

    private func begin() {
        draft = ""
        Panel.focus()
        DispatchQueue.main.async { typing = true }
    }

    private func commit() {
        let title = (draft ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        draft = nil
        if !title.isEmpty { store.add(title) }
    }
}

private struct Loose: View {
    @EnvironmentObject var store: Store
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

    private var label: String {
        let kind = home ? "unsorted" : "not a task"
        return folded ? kind.prefix(1).uppercased() + kind.dropFirst() : "Desktop \(space.number ?? 0) · \(kind)"
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
                        if folded { Apps(windows: windows) }
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
                    withAnimation(.easeInOut(duration: 0.15)) { folded.toggle() }
                } label: {
                    Image(systemName: folded ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(Glyph())
                .opacity(0.8)
                .help(folded ? "Expand" : "Collapse")
            }
            if !folded {
                VStack(spacing: 0) {
                    ForEach(windows) { Row(window: $0) }
                }
                .padding(.leading, Style.indent - 6)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, folded ? 6 : 10)
        .background(targeted ? Color.mist : .clear)
        .overlay {
            if targeted { Rectangle().strokeBorder(Color.ink, lineWidth: 2) }
        }
        .zone(space.id, in: store)
    }
}
