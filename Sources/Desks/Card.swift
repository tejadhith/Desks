import SwiftUI

struct Card: View {
    @EnvironmentObject var store: Store
    @Binding var item: Item
    @State private var hover = false
    @FocusState private var naming: Bool

    private var space: Sky.Space? { store.space(for: item) }
    private var active: Bool { space?.id == store.current }
    private var targeted: Bool { space != nil && store.hovered == space?.id }
    private var windows: [Sky.Window] { space.map(store.windows(on:)) ?? [] }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if store.editing == item.id {
                    Badge(label: space?.number.map(String.init) ?? "–", active: active)
                    TextField("Task name", text: $item.title)
                        .textFieldStyle(.plain)
                        .focused($naming)
                        .onSubmit { store.editing = nil }
                        .onExitCommand { store.editing = nil }
                        .onChange(of: naming) { _, now in
                            if !now { store.editing = nil }
                        }
                        .onAppear {
                            Panel.focus()
                            DispatchQueue.main.async { naming = true }
                        }
                } else {
                    Button {
                        store.open(item)
                    } label: {
                        HStack(spacing: 8) {
                            Badge(label: space?.number.map(String.init) ?? "–", active: active)
                            Text(item.title.isEmpty ? "Untitled" : item.title)
                                .lineLimit(1)
                                .opacity(item.title.isEmpty ? 0.7 : 1)
                            if item.folded { Apps(windows: windows) }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Switch to this task's desktop")
                }
                Group {
                    Button {
                        store.pull(item)
                    } label: {
                        Image(systemName: "rectangle.stack.badge.plus")
                    }
                    .help("Send the front window here")
                    .disabled(space == nil || store.busy)
                    Button {
                        store.remove(item)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help("Delete task · its windows move to Desktop 1")
                }
                .buttonStyle(Glyph())
                .opacity(hover || active ? 1 : 0.35)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { item.folded.toggle() }
                } label: {
                    Image(systemName: item.folded ? "chevron.down" : "chevron.up")
                }
                .buttonStyle(Glyph())
                .opacity(0.8)
                .help(item.folded ? "Expand" : "Collapse")
            }
            .font(.grotesk(13, .semibold))
            .frame(minHeight: 22)

            if !item.folded { details }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, item.folded ? 6 : 10)
        .background(targeted ? Color.mist : active ? Color.wash : .clear)
        .overlay {
            if targeted { Rectangle().strokeBorder(Color.ink, lineWidth: 2) }
        }
        .zone(space?.id, in: store)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Switch to Task") { store.open(item) }
                .disabled(space == nil)
            Button("Rename") { store.editing = item.id }
            Button(item.folded ? "Expand" : "Collapse") { item.folded.toggle() }
            Button("Send Front Window Here") { store.pull(item) }
                .disabled(space == nil)
            Button("Use Current Desktop") { store.claim(item) }
                .disabled(!store.claimable)
            Divider()
            Button("Delete Task", role: .destructive) { store.remove(item) }
        }
    }

    @ViewBuilder
    private var details: some View {
        if let number = space?.number {
            Text(["Desktop \(number)", store.screen(of: space), store.shortcut(for: space)].compactMap { $0 }.joined(separator: " · "))
                .font(.grotesk(11, .medium))
                .opacity(0.7)
                .padding(.leading, Style.indent)
        }

        TextField("Add a description", text: $item.detail, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.grotesk(12))
            .lineLimit(1...8)
            .padding(.leading, Style.indent)

        if let space {
            if windows.isEmpty {
                Text("No windows yet · drag onto Desktop \(space.number ?? 0) in Mission Control")
                    .font(.grotesk(11))
                    .opacity(0.7)
                    .padding(.leading, Style.indent)
            } else {
                VStack(spacing: 0) {
                    ForEach(windows) { Row(window: $0) }
                }
                .padding(.leading, Style.indent - 6)
            }
        } else {
            HStack(spacing: 12) {
                Text("No desktop")
                    .opacity(0.7)
                Button("New desktop") { store.create(for: item) }
                    .underline()
                Button("Use current") { store.claim(item) }
                    .underline()
                    .disabled(!store.claimable)
            }
            .buttonStyle(.plain)
            .font(.grotesk(11, .medium))
            .padding(.leading, Style.indent)
            .disabled(store.busy)
        }
    }
}
