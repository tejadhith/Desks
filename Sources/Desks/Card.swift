import SwiftUI

struct Card: View {
    @EnvironmentObject var store: Store
    @Binding var item: Item
    @State private var hover = false
    @State private var entry = ""
    @GestureState private var dragging = false
    @State private var click: Task<Void, Never>?
    @FocusState private var naming: Bool
    @FocusState private var field: Field?

    enum Field: Hashable {
        case todo(UUID)
        case add
    }

    private var space: Sky.Space? { store.space(for: item) }
    private var active: Bool { space?.id == store.current }
    private var targeted: Bool { space != nil && store.hovered == space?.id }
    private var windows: [Sky.Window] { space.map(store.windows(on:)) ?? [] }
    private var lifted: Bool { store.lift?.id == item.id }

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
                    Button(action: tap) {
                        HStack(spacing: 8) {
                            Badge(label: space?.number.map(String.init) ?? "–", active: active)
                            Ticker(text: item.title.isEmpty ? "Untitled" : item.title, rolling: hover && store.lift == nil)
                                .opacity(item.title.isEmpty ? 0.7 : 1)
                            if item.folded {
                                tally
                                Apps(windows: windows)
                            }
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .highPriorityGesture(
                        DragGesture(minimumDistance: 6, coordinateSpace: .named(Style.space))
                            .updating($dragging) { _, state, _ in state = true }
                            .onChanged { store.lift(item, by: $0.translation.height) }
                    )
                    .onChange(of: dragging) { _, now in
                        if !now { store.drop() }
                    }
                    .help(space == nil ? "Show details · double-click to rename · drag to reorder" : "Switch to this task's desktop · double-click to rename · drag to reorder")
                }
                Group {
                    if space == nil {
                        Button {
                            store.create(for: item)
                        } label: {
                            Image(systemName: "play.fill")
                        }
                        .help("Start · opens a new desktop for this task")
                        .disabled(store.busy || !store.trusted)
                    } else {
                        Button {
                            store.pull(item)
                        } label: {
                            Image(systemName: "rectangle.stack.badge.plus")
                        }
                        .help("Send the front window here")
                        .disabled(store.busy)
                    }
                    Button {
                        store.remove(item)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .help(space == nil ? "Delete task" : "Delete task · its windows move to Desktop 1")
                }
                .buttonStyle(Glyph())
                .opacity(hover || active ? 1 : 0.35)
                Button {
                    withAnimation(Style.fold(item.folded)) { item.folded.toggle() }
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
        .background(lifted ? Color.paper : .clear)
        .shadow(color: .black.opacity(lifted ? 0.3 : 0), radius: 8, y: 2)
        .overlay {
            if targeted { Rectangle().strokeBorder(Color.ink, lineWidth: 2) }
        }
        .zone(space?.id, in: store)
        .card(item.id, in: store)
        .onHover { hover = $0 }
        .contextMenu {
            if space == nil {
                Button("Start on New Desktop") { store.create(for: item) }
                    .disabled(store.busy)
            } else {
                Button("Switch to Task") { store.open(item) }
            }
            Button("Rename") { store.editing = item.id }
            Button(item.folded ? "Expand" : "Collapse") { item.folded.toggle() }
            Button("Send Front Window Here") { store.pull(item) }
                .disabled(space == nil)
            Button("Use Current Desktop") { store.claim(item) }
                .disabled(!store.claimable)
            if let space {
                ForEach(store.screens.filter { $0.id != space.display }, id: \.id) { screen in
                    Button("Move to \(screen.name)") { store.relocate(item, to: screen.id) }
                        .disabled(store.busy)
                }
            }
            Divider()
            Button("Delete Task", role: .destructive) { store.remove(item) }
        }
    }

    private func tap() {
        if let click {
            click.cancel()
            self.click = nil
            store.editing = item.id
            return
        }
        click = Task {
            try? await Task.sleep(for: .seconds(min(NSEvent.doubleClickInterval, 0.35)))
            guard !Task.isCancelled else { return }
            click = nil
            if space == nil {
                withAnimation(Style.fold(item.folded)) { item.folded.toggle() }
            } else {
                store.open(item)
            }
        }
    }

    @ViewBuilder
    private var tally: some View {
        if !item.todos.isEmpty {
            Text("\(item.todos.filter(\.done).count)/\(item.todos.count)")
                .font(.grotesk(10, .medium))
                .monospacedDigit()
                .opacity(0.7)
                .help("To-dos done")
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

        todos

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
                Text("Not started")
                    .opacity(0.7)
                Button("Start") { store.create(for: item) }
                    .underline()
                    .disabled(!store.trusted)
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

    private var todos: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(item.todos) { todo in
                Check(todo: binding(todo.id), focus: $field, step: step) {
                    tick(todo.id)
                } remove: {
                    item.todos.removeAll { $0.id == todo.id }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 14)
                    .opacity(0.6)
                TextField("Add a to-do", text: $entry, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($field, equals: .add)
                    .onSubmit(append)
                    .onKeyPress(.upArrow) { step(-1) }
                    .onExitCommand {
                        entry = ""
                        field = nil
                    }
            }
        }
        .font(.grotesk(12))
        .padding(.leading, Style.indent - 20)
        .onChange(of: field) { old, _ in
            guard case .todo(let id)? = old,
                  item.todos.first(where: { $0.id == id })?.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true
            else { return }
            item.todos.removeAll { $0.id == id }
        }
    }

    private func tick(_ id: UUID) {
        guard let index = item.todos.firstIndex(where: { $0.id == id }) else { return }
        item.todos[index].done.toggle()
        land(order[index + 1])
    }

    private func land(_ target: Field) {
        var done = false
        if case .todo(let id) = target { done = item.todos.first { $0.id == id }?.done ?? false }
        Panel.main?.expect { editor in
            editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
            Panel.main?.strike(editor, done)
        }
        field = target
    }

    private var order: [Field] {
        item.todos.map { .todo($0.id) } + [.add]
    }

    private func step(_ offset: Int) -> KeyPress.Result {
        guard let field, let index = order.firstIndex(of: field), order.indices.contains(index + offset) else { return .ignored }
        land(order[index + offset])
        return .handled
    }

    private func binding(_ id: UUID) -> Binding<Todo> {
        Binding {
            item.todos.first { $0.id == id } ?? Todo(id: id, text: "")
        } set: { todo in
            guard let index = item.todos.firstIndex(where: { $0.id == id }), item.todos[index] != todo else { return }
            item.todos[index] = todo
        }
    }

    private func append() {
        let text = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        entry = ""
        guard !text.isEmpty else { return }
        item.todos.append(Todo(text: text))
        DispatchQueue.main.async { field = .add }
    }
}

private struct Check: View {
    @Binding var todo: Todo
    let focus: FocusState<Card.Field?>.Binding
    let step: (Int) -> KeyPress.Result
    let tick: () -> Void
    let remove: () -> Void
    @State private var hover = false

    private var editing: Bool { focus.wrappedValue == .todo(todo.id) }
    private var struck: Bool { todo.done && !editing }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Button {
                if editing {
                    tick()
                } else {
                    withAnimation(.easeInOut(duration: 0.12)) { todo.done.toggle() }
                }
            } label: {
                Image(systemName: todo.done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(editing ? KeyboardShortcut(.return, modifiers: .command) : nil)
            .help(todo.done ? "Mark as not done · ⌘↩" : "Mark as done · ⌘↩")
            TextField("To-do", text: $todo.text, axis: .vertical)
                .textFieldStyle(.plain)
                .focused(focus, equals: .todo(todo.id))
                .onSubmit { focus.wrappedValue = nil }
                .onKeyPress(.upArrow) { step(-1) }
                .onKeyPress(.downArrow) { step(1) }
                .foregroundStyle(struck ? Color.clear : Color.ink)
                .opacity(todo.done && !struck ? 0.6 : 1)
                .onChange(of: editing) { _, now in
                    guard now, let panel = Panel.main, let editor = panel.firstResponder as? NSTextView, editor.string == todo.text else { return }
                    panel.strike(editor, todo.done)
                }
                .overlay(alignment: .topLeading) {
                    if struck {
                        Text(todo.text)
                            .strikethrough()
                            .opacity(0.6)
                            .allowsHitTesting(false)
                    }
                }
            Spacer(minLength: 0)
            Button(action: remove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .opacity(hover ? 0.7 : 0)
            .help("Remove to-do")
        }
        .onHover { hover = $0 }
    }
}
