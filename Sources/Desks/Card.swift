import SwiftUI

private let erase = KeyEquivalent("\u{7F}")

struct Card: View {
    @EnvironmentObject var store: Store
    @Environment(\.aside) private var aside
    @Environment(\.fewer) private var fewer
    @Environment(\.tidy) private var tidy
    @Binding var item: Item
    @State private var hover = false
    @State private var entry = ""
    @GestureState private var dragging = false
    @State private var click: Task<Void, Never>?
    @FocusState private var naming: Bool
    @FocusState private var field: Field?
    @AppStorage("glass") private var glass = "blue"

    private var all: Bool { !tidy && store.all.contains(item.id) }
    private var more: Bool { !fewer && store.more.contains(item.id) }

    enum Field: Hashable {
        case todo(UUID)
        case add
    }

    private var space: Sky.Space? { store.space(for: item) }
    private var active: Bool { space?.id == store.current }
    private var targeted: Bool { (space != nil && store.hovered == space?.id) || store.aim == .card(item.id) }
    private var windows: [Sky.Window] { space.map(store.windows(on:)) ?? [] }
    private var lifted: Bool { store.lift?.id == item.id }
    private var folded: Bool { !aside && item.folded && !store.peek.contains(.task(item.id)) }
    private var pinning: Bool { item.folded && store.peek.contains(.task(item.id)) }
    private var label: String { pinning ? "Keep expanded" : item.folded ? "Expand" : "Collapse" }
    private static let cap = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: folded && store.editing != item.id ? .center : .firstTextBaseline, spacing: 8) {
                if store.editing == item.id {
                    Badge(label: space?.number.map(String.init) ?? "–", active: active)
                    TextField("Task name", text: $item.title, prompt: Text(""), axis: .vertical)
                        .hint("Task name", item.title.isEmpty)
                        .textFieldStyle(.plain)
                        .wrap(item.title)
                        .focused($naming)
                        .onSubmit { store.editing = nil }
                        .onExitCommand { store.editing = nil }
                        .onChange(of: naming) { _, now in
                            if !now { store.editing = nil }
                        }
                        .onChange(of: item.title) { _, title in
                            if title.contains(where: \.isNewline) { item.title = title.split(whereSeparator: \.isNewline).joined(separator: " ") }
                        }
                        .onAppear {
                            Panel.focus()
                            DispatchQueue.main.async { naming = true }
                        }
                } else {
                    Button(action: tap) {
                        HStack(alignment: folded ? .center : .firstTextBaseline, spacing: 8) {
                            Badge(label: space?.number.map(String.init) ?? "–", active: active)
                            Text(item.title.isEmpty ? "Untitled" : item.title)
                                .lineLimit(folded ? 1 : nil)
                                .fixedSize(horizontal: false, vertical: !folded)
                                .frame(maxWidth: folded ? nil : .infinity, alignment: .leading)
                                .opacity(item.title.isEmpty ? 0.7 : 1)
                            if folded && !store.moving(.task(item.id)) {
                                Group {
                                    tally
                                    Apps(windows: windows)
                                    if let status = Status.urgent(item.chats.compactMap { store.beats[$0.id]?.status }) {
                                        Dot(status: status)
                                    }
                                }
                                .transition(Store.blink)
                            }
                            if folded { Spacer(minLength: 0) }
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
                        .disabled(!store.trusted)
                    } else {
                        Button {
                            store.pull(item)
                        } label: {
                            Image(systemName: "rectangle.stack.badge.plus")
                        }
                        .help("Send the front window here")
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
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Style.line }
                Button(action: toss) {
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(folded ? 0 : 180))
                }
                .buttonStyle(Glyph())
                .opacity(0.8)
                .help(label)
                .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + Style.line }
            }
            .font(.grotesk(13, .semibold))
            .frame(minHeight: 22)
            .contentTransition(.identity)

            if !folded {
                Group { details }
                    .transition(store.rise(.task(item.id)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, folded ? 6 : 10)
        .plate(targeted ? .mist : active ? glass == "clear" ? .paper.opacity(0.6) : .wash : .clear, ring: targeted)
        .background {
            Style.plate
                .fill(lifted ? glass == "clear" ? AnyShapeStyle(.thickMaterial) : AnyShapeStyle(Color.paper) : AnyShapeStyle(.clear))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
        }
        .clipped()
        .shadow(color: .black.opacity(lifted ? 0.3 : 0), radius: 8, y: 2)
        .zone(space?.id, in: store)
        .card(item.id, in: store)
        .leaf(.task(item.id), in: store)
        .onHover { hover = $0 }
        .contextMenu {
            if space == nil {
                Button("Start") { store.create(for: item) }
                    .disabled(store.busy)
            } else {
                Button("Switch to Task") { store.open(item) }
            }
            Button("Rename") { store.editing = item.id }
            Button(label, action: toss)
            Button("Send Front Window Here") { store.pull(item) }
                .disabled(space == nil)
            Button("Use Current Desktop") { store.claim(item) }
                .disabled(!store.claimable)
            if let space {
                ForEach(store.screens.filter { $0.id != space.display }, id: \.id) { screen in
                    Button("Move to \(screen.name)") { store.relocate(item, to: screen.id) }
                        .disabled(store.busy)
                }
                Button("Move to Upcoming") { store.postpone(item) }
                    .disabled(store.busy)
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
                toss()
            } else {
                store.open(item)
            }
        }
    }

    private func toss() {
        store.toss(.task(item.id))
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

        TextField("Add a description", text: $item.detail, prompt: Text(""), axis: .vertical)
            .hint("Add a description", item.detail.isEmpty)
            .textFieldStyle(.plain)
            .lineLimit(1...8)
            .wrap(item.detail, lines: 8)
            .font(.grotesk(12))
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
        }

        if !item.chats.isEmpty {
            if space != nil {
                Rectangle()
                    .fill(Color.ink.opacity(0.14))
                    .frame(height: 1)
                    .padding(.leading, Style.indent - 6)
            }
            VStack(spacing: 0) {
                ForEach(store.chats(of: item, keep: more ? nil : Self.cap)) { Talk(chat: $0, item: item) }
                if item.chats.count > Self.cap {
                    Button {
                        store.trim(item.id, done: false)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: more ? "chevron.up" : "ellipsis")
                                .font(.system(size: 9, weight: .bold))
                                .frame(width: 14, height: 14)
                            Text(more ? "Show fewer" : "\(item.chats.count - Self.cap) more")
                            Spacer(minLength: 0)
                        }
                        .font(.grotesk(11))
                        .opacity(0.6)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(more ? "Show only the most recent" : "Show every conversation")
                }
            }
            .padding(.leading, Style.indent - 6)
        }
    }

    private var todos: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !item.todos.isEmpty {
                Button {
                    withAnimation(Style.fold(item.shelved)) { item.shelved.toggle() }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: item.shelved ? "chevron.right" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 14)
                            .opacity(0.7)
                        Text("To-dos")
                            .font(.grotesk(12, .medium))
                            .opacity(0.7)
                        Text("\(item.todos.filter(\.done).count)/\(item.todos.count)")
                            .font(.grotesk(12, .medium))
                            .monospacedDigit()
                            .opacity(0.5)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(item.shelved ? "Show to-dos" : "Hide to-dos")
            }
            if !item.shelved || item.todos.isEmpty { list }
        }
        .font(.grotesk(12))
        .padding(.leading, Style.indent - 20)
        .shelf(item.id, in: store)
        .onChange(of: field) { old, _ in
            if old == .add { commit() }
            guard case .todo(let id)? = old, let at = item.todos.firstIndex(where: { $0.id == id }) else { return }
            let text = item.todos[at].text.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty {
                item.todos.remove(at: at)
            } else if text != item.todos[at].text {
                item.todos[at].text = text
            }
        }
    }

    @ViewBuilder
    private var list: some View {
        ForEach(open) { check($0) }
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "plus")
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 14)
                .opacity(0.6)
            TextField("Add a to-do", text: $entry, prompt: Text(""), axis: .vertical)
                .hint("Add a to-do", entry.isEmpty)
                .textFieldStyle(.plain)
                .wrap(entry)
                .focused($field, equals: .add)
                .onSubmit(append)
                .onKeyPress(.upArrow) { step(-1) }
                .onKeyPress(.downArrow) { step(1) }
                .onKeyPress(erase) { back() }
                .onExitCommand {
                    entry = ""
                    field = nil
                }
        }
        if !shut.isEmpty {
            Button {
                store.trim(item.id, done: true)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: all ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 14)
                        .opacity(0.5)
                    Text("\(shut.count) done")
                        .font(.grotesk(12, .medium))
                        .opacity(0.5)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(all ? "Hide what's done" : "Show what's done")
            if all {
                ForEach(shut) { check($0) }
            }
        }
    }

    private func check(_ todo: Todo) -> some View {
        Check(todo: binding(todo.id), owner: item.id, focus: $field, step: step, back: back, split: split) {
            tick(todo.id)
        } remove: {
            item.todos.removeAll { $0.id == todo.id }
        }
        .glide(todo.id, in: store)
    }

    private func tick(_ id: UUID) {
        guard let index = item.todos.firstIndex(where: { $0.id == id }) else { return }
        let next = order.firstIndex(of: .todo(id)).map { order[min($0 + 1, order.count - 1)] } ?? .add
        item.todos[index].done.toggle()
        if item.todos[index].done {
            Archive.log(item.todos[index], in: item)
        } else {
            Archive.undo(item.todos[index], in: item)
        }
        land(next)
    }

    private func land(_ target: Field, at caret: Int? = nil) {
        var done = false
        if case .todo(let id) = target { done = item.todos.first { $0.id == id }?.done ?? false }
        Panel.main?.expect { editor in
            let length = (editor.string as NSString).length
            editor.setSelectedRange(NSRange(location: min(caret ?? length, length), length: 0))
            Panel.main?.strike(editor, done)
        }
        field = target
    }

    private var open: [Todo] { item.todos.filter { !$0.done } }
    private var shut: [Todo] { item.todos.filter(\.done) }

    private var order: [Field] {
        open.map { .todo($0.id) } + [.add] + (all ? shut.map { .todo($0.id) } : [])
    }

    private func step(_ offset: Int) -> KeyPress.Result {
        guard let field, let index = order.firstIndex(of: field), order.indices.contains(index + offset), edge(offset) else { return .ignored }
        land(order[index + offset])
        return .handled
    }

    private func split() -> KeyPress.Result {
        guard case .todo(let id)? = field, let at = item.todos.firstIndex(where: { $0.id == id }) else { return .ignored }
        let text = item.todos[at].text as NSString
        guard text.length > 0 else {
            field = nil
            return .handled
        }
        let cut = min(editor?.selectedRange().location ?? text.length, text.length)
        var todos = item.todos
        let rest = Todo(text: text.substring(from: cut), done: todos[at].done)
        todos[at].text = text.substring(to: cut)
        todos.insert(rest, at: at + 1)
        item.todos = todos
        land(.todo(rest.id), at: 0)
        return .handled
    }

    private func back() -> KeyPress.Result {
        guard let field, let index = order.firstIndex(of: field), index > 0 else { return .ignored }
        let above = order[index - 1]
        if case .todo(let id) = field {
            guard let todo = item.todos.first(where: { $0.id == id }) else { return .ignored }
            if todo.text.isEmpty {
                item.todos.removeAll { $0.id == id }
            } else {
                guard head else { return .ignored }
                if case .todo(let over) = above, let at = item.todos.firstIndex(where: { $0.id == over }), item.todos[at].done == todo.done {
                    var todos = item.todos
                    let join = (todos[at].text as NSString).length
                    todos[at].text += todo.text
                    todos.removeAll { $0.id == id }
                    item.todos = todos
                    land(above, at: join)
                    return .handled
                }
            }
        } else {
            guard entry.isEmpty || head else { return .ignored }
        }
        land(above)
        return .handled
    }

    private var editor: NSTextView? { Panel.main?.firstResponder as? NSTextView }

    private var head: Bool {
        editor?.selectedRange() == NSRange(location: 0, length: 0)
    }

    private func edge(_ offset: Int) -> Bool {
        guard let editor else { return true }
        let length = (editor.string as NSString).length
        guard length > 0 else { return true }
        return line(editor, editor.selectedRange().location) == line(editor, offset < 0 ? 0 : length)
    }

    private func line(_ editor: NSTextView, _ at: Int) -> CGFloat {
        editor.firstRect(forCharacterRange: NSRange(location: at, length: 0), actualRange: nil).minY
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
        guard commit() else { return }
        DispatchQueue.main.async { field = .add }
    }

    @discardableResult
    private func commit() -> Bool {
        let text = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        entry = ""
        guard !text.isEmpty else { return false }
        item.todos.append(Todo(text: text))
        return true
    }
}

private struct Check: View {
    @EnvironmentObject var store: Store
    @Binding var todo: Todo
    let owner: UUID
    let focus: FocusState<Card.Field?>.Binding
    let step: (Int) -> KeyPress.Result
    let back: () -> KeyPress.Result
    let split: () -> KeyPress.Result
    let tick: () -> Void
    let remove: () -> Void
    @State private var hover = false
    @GestureState private var hauling = false

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
            .highPriorityGesture(
                DragGesture(minimumDistance: 6, coordinateSpace: .named(Style.space))
                    .updating($hauling) { _, state, _ in state = true }
                    .onChanged { store.tug(todo.id, in: owner, by: $0.translation.height) }
            )
            .onChange(of: hauling) { _, now in
                if !now { store.shed() }
            }
            .help(todo.done ? "Mark as not done · ⌘↩ · drag to reorder" : "Mark as done · ⌘↩ · drag to reorder")
            TextField("To-do", text: $todo.text, prompt: Text(""), axis: .vertical)
                .hint("To-do", todo.text.isEmpty)
                .textFieldStyle(.plain)
                .focused(focus, equals: .todo(todo.id))
                .onKeyPress(.return) { split() }
                .onKeyPress(.upArrow) { step(-1) }
                .onKeyPress(.downArrow) { step(1) }
                .onKeyPress(erase) { back() }
                .onExitCommand { focus.wrappedValue = nil }
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
                .wrap(todo.text)
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
        .row(todo.id, in: store)
        .onHover { hover = $0 }
    }
}
