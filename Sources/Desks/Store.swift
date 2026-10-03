import AppKit
import SwiftUI

struct Lift: Equatable {
    let id: UUID
    let order: [UUID]
    let frames: [UUID: CGRect]
    var shift: CGFloat = 0
    var slot: Int
    var owner: UUID?
}

struct Anchor {
    let leaf: Leaf
    var y: CGFloat
    let until: Date
}

enum Aim: Equatable {
    case card(UUID)
    case inbox(Agent)
}

enum Leaf: Hashable {
    case task(UUID)
    case desk(UInt64)
    case unsorted(Agent)
    case upcoming
}

@MainActor
final class Store: ObservableObject {
    @Published var items: [Item] {
        didSet {
            save()
            forget(oldValue)
        }
    }
    @Published private(set) var spaces: [Sky.Space] = []
    @Published private(set) var windows: [Sky.Window] = []
    @Published private(set) var current: UInt64 = 0
    @Published private(set) var trusted = Access.trusted
    @Published private(set) var busy = false
    @Published private(set) var notice: String?
    @Published var editing: UUID?
    @Published var collapsed = false
    @Published var anchored = true
    @Published var height: CGFloat = 0
    @Published var overflow = false
    @Published var limit: CGFloat = 600
    var scrolled: CGFloat = 0
    @Published private(set) var lead: CGFloat = 0
    @Published private(set) var clock: Double = 0
    @Published private(set) var carrying: Sky.Window?
    @Published private(set) var pointer: CGPoint = .zero
    @Published private(set) var lift: Lift?
    @Published private(set) var tug: Lift?
    @Published private(set) var peek: Set<Leaf> = []
    @Published var all: Set<UUID> = []
    @Published var more: Set<UUID> = []
    @Published var reveal: Leaf?
    @Published private(set) var rises: [Leaf: CGFloat] = [:]
    private(set) var sinking: Date?
    private var turn = 0
    private var leaves: [Leaf: CGRect] = [:]
    private var low: [Leaf: CGFloat] = [:]
    private var high: [Leaf: CGFloat] = [:]
    private var anchor: Anchor?
    private var tried: Set<Leaf> = []
    private var priming: Task<Void, Never>?
    private let glide = Glide()
    private var dwell: Task<Void, Never>?
    private var spot: CGPoint?
    private var mark: CGPoint?
    private var muted: Leaf?
    private var cards: [UUID: CGRect] = [:]
    private var rows: [UUID: CGRect] = [:]
    private var shelves: [UUID: CGRect] = [:]
    private var owners: [String: UUID] = [:]
    @Published private(set) var hovered: UInt64?
    @Published private(set) var front: UInt32?
    @Published private(set) var starting: UUID?
    @Published private(set) var beats: [String: Beat] = [:]
    @Published private(set) var named: [String: String] = [:]
    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var active: [String: Date] = [:]
    @Published private(set) var running: Set<Agent> = []
    @Published private(set) var held: Chat?
    @Published private(set) var aim: Aim?
    private var zones: [UInt64: CGRect] = [:]
    private var inboxes: [Agent: CGRect] = [:]
    private var looked: [String: Date] = [:]
    private var sifted: [String: Date] = [:]
    private var sorting = false
    private var known: Set<UUID>?
    var snap: () -> Void = {}

    private let url: URL
    private var titles: [UInt32: String] = [:]
    private var fronts: [UInt64: Sky.Window] = [:]
    private var leads: [UInt64: UInt32] = [:]
    private var loop: Task<Void, Never>?
    private var scout: Scout?
    private var stirring: Task<Void, Never>?
    private var stirs = 0
    private var sense: Task<Void, Never>?
    private var ear: Task<Void, Never>?
    private var again = false
    private var seen = Hooks.Seen()
    private var watches: [URL: Watch] = [:]
    private var observers: [NSObjectProtocol] = []
    @Published private var lost: Set<UUID> = []
    private var returning: Set<UUID> = []

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Desks", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("items.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([Item].self, from: Data(contentsOf: url))) ?? []
        spaces = Sky.spaces()
        current = Sky.current()
        start()
    }

    var desktops: [Sky.Space] {
        spaces.filter { $0.number != nil }
    }

    var home: Sky.Space? {
        desktops.first
    }

    var loose: [Sky.Space] {
        let linked = Set(items.compactMap { space(for: $0)?.uuid })
        return desktops.dropFirst().filter { !linked.contains($0.uuid) }
    }

    var claimable: Bool {
        current != home?.id && !items.contains { space(for: $0)?.id == current }
    }

    var here: String? {
        here(on: current)?.name
    }

    func here(on id: UInt64) -> (space: Sky.Space, name: String)? {
        guard let space = spaces.first(where: { $0.id == id }), let number = space.number else { return nil }
        let item = items.first { self.space(for: $0)?.id == id }
        return (space, item.map { $0.title.isEmpty ? "Untitled" : $0.title } ?? "Desktop \(number)")
    }

    var upcoming: [Item] {
        items.filter { !started($0) }
    }

    func started(_ item: Item) -> Bool {
        starting == item.id || lost.contains(item.id) || space(for: item) != nil
    }

    func space(for item: Item) -> Sky.Space? {
        guard let uuid = item.space, let space = spaces.first(where: { $0.uuid == uuid }), space != home else { return nil }
        return space
    }

    func windows(on space: Sky.Space) -> [Sky.Window] {
        windows.filter { $0.space == space.id }
    }

    var linked: Set<String> {
        Set(items.flatMap { $0.chats.map(\.id) })
    }

    func inbox(_ agent: Agent) -> [Chat] {
        guard running.contains(agent) else { return [] }
        let cutoff = Date().addingTimeInterval(-86400)
        let linked = linked
        return beats.values
            .filter { $0.agent == agent && !linked.contains($0.id) && !hidden.contains($0.id) }
            .map { (beat: $0, time: latest($0)) }
            .filter { $0.time > cutoff }
            .sorted { $0.time > $1.time }
            .map { Chat(agent: $0.beat.agent, session: $0.beat.session, title: named[$0.beat.id] ?? "") }
    }

    private func latest(_ beat: Beat) -> Date {
        let busy = beat.status == .running || beat.status == .waiting || beat.status == .done
        return max(active[beat.id] ?? .distantPast, busy ? beat.time : .distantPast)
    }

    func chats(of item: Item, keep: Int? = nil) -> [Chat] {
        let all = item.chats.map { chat in
            var chat = chat
            if let title = named[chat.id], !title.isEmpty { chat.title = title }
            return chat
        }
        let ranked = all.enumerated()
            .sorted { left, right in
                let (a, b) = (score(left.element), score(right.element))
                return a == b ? left.offset > right.offset : a > b
            }
            .map(\.element)
        guard let keep, ranked.count > keep else { return ranked }
        return Array(ranked.prefix(keep))
    }

    private func score(_ chat: Chat) -> Date {
        beats[chat.id].map(latest) ?? .distantPast
    }

    func homes(for chat: Chat) -> [Item] {
        items.filter { !$0.chats.contains { $0.id == chat.id } }
    }

    var screens: [(id: String, name: String)] {
        var seen = Set<String>()
        return spaces.compactMap { space in
            guard seen.insert(space.display).inserted else { return nil }
            return (space.display, Sky.name(of: space.display) ?? "Screen")
        }
    }

    func screen(of space: Sky.Space?) -> String? {
        guard let space, screens.count > 1 else { return nil }
        return Sky.name(of: space.display)
    }

    func shortcut(for space: Sky.Space?) -> String? {
        space?.number.flatMap(Keys.label(for:))
    }

    func add(_ title: String, later: Bool = false) {
        let item = Item(title: title)
        items.append(item)
        if !later { create(for: item) }
    }

    func create(for item: Item) {
        guard ready() else { return }
        let id = item.id
        let display = spaces.first { $0.id == current }?.display ?? home?.display ?? ""
        starting = id
        run {
            defer { self.starting = nil }
            guard let made = await self.reuse(on: display) else { return }
            self.link(id, to: made)
            try? await Task.sleep(for: .milliseconds(700))
            await self.go(to: made)
        }
    }

    private func reuse(on display: String) async -> Sky.Space? {
        let taken = Set(items.flatMap { [$0.space, $0.origin].compactMap { $0 } })
        let desktops = Sky.spaces().filter { $0.number != nil }
        if let spare = desktops.dropFirst().first(where: { $0.display == display && !taken.contains($0.uuid) && Sky.windows(in: [$0.id]).isEmpty }) {
            return spare
        }
        return await provision(on: display)
    }

    private func provision(on display: String) async -> Sky.Space? {
        let before = Set(Sky.spaces().map(\.id))
        guard await Mission.add(on: display) else { return nil }
        var made: Sky.Space?
        for _ in 0..<30 where made == nil {
            try? await Task.sleep(for: .milliseconds(100))
            made = Sky.spaces().first { !before.contains($0.id) }
        }
        await Mission.close()
        return made
    }

    private func restore(_ id: UUID) {
        Task {
            try? await Task.sleep(for: .seconds(2))
            while busy { try? await Task.sleep(for: .milliseconds(200)) }
            guard trusted, let item = items.first(where: { $0.id == id }), let origin = item.origin,
                  let target = Sky.spaces().first(where: { $0.uuid == origin })
            else {
                returning.remove(id)
                return
            }
            let stand = Sky.spaces().first { $0.uuid == item.space && $0.display != target.display }
            let title = item.title.isEmpty ? "Untitled" : item.title
            run {
                defer { self.returning.remove(id) }
                if let stand {
                    let windows = Sky.windows(in: [stand.id])
                    if !windows.isEmpty {
                        let back = Sky.current()
                        if !Sky.visible().contains(stand.id) {
                            await self.go(to: stand)
                            try? await Task.sleep(for: .milliseconds(350))
                        }
                        let moved = await self.cross(windows, to: target)
                        try? await Task.sleep(for: .milliseconds(300))
                        if back != stand.id, Sky.current() != back, let previous = Sky.spaces().first(where: { $0.id == back }) {
                            await self.go(to: previous)
                        }
                        guard moved else {
                            if let index = self.items.firstIndex(where: { $0.id == id }) { self.items[index].origin = nil }
                            self.tell("Couldn't bring every window of \(title) back to its screen, so it stays on Desktop \(stand.number ?? 0)")
                            return
                        }
                    }
                }
                self.link(id, to: target)
                if let stand { await self.discard(stand) }
                let number = Sky.spaces().first { $0.uuid == origin }?.number ?? 0
                self.tell("\(title) is back on Desktop \(number) on its screen")
            }
        }
    }

    private func rehome(_ id: UUID, bringing windows: [UInt32]) {
        Task {
            try? await Task.sleep(for: .seconds(3))
            while busy { try? await Task.sleep(for: .milliseconds(200)) }
            guard trusted, let uuid = items.first(where: { $0.id == id })?.space,
                  !Sky.spaces().contains(where: { $0.uuid == uuid }),
                  let display = Sky.spaces().first(where: { $0.number != nil })?.display
            else {
                lost.remove(id)
                return
            }
            run {
                defer { self.lost.remove(id) }
                guard let made = await self.reuse(on: display) else { return }
                self.link(id, to: made)
                if let index = self.items.firstIndex(where: { $0.id == id }) { self.items[index].origin = uuid }
                try? await Task.sleep(for: .milliseconds(700))
                let live = Set(Sky.windows(in: Sky.spaces().map(\.id)).map(\.id))
                let moving = windows.filter(live.contains)
                if !moving.isEmpty { _ = Bridge.move(moving, to: made.id) }
                let title = self.items.first { $0.id == id }?.title ?? ""
                self.tell("\(title.isEmpty ? "Untitled" : title) moved to Desktop \(made.number ?? 0) because its screen was disconnected")
            }
        }
    }

    func adopt(_ space: Sky.Space) {
        guard space != home else { return }
        let item = Item(title: "", space: space.uuid)
        items.append(item)
        editing = item.id
    }

    func claim(_ item: Item) {
        guard claimable, let space = spaces.first(where: { $0.id == current }) else { return }
        link(item.id, to: space)
    }

    func remove(_ item: Item) {
        guard let space = space(for: item) else {
            file(item)
            items.removeAll { $0.id == item.id }
            return
        }
        guard ready() else { return }
        file(item)
        items.removeAll { $0.id == item.id }
        let siblings = desktops.filter { $0.display == space.display && $0.id != space.id }
        guard !siblings.isEmpty else {
            tell("Desktop \(space.number ?? 0) is the only desktop on its screen, so it stays")
            return
        }
        run { await self.discard(space) }
    }

    private func file(_ item: Item) {
        guard !Archive.store(item) else { return }
        tell("Could not write the archive to \((Archive.folder.path as NSString).abbreviatingWithTildeInPath)")
    }

    func remove(_ space: Sky.Space) {
        guard space != home, !items.contains(where: { self.space(for: $0) == space }), ready() else { return }
        guard desktops.contains(where: { $0.display == space.display && $0.id != space.id }) else {
            tell("Desktop \(space.number ?? 0) is the only desktop on its screen, so it stays")
            return
        }
        run { await self.discard(space) }
    }

    func postpone(_ item: Item) {
        guard let space = space(for: item), ready(), let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].space = nil
        items[index].origin = nil
        guard desktops.contains(where: { $0.display == space.display && $0.id != space.id }) else { return }
        run { await self.discard(space) }
    }

    private func discard(_ space: Sky.Space) async {
        let desktops = Sky.spaces().filter { $0.number != nil }
        guard let space = desktops.first(where: { $0.id == space.id }) else { return }
        let siblings = desktops.filter { $0.display == space.display && $0.id != space.id }
        guard !siblings.isEmpty else { return }
        let fallback = siblings.first { $0.id == desktops.first?.id } ?? siblings.last { $0.index < space.index } ?? siblings[0]
        let back = Sky.current()
        if !Sky.visible().contains(fallback.id) {
            await go(to: fallback)
            try? await Task.sleep(for: .milliseconds(400))
        }
        guard await Mission.remove(at: space.index, on: space.display) else { return }
        try? await Task.sleep(for: .milliseconds(500))
        if back != space.id, back != Sky.current(), let previous = Sky.spaces().first(where: { $0.id == back }) {
            await go(to: previous)
        }
    }

    func relocate(_ item: Item, to display: String) {
        guard let space = space(for: item), space.display != display, ready() else { return }
        let id = item.id
        let showing = Sky.visible().contains(space.id)
        run {
            guard let made = await self.reuse(on: display) else {
                self.tell("Couldn't make a desktop on that screen")
                return
            }
            let windows = Sky.windows(in: [space.id]).map(\.id)
            if !windows.isEmpty { _ = Bridge.move(windows, to: made.id) }
            for _ in 0..<20 where !Sky.windows(in: [space.id]).isEmpty {
                try? await Task.sleep(for: .milliseconds(100))
            }
            self.link(id, to: made)
            if Sky.windows(in: [space.id]).isEmpty {
                await self.discard(space)
            } else {
                self.tell("Some windows stayed on Desktop \(space.number ?? 0)")
            }
            if showing { await self.go(to: made) }
        }
    }

    func open(_ space: Sky.Space) {
        guard space.id != current, ready() else { return }
        run { await self.go(to: space) }
    }

    func open(_ item: Item) {
        guard let space = space(for: item) else { return }
        open(space)
    }

    func open(_ chat: Chat, in item: Item?) {
        guard ready() else { return }
        let task = item.flatMap(space(for:))
        run {
            let window = chat.agent.app.flatMap { self.main(of: $0.processIdentifier, for: chat.agent) }
            if let task {
                if !Sky.visible().contains(task.id) {
                    await self.go(to: task)
                    try? await Task.sleep(for: .milliseconds(400))
                }
                if let window, window.space != task.id, Bridge.move([window.id], to: task.id) {
                    _ = await Carry.arrived(window.id, in: task.id)
                }
            } else if let window, !Sky.visible().contains(window.space), let space = Sky.spaces().first(where: { $0.id == window.space }) {
                await self.go(to: space)
                try? await Task.sleep(for: .milliseconds(400))
            }
            await self.reveal(chat)
        }
    }

    private func reveal(_ chat: Chat) async {
        let agent = chat.agent
        guard let url = agent.link(chat.session),
              let target = agent.app?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: agent.bundle)
        else {
            tell("\(agent.name) isn't installed")
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: target, configuration: configuration)
        } catch {
            tell("Couldn't open the conversation in \(agent.name)")
        }
    }

    private func main(of pid: pid_t, for agent: Agent) -> Sky.Window? {
        let found = Sky.windows(in: Sky.spaces().filter { $0.number != nil }.map(\.id)).filter { $0.pid == pid }
        if agent == .code, let window = found.first(where: { id in windows.first { $0.id == id.id }?.title == "Agents" }) {
            return window
        }
        func area(_ window: Sky.Window) -> CGFloat {
            Carry.bounds(window.id).map { $0.width * $0.height } ?? 0
        }
        return found.max { area($0) < area($1) }
    }

    func attach(_ chat: Chat, to id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }), !items[index].chats.contains(where: { $0.id == chat.id }) else { return }
        var next = items
        for position in next.indices { next[position].chats.removeAll { $0.id == chat.id } }
        var chat = chat
        if let title = named[chat.id], !title.isEmpty { chat.title = title }
        next[index].chats.append(chat)
        items = next
    }

    func detach(_ chat: Chat) {
        guard items.contains(where: { $0.chats.contains { $0.id == chat.id } }) else { return }
        items = items.map { item in
            var item = item
            if item.chats.contains(where: { $0.id == chat.id }), !item.refused.contains(chat.id) {
                item.refused.append(chat.id)
            }
            item.chats.removeAll { $0.id == chat.id }
            return item
        }
    }

    func focus(_ window: Sky.Window) {
        guard ready() else { return }
        run {
            if !Sky.visible().contains(window.space), let space = self.spaces.first(where: { $0.id == window.space }) {
                await self.go(to: space)
                try? await Task.sleep(for: .milliseconds(450))
            }
            Access.raise(window)
        }
    }

    func send(_ window: Sky.Window, to space: Sky.Space, from frame: CGRect? = nil) {
        guard window.space != space.id, ready() else { return }
        let back = current
        let origin = spaces.first { $0.id == window.space }
        run {
            let shown = Sky.visible().contains(window.space)
            let element = shown ? Access.element(of: window) : nil
            let fit = origin.flatMap { Carry.fit(frame ?? Carry.bounds(window.id), from: $0.display, to: space.display) }
            if shown { Access.lift(window) }
            if Bridge.move([window.id], to: space.id), await Carry.arrived(window.id, in: space.id) {
                if let element, let fit { Access.fit(element, to: fit) }
                self.lead(window, on: space)
                return
            }
            if !shown, let origin {
                await self.go(to: origin)
                try? await Task.sleep(for: .milliseconds(350))
                Access.lift(window)
            }
            var moved = false
            if let origin, origin.display != space.display {
                moved = await self.cross([window], to: space)
            } else {
                moved = await Carry.run(window, to: space)
            }
            try? await Task.sleep(for: .milliseconds(300))
            if Sky.current() != back, let previous = Sky.spaces().first(where: { $0.id == back }) {
                await self.go(to: previous)
            }
            if moved {
                if let element, let fit { Access.fit(element, to: fit) }
                self.lead(window, on: space)
            } else {
                self.tell("Couldn't move \(window.app). Drag it in Mission Control instead.")
            }
        }
    }

    private func lead(_ window: Sky.Window, on space: Sky.Space) {
        if Sky.visible().contains(space.id) {
            Access.raise(window)
        } else {
            leads[space.id] = window.id
        }
    }

    private func cross(_ windows: [Sky.Window], to space: Sky.Space) async -> Bool {
        if !Sky.visible().contains(space.id) {
            await go(to: space)
            try? await Task.sleep(for: .milliseconds(350))
        }
        guard let frame = Sky.frame(of: space.display) else { return false }
        for window in windows { _ = Carry.place(window, in: frame) }
        try? await Task.sleep(for: .milliseconds(400))
        let there = Set(Sky.windows(in: [space.id]).map(\.id))
        return windows.allSatisfy { there.contains($0.id) }
    }

    func pull(_ item: Item) {
        guard let space = space(for: item) else { return }
        Task {
            await refresh()
            guard let front = Access.front(), let window = windows.first(where: { $0.id == front.id }) else {
                tell("No front window to send")
                return
            }
            send(window, to: space)
        }
    }

    func place(_ id: UInt64?, _ frame: CGRect?, by token: UUID) {
        guard let id, own("zone \(id)", frame, token) else { return }
        zones[id] = frame
    }

    func place(shelf id: UUID, _ frame: CGRect?, by token: UUID) {
        guard own("shelf \(id)", frame, token) else { return }
        shelves[id] = frame
    }

    func place(row id: UUID, _ frame: CGRect?, by token: UUID) {
        guard own("row \(id)", frame, token) else { return }
        rows[id] = frame
    }

    func place(card id: UUID, _ frame: CGRect?, by token: UUID) {
        guard own("card \(id)", frame, token) else { return }
        cards[id] = frame
    }

    func place(leaf: Leaf, _ frame: CGRect?, by token: UUID) {
        guard own("leaf \(leaf)", frame, token) else { return }
        leaves[leaf] = frame
        guard let frame else { return }
        if shown(leaf) { high[leaf] = frame.height } else { low[leaf] = frame.height }
        if let anchor, anchor.leaf == leaf, Date() < anchor.until, lift == nil, tug == nil, !overflow {
            follow(frame.minY - anchor.y)
        }
    }

    func place(inbox agent: Agent, _ frame: CGRect?, by token: UUID) {
        guard own("inbox \(agent.rawValue)", frame, token) else { return }
        inboxes[agent] = frame
    }

    private func own(_ key: String, _ frame: CGRect?, _ token: UUID) -> Bool {
        if frame != nil {
            owners[key] = token
            return true
        }
        guard owners[key] == token else { return false }
        owners[key] = nil
        return true
    }

    func track(_ chat: Chat, at point: CGPoint) {
        if held != chat { held = chat }
        pointer = point
        let aim = aim(for: chat, at: point)
        if self.aim != aim {
            if aim != nil { buzz(.levelChange) }
            self.aim = aim
        }
    }

    func release(_ chat: Chat, at point: CGPoint) {
        let aim = aim(for: chat, at: point)
        held = nil
        self.aim = nil
        switch aim {
        case .card(let id): attach(chat, to: id)
        case .inbox: detach(chat)
        case nil: break
        }
    }

    private func aim(for chat: Chat, at point: CGPoint) -> Aim? {
        if let id = cards.filter({ $0.value.contains(point) }).min(by: { $0.value.height < $1.value.height })?.key {
            return .card(id)
        }
        if inboxes[chat.agent]?.contains(point) == true {
            return .inbox(chat.agent)
        }
        return nil
    }

    func lift(_ item: Item, by translation: CGFloat) {
        if lift?.id != item.id {
            let group = started(item)
            let order = items.filter { started($0) == group }.map(\.id)
            lift = Lift(id: item.id, order: order, frames: cards.filter { order.contains($0.key) }, slot: order.firstIndex(of: item.id) ?? 0)
        }
        guard var lift, let frame = lift.frames[item.id],
              let first = lift.order.first.flatMap({ lift.frames[$0] }),
              let last = lift.order.last.flatMap({ lift.frames[$0] })
        else { return }
        lift.shift = min(max(translation, first.minY - frame.minY), last.maxY - frame.maxY)
        let edge = lift.shift > 0 ? frame.maxY + lift.shift : frame.minY + lift.shift
        lift.slot = lift.order.filter { $0 != item.id }.filter { (lift.frames[$0]?.midY ?? 0) < edge }.count
        if lift.slot != self.lift?.slot { buzz(.alignment) }
        if lift != self.lift { self.lift = lift }
    }

    func tug(_ todo: UUID, in owner: UUID, by translation: CGFloat) {
        guard let item = items.first(where: { $0.id == owner }), let row = item.todos.first(where: { $0.id == todo }) else { return }
        if tug?.id != todo {
            let order = item.todos.filter { $0.done == row.done }.map(\.id)
            tug = Lift(id: todo, order: order, frames: rows.filter { order.contains($0.key) }, slot: order.firstIndex(of: todo) ?? 0, owner: owner)
        }
        guard var tug, let frame = tug.frames[todo],
              let first = tug.order.first.flatMap({ tug.frames[$0] }),
              let last = tug.order.last.flatMap({ tug.frames[$0] })
        else { return }
        tug.shift = min(max(translation, first.minY - frame.minY), last.maxY - frame.maxY)
        let edge = tug.shift > 0 ? frame.maxY + tug.shift : frame.minY + tug.shift
        tug.slot = tug.order.filter { $0 != todo }.filter { (tug.frames[$0]?.midY ?? 0) < edge }.count
        if tug.slot != self.tug?.slot { buzz(.alignment) }
        if tug != self.tug { self.tug = tug }
    }

    func shed() {
        guard let tug, let at = items.firstIndex(where: { $0.id == tug.owner }) else { return }
        var order = tug.order.filter { $0 != tug.id }
        order.insert(tug.id, at: min(tug.slot, order.count))
        var queue = order.compactMap { id in items[at].todos.first { $0.id == id } }[...]
        let next = items[at].todos.map { tug.order.contains($0.id) && !queue.isEmpty ? queue.removeFirst() : $0 }
        withAnimation(.easeInOut(duration: 0.18)) {
            if next.map(\.id) != items[at].todos.map(\.id) { items[at].todos = next }
            self.tug = nil
        }
    }

    func offset(for id: UUID) -> CGFloat { travel(lift, id, 1, free: true) }

    func berth(for id: UUID) -> CGFloat { travel(lift, id, 1, free: false) }

    func shift(for id: UUID) -> CGFloat { travel(tug, id, 3, free: false) }

    private func travel(_ lift: Lift?, _ id: UUID, _ gap: CGFloat, free: Bool) -> CGFloat {
        guard let lift, let from = lift.order.firstIndex(of: lift.id), let index = lift.order.firstIndex(of: id),
              let height = lift.frames[lift.id]?.height
        else { return 0 }
        if id == lift.id { return free ? lift.shift : snap(lift, from, gap) }
        if from < lift.slot, index > from, index <= lift.slot { return -(height + gap) }
        if from > lift.slot, index >= lift.slot, index < from { return height + gap }
        return 0
    }

    private func snap(_ lift: Lift, _ from: Int, _ gap: CGFloat) -> CGFloat {
        let span = from < lift.slot ? (from + 1)...lift.slot : from > lift.slot ? lift.slot...(from - 1) : nil
        guard let span else { return 0 }
        let travel = span.reduce(CGFloat(0)) { $0 + (lift.frames[lift.order[$1]]?.height ?? 0) + gap }
        return from < lift.slot ? travel : -travel
    }

    func drop() {
        guard let lift else { return }
        var order = lift.order.filter { $0 != lift.id }
        order.insert(lift.id, at: min(lift.slot, order.count))
        var queue = order.compactMap { id in items.first { $0.id == id } }[...]
        let next = items.map { lift.order.contains($0.id) && !queue.isEmpty ? queue.removeFirst() : $0 }
        withAnimation(.easeInOut(duration: 0.18)) {
            if next.map(\.id) != items.map(\.id) { items = next }
            self.lift = nil
        }
    }

    func track(_ window: Sky.Window, at point: CGPoint) {
        if carrying?.id != window.id { carrying = window }
        pointer = point
        let hit = zone(at: point)
        light(hit)
    }

    func hover(_ point: CGPoint?) {
        let hit = point.flatMap(zone(at:))
        light(hit)
    }

    private func light(_ hit: UInt64?) {
        guard hovered != hit else { return }
        if hit != nil { buzz(.levelChange) }
        hovered = hit
    }

    private func buzz(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    func take(_ id: UInt32, at point: CGPoint, back frame: CGRect) {
        let hit = zone(at: point)
        hovered = nil
        guard let hit, let space = spaces.first(where: { $0.id == hit }) else { return }
        Task {
            await refresh()
            guard let window = windows.first(where: { $0.id == id }), window.space != hit else { return }
            send(window, to: space, from: frame)
        }
    }

    func graze(_ point: CGPoint?) {
        guard lift == nil, tug == nil, carrying == nil, held == nil, editing == nil,
              !(Panel.main?.firstResponder is NSTextView)
        else { return }
        guard let point else {
            spot = nil
            mark = nil
            wait(0.26)
            return
        }
        spot = point
        if let mark, hypot(point.x - mark.x, point.y - mark.y) < 2 { return }
        mark = point
        wait(0.18)
    }

    func mute(_ leaf: Leaf) {
        calm()
        muted = leaf
        peek.remove(leaf)
    }

    func toss(_ leaf: Leaf) {
        if case .task(let id) = leaf {
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            if items[index].folded, peek.contains(leaf) {
                items[index].folded = false
                return
            }
            let next = !items[index].folded
            if next { mute(leaf) }
            withAnimation(Style.fold(items[index].folded)) { items[index].folded = next }
            return
        }
        guard let key = key(leaf) else { return }
        let folded = UserDefaults.standard.bool(forKey: key)
        if folded, peek.contains(leaf) {
            UserDefaults.standard.set(false, forKey: key)
            return
        }
        if !folded { mute(leaf) }
        withAnimation(Style.fold(folded)) { UserDefaults.standard.set(!folded, forKey: key) }
    }

    private func key(_ leaf: Leaf) -> String? {
        switch leaf {
        case .task: nil
        case .desk(let id): spaces.first { $0.id == id }.map { "folded." + ($0 == home ? "home" : $0.uuid) }
        case .unsorted(let agent): "folded.agent." + agent.rawValue
        case .upcoming: "folded.upcoming"
        }
    }

    private func wait(_ delay: TimeInterval) {
        calm()
        dwell = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            dwell = nil
            settle()
        }
    }

    private func settle() {
        spot = cursor()
        let hit = spot.flatMap(leaf(at:))
        if hit != muted { muted = nil }
        guard let hit else {
            if !peek.isEmpty { steady(nil, after: { !self.folded($0) }) { self.peek = [] } }
            return
        }
        guard hit != muted, leaves[hit] != nil else { return }
        let keep: Set<Leaf> = upcomer(hit) && peek.contains(.upcoming) ? [hit, .upcoming] : [hit]
        guard peek != keep else { return }
        if !peek.contains(hit), folded(hit) {
            buzz(.alignment)
            reveal = hit
        }
        steady(hit, after: { !self.folded($0) || keep.contains($0) }) { self.peek = keep }
    }

    static let blink = AnyTransition.opacity.animation(.linear(duration: 0.05))

    func moving(_ leaf: Leaf) -> Bool {
        guard let move = rises[leaf] else { return false }
        return move.isNaN || abs(move) > 0.5
    }

    func rise(_ leaf: Leaf) -> AnyTransition {
        guard let move = rises[leaf] else { return .opacity }
        guard !move.isNaN else { return .asymmetric(insertion: .opacity, removal: Self.blink) }
        return .asymmetric(insertion: .offset(y: -move).combined(with: .opacity), removal: .offset(y: move).combined(with: .opacity))
    }

    private func upcomer(_ leaf: Leaf) -> Bool {
        guard case .task(let id) = leaf, let item = items.first(where: { $0.id == id }) else { return false }
        return !started(item)
    }

    private func shown(_ leaf: Leaf) -> Bool {
        !folded(leaf) || peek.contains(leaf)
    }

    private func rest(_ leaf: Leaf) -> CGFloat {
        low[leaf] ?? low.first { kind($0.key) == kind(leaf) }?.value ?? 34
    }

    private func kind(_ leaf: Leaf) -> String {
        String(String(describing: leaf).prefix { $0 != "(" })
    }

    private func measure(_ leaf: Leaf, fewer: Bool = false, tidy: Bool = false) -> CGFloat? {
        let view: AnyView
        switch leaf {
        case .task(let id):
            guard let item = items.first(where: { $0.id == id }) else { return nil }
            view = AnyView(Card(item: .constant(item)))
        case .desk(let id):
            guard let space = spaces.first(where: { $0.id == id }) else { return nil }
            view = AnyView(Loose(space: space, home: space == home))
        case .unsorted(let agent):
            view = AnyView(Inbox(agent: agent))
        case .upcoming:
            return nil
        }
        let host = NSHostingView(rootView: view
            .frame(width: Panel.main?.frame.width ?? 300)
            .fixedSize(horizontal: false, vertical: true)
            .environment(\.aside, true)
            .environment(\.fewer, fewer)
            .environment(\.tidy, tidy)
            .environmentObject(self))
        let height = host.fittingSize.height
        guard height > 0 else { return nil }
        if !fewer, !tidy { high[leaf] = height }
        return height
    }

    func trim(_ id: UUID, done: Bool) {
        let leaf = Leaf.task(id)
        let open = done ? all.contains(id) : more.contains(id)
        let flip = {
            if done { self.all.formSymmetricDifference([id]) } else { self.more.formSymmetricDifference([id]) }
        }
        guard open, let frame = leaves[leaf], let size = measure(leaf, fewer: !done, tidy: done) else {
            withAnimation(Style.fold(!open)) { flip() }
            return
        }
        steady(nil, focus: cursor()?.y, resize: [leaf: size], drop: done ? 0 : frame.height - size, after: { self.shown($0) }, flip)
    }

    private func steady(_ hit: Leaf?, focus: CGFloat? = nil, resize: [Leaf: CGFloat] = [:], drop: CGFloat = 0, after: @escaping (Leaf) -> Bool, _ change: @escaping () -> Void) {
        let top = focus ?? hit.flatMap { leaves[$0]?.minY } ?? -.infinity
        let frames = leaves
        let was = Set(frames.keys.filter(shown))
        var moves: [Leaf: CGFloat] = [:]
        var total: CGFloat = 0
        var shrink = drop
        for (leaf, frame) in frames.sorted(by: { $0.value.minY < $1.value.minY }) {
            if let size = resize[leaf] {
                total += size - frame.height
                continue
            }
            let now = after(leaf)
            guard now != was.contains(leaf) else { continue }
            moves[leaf] = total
            if !now, frame.minY < top { shrink += max(0, frame.height - rest(leaf)) }
            total = now ? (high[leaf] ?? measure(leaf)).map { total + $0 - frame.height } ?? .nan : total + rest(leaf) - frame.height
        }
        let next = height + (total.isNaN ? -shrink : total)
        if overflow, scrolled > 0.5, next <= limit {
            turn += 1
            let mark = turn
            sinking = Date().addingTimeInterval(1)
            lead = scrolled
            overflow = false
            DispatchQueue.main.async { [weak self] in
                guard let self, self.turn == mark else { return }
                self.steady(hit, focus: focus, resize: resize, drop: drop, after: after, change)
            }
            return
        }
        let duration = Glide.duration(for: shrink > 0 || total.isNaN ? shrink : total)
        sinking = Date().addingTimeInterval(duration + 0.05)
        turn += 1
        let mark = turn
        rises = moves
        let held = lead
        withAnimation(Glide.animation(duration)) {
            change()
            lead = 0
            clock += 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration + 0.05) { [weak self] in
            guard let self, self.turn == mark else { return }
            self.rises = [:]
        }
        guard top > -.infinity else { return }
        let give = overflow ? scrolled - max(0, min(scrolled, next - limit)) : held
        anchor = hit.map { Anchor(leaf: $0, y: top, until: Date().addingTimeInterval(0.5)) }
        follow(give - shrink, smooth: true)
    }

    func tick(_ value: Double) {
        glide.tick(value)
    }

    private func follow(_ drift: CGFloat, smooth: Bool = false) {
        guard abs(drift) > 0.5, let panel = Panel.main, panel.isVisible, panel.frame.contains(NSEvent.mouseLocation) else { return }
        glide.add(drift, until: smooth ? clock : nil)
        spot?.y += drift
        mark?.y += drift
        anchor?.y += drift
    }

    func scroll(to leaf: Leaf) -> (Leaf, UnitPoint)? {
        guard overflow, !folded(leaf) || peek.contains(leaf), let frame = leaves[leaf] else { return nil }
        let cards = leaf == .upcoming ? upcoming.compactMap { item in leaves[.task(item.id)].map { (Leaf.task(item.id), $0) } } : []
        let span = cards.reduce(frame) { $0.union($1.1) }
        let top = Style.header + 0.5
        let bottom = Style.header + limit + 0.5
        if span.minY < top || (span.height > limit && span.maxY > bottom) {
            pass(span.minY - Style.header)
            return (leaf, .top)
        }
        guard span.maxY > bottom else { return nil }
        pass(span.maxY - Style.header - limit)
        return (cards.max { $0.1.maxY < $1.1.maxY }?.0 ?? leaf, .bottom)
    }

    private func pass(_ shift: CGFloat) {
        guard let spot, let leaf = leaf(at: CGPoint(x: spot.x, y: spot.y + shift)), folded(leaf), !peek.contains(leaf) else { return }
        muted = leaf
    }

    private func folded(_ leaf: Leaf) -> Bool {
        if case .task(let id) = leaf { return items.first { $0.id == id }?.folded ?? false }
        return key(leaf).map { UserDefaults.standard.bool(forKey: $0) } ?? false
    }

    private func leaf(at point: CGPoint) -> Leaf? {
        for dy: CGFloat in [0, -1.5, 1.5] {
            let probe = CGPoint(x: point.x, y: point.y + dy)
            if let hit = leaves.filter({ $0.value.contains(probe) }).min(by: { $0.value.height < $1.value.height })?.key { return hit }
        }
        return nil
    }

    private func cursor() -> CGPoint? {
        guard let panel = Panel.main, panel.isVisible, !collapsed else { return nil }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x - panel.frame.minX, y: panel.frame.maxY - mouse.y)
        let bottom = Style.header + min(overflow ? limit : height, panel.frame.height - Style.header)
        guard point.x >= 0, point.x < panel.frame.width, point.y >= Style.header, point.y < bottom else { return nil }
        return point
    }

    private func calm() {
        dwell?.cancel()
        dwell = nil
    }

    private func card(at point: CGPoint) -> UUID? {
        cards.filter { $0.value.contains(point) }.min { $0.value.height < $1.value.height }?.key
    }

    private func mind() {
        guard editing == nil, !(Panel.main?.firstResponder is NSTextView) else { return }
        let id = items.first { space(for: $0)?.id == current }?.id
        var next = items
        for index in next.indices where next[index].folded != (next[index].id != id) {
            next[index].folded = next[index].id != id
        }
        var marks = ["folded.upcoming": true]
        for agent in Agent.allCases { marks["folded.agent." + agent.rawValue] = true }
        for space in loose + (home.map { [$0] } ?? []) {
            guard let key = key(.desk(space.id)) else { continue }
            marks[key] = !(id == nil && space.id == current)
        }
        let defaults = UserDefaults.standard
        marks = marks.filter { defaults.bool(forKey: $0.key) != $0.value }
        guard next != items || !marks.isEmpty else { return }
        calm()
        let after: (Leaf) -> Bool = { leaf in
            if case .task(let id) = leaf { return !(next.first { $0.id == id }?.folded ?? true) }
            guard let key = self.key(leaf) else { return true }
            return !(marks[key] ?? defaults.bool(forKey: key))
        }
        anchor = nil
        steady(nil, after: after) {
            self.peek = []
            if next != self.items { self.items = next }
            for (key, value) in marks { defaults.set(value, forKey: key) }
        }
        reveal = id.map(Leaf.task) ?? .desk(current)
    }

    func fold(at point: CGPoint) -> Bool {
        if let id = shelves.first(where: { $0.value.contains(point) })?.key,
           let index = items.firstIndex(where: { $0.id == id }), !items[index].todos.isEmpty {
            withAnimation(Style.fold(items[index].shelved)) { items[index].shelved.toggle() }
            return true
        }
        guard let leaf = leaf(at: point) else { return false }
        toss(leaf)
        return true
    }

    private func zone(at point: CGPoint) -> UInt64? {
        zones.filter { $0.value.contains(point) }.min { $0.value.height < $1.value.height }?.key
    }

    func release(_ window: Sky.Window, at point: CGPoint) {
        let hit = zone(at: point)
        carrying = nil
        hovered = nil
        guard let hit, hit != window.space, let space = spaces.first(where: { $0.id == hit }) else { return }
        send(window, to: space)
    }

    func targets(for window: Sky.Window) -> [(name: String, space: Sky.Space)] {
        var targets = items.compactMap { item in
            space(for: item).map { (name: item.title.isEmpty ? "Untitled" : item.title, space: $0) }
        }
        if let home { targets.append((name: "Unsorted", space: home)) }
        return targets.filter { $0.space.id != window.space }
    }

    func refresh() async {
        trusted = Access.trusted
        let spaces = Sky.spaces()
        let current = Sky.current()
        let ids = spaces.filter { $0.number != nil }.map(\.id)
        let trusted = self.trusted
        let (found, scanned) = await Task.detached {
            let windows = Sky.windows(in: ids)
            let scanned = trusted ? Access.scan(Set(windows.map(\.pid))) : [:]
            return (windows, scanned)
        }.value
        let named = scanned.compactMapValues { $0.title.isEmpty ? nil : $0.title }
        scout?.attach(scanned)
        leads = leads.filter { lead in found.contains { $0.id == lead.value && $0.space == lead.key } }
        var fronts: [UInt64: Sky.Window] = [:]
        for window in found where fronts[window.space] == nil { fronts[window.space] = window }
        for (space, id) in leads { fronts[space] = found.first { $0.id == id } }
        self.fronts = fronts
        if let id = leads.removeValue(forKey: current), let window = found.first(where: { $0.id == id }) {
            Access.raise(window)
        }
        let live = Set(found.map(\.id))
        titles.merge(named) { $1 }
        titles = titles.filter { live.contains($0.key) }
        let windows = found
            .map { window -> Sky.Window in
                var window = window
                if window.title.isEmpty { window.title = titles[window.id] ?? "" }
                return window
            }
            .sorted { ($0.app, $0.id) < ($1.app, $1.id) }
        let screens = Set(spaces.map(\.display))
        for item in items where !lost.contains(item.id) {
            guard let uuid = item.space, let old = self.spaces.first(where: { $0.uuid == uuid }), old != home,
                  !spaces.contains(where: { $0.uuid == uuid }), !screens.contains(old.display)
            else { continue }
            lost.insert(item.id)
            rehome(item.id, bringing: self.windows.filter { $0.space == old.id }.map(\.id))
        }
        for item in items where !returning.contains(item.id) && !lost.contains(item.id) {
            guard let origin = item.origin, spaces.contains(where: { $0.uuid == origin }) else { continue }
            returning.insert(item.id)
            restore(item.id)
        }
        if spaces != self.spaces { self.spaces = spaces }
        if windows != self.windows { self.windows = windows }
        if current != self.current {
            self.current = current
            mind()
        }
    }

    func tell(_ message: String) {
        notice = message
        Task {
            try? await Task.sleep(for: .seconds(5))
            if notice == message { notice = nil }
        }
    }

    private func go(to space: Sky.Space) async {
        if Sky.visible().contains(space.id) {
            await land(space)
            return
        }
        if let number = space.number {
            for _ in 0..<2 {
                guard Keys.desktop(number) else { break }
                for _ in 0..<10 {
                    try? await Task.sleep(for: .milliseconds(100))
                    if Sky.visible().contains(space.id) {
                        await land(space)
                        return
                    }
                }
            }
        }
        _ = await Mission.go(to: space.index, on: space.display)
    }

    private func land(_ space: Sky.Space) async {
        guard Sky.current() != space.id else { return }
        if let window = fronts[space.id] {
            Access.raise(window)
        } else if let frame = Sky.frame(of: space.display) {
            Carry.tap(CGPoint(x: frame.midX, y: frame.midY))
        }
        for _ in 0..<10 where Sky.current() != space.id {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func link(_ id: UUID, to space: Sky.Space) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].space = space.uuid
        items[index].origin = nil
    }

    private func ready() -> Bool {
        guard trusted else {
            Access.prompt()
            return false
        }
        return !busy
    }

    private func run(_ action: @escaping () async -> Void) {
        busy = true
        Task {
            await action()
            busy = false
            await refresh()
        }
    }

    private func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.glance()
                    await self?.refresh()
                }
            })
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.census() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stir() }
        })
        Sky.listen { [weak self] code, window in
            DispatchQueue.main.async { self?.shift(code, window) }
        }
        scout = Scout(
            changed: { [weak self] in self?.stir() },
            focused: { [weak self] in self?.glance() },
            titled: { [weak self] id, title in self?.retitle(id, title) }
        )
        census()
        prime()
        glance()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.scout?.scan()
                self?.glance()
                await self?.refresh()
                try? await Task.sleep(for: .seconds(30))
            }
        }
        sense = Task { [weak self] in
            while !Task.isCancelled {
                self?.poke()
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func forget(_ old: [Item]) {
        let before = Dictionary(old.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var changed = false
        for item in items {
            guard var was = before[item.id] else {
                changed = true
                continue
            }
            var now = item
            was.folded = false
            now.folded = false
            guard was != now else { continue }
            high[.task(item.id)] = nil
            tried.remove(.task(item.id))
            changed = true
        }
        if changed { prime() }
    }

    private func prime() {
        priming?.cancel()
        priming = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            while !Task.isCancelled {
                guard let self else { return }
                if dwell != nil || (sinking.map { $0 > Date() } ?? false) {
                    try? await Task.sleep(for: .seconds(0.5))
                    continue
                }
                guard let leaf = items.lazy.map({ Leaf.task($0.id) }).first(where: { self.high[$0] == nil && !self.tried.contains($0) && self.leaves[$0] != nil && !self.shown($0) }) else { return }
                tried.insert(leaf)
                _ = measure(leaf)
                try? await Task.sleep(for: .seconds(0.1))
            }
        }
    }

    private func census() {
        let now = Set(Agent.allCases.filter { $0.app != nil })
        if now != running { running = now }
    }

    private func poke() {
        guard ear == nil else {
            again = true
            return
        }
        ear = Task { [weak self] in
            repeat {
                self?.again = false
                try? await Task.sleep(for: .milliseconds(150))
                await self?.listen()
            } while self?.again == true
            self?.ear = nil
        }
    }

    private func track(_ tails: Set<URL>) {
        let wanted = tails.union([Hooks.events])
        for (url, watch) in watches where watch.dead || !wanted.contains(url) { watches[url] = nil }
        for url in wanted where watches[url] == nil {
            watches[url] = Watch(url) { [weak self] in
                MainActor.assumeIsolated { self?.poke() }
            }
        }
    }

    private func listen() async {
        let seen = self.seen
        let (found, tails, memo) = await Task.detached {
            var seen = seen
            let (beats, tails) = Hooks.read(&seen)
            return (beats, tails, seen)
        }.value
        self.seen = memo
        track(tails)
        var beats: [String: Beat] = [:]
        for beat in found where (beats[beat.id]?.time ?? .distantPast) <= beat.time { beats[beat.id] = beat }
        if beats != self.beats { self.beats = beats }
        var tools: [Agent: String] = [:]
        for beat in beats.values.sorted(by: { $0.time < $1.time }) where !beat.tool.isEmpty {
            tools[beat.agent] = beat.tool
        }
        if !tools.isEmpty { Guess.learn(tools) }
        let now = Date()
        var wanted: [String: (agent: Agent, session: String, cwd: String)] = [:]
        for chat in items.flatMap(\.chats) { wanted[chat.id] = (chat.agent, chat.session, "") }
        for beat in beats.values { wanted[beat.id] = (beat.agent, beat.session, beat.cwd) }
        let due = wanted.filter { id, _ in
            guard let last = looked[id] else { return true }
            return now.timeIntervalSince(last) > 60 || (beats[id].map { $0.time > last } ?? false)
        }
        guard !due.isEmpty else { return }
        for id in due.keys { looked[id] = now }
        let results = await Task.detached {
            due.map { id, value in (id: id, agent: value.agent, cwd: value.cwd, found: value.agent.look(value.session)) }
        }.value
        var named = self.named
        var hidden = self.hidden
        var active = self.active
        var titles: [String: String] = [:]
        for result in results {
            let title = result.found?.title ?? ""
            if !title.isEmpty { titles[result.id] = title }
            let cached = items.lazy.flatMap(\.chats).first { $0.id == result.id }?.title ?? ""
            let fallback = !cached.isEmpty ? cached : result.cwd.isEmpty ? "Untitled" : URL(fileURLWithPath: result.cwd).lastPathComponent
            named[result.id] = title.isEmpty ? (named[result.id] ?? fallback) : title
            if result.found?.hidden ?? true {
                hidden.insert(result.id)
            } else {
                hidden.remove(result.id)
            }
            active[result.id] = result.found?.active
        }
        if named != self.named { self.named = named }
        if hidden != self.hidden { self.hidden = hidden }
        if active != self.active { self.active = active }
        let next = items.map { item in
            var item = item
            for index in item.chats.indices {
                if let title = titles[item.chats[index].id] { item.chats[index].title = title }
            }
            return item
        }
        if next != items { items = next }
        sift()
    }

    private func brief(_ item: Item) -> String {
        var bits = [item.title]
        if !item.detail.isEmpty { bits.append(item.detail) }
        let todos = item.todos.map(\.text).filter { !$0.isEmpty }
        if !todos.isEmpty { bits.append("to-dos: " + todos.joined(separator: "; ")) }
        return bits.joined(separator: " - ")
    }

    private func renew() {
        let ids = Set(items.flatMap { item in [item.id] + item.todos.filter { !$0.text.isEmpty }.map(\.id) })
        guard let known else {
            self.known = ids
            return
        }
        guard !ids.isSubset(of: known), editing == nil,
              !(Panel.main?.isKeyWindow == true && Panel.main?.firstResponder is NSTextView) else { return }
        self.known = known.union(ids)
        sifted.removeAll()
    }

    private func sift() {
        renew()
        guard !sorting, Hooks.connected, !items.isEmpty else { return }
        let now = Date()
        let cutoff = now.addingTimeInterval(-86400)
        let taken = linked
        let candidates = beats.values.filter { !taken.contains($0.id) && !hidden.contains($0.id) && latest($0) > cutoff }
        if let fresh = candidates.compactMap(\.prompt).filter({ now.timeIntervalSince($0) < 3 }).max() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.1 - now.timeIntervalSince(fresh)) { [weak self] in self?.sift() }
        }
        let waiting = candidates
            .filter { beat in
                if let prompt = beat.prompt, now.timeIntervalSince(prompt) < 3 { return false }
                guard let last = sifted[beat.id] else { return true }
                return (beat.prompt ?? .distantPast) > last
            }
            .sorted { latest($0) > latest($1) }
        guard let beat = waiting.first else { return }
        let chat = Chat(agent: beat.agent, session: beat.session, title: named[beat.id] ?? "")
        let tasks = items.filter { !$0.refused.contains(chat.id) }.map { (id: $0.id, text: brief($0)) }
        guard !tasks.isEmpty else { return }
        sifted[chat.id] = beat.prompt ?? .distantPast
        sorting = true
        let title = chat.title
        let cwd = beat.cwd
        Task.detached(priority: .background) { [weak self] in
            let pick = Guess.sort(chat, title: title, cwd: cwd, tasks: tasks)
            await self?.settle(chat, pick)
        }
    }

    private func settle(_ chat: Chat, _ pick: UUID?) {
        sorting = false
        if let pick, items.contains(where: { $0.id == pick && !$0.refused.contains(chat.id) }) { attach(chat, to: pick) }
        sift()
    }

    private func shift(_ code: UInt32, _ window: UInt32?) {
        guard code != 1329 else { return }
        if let window, code == 1325 || code == 1326, !windows.contains(where: { $0.id == window }), !Sky.normal(window) { return }
        stir()
    }

    private func stir() {
        stirs += 1
        guard stirring == nil else { return }
        stirring = Task { [weak self] in
            let waits = [0.1, 0.25, 0.65]
            var step = 0
            var seen = self?.stirs
            while let self, step < waits.count {
                try? await Task.sleep(for: .seconds(waits[step]))
                await refresh()
                glance()
                if stirs != seen {
                    seen = stirs
                    step = 1
                } else {
                    step += 1
                }
            }
            self?.stirring = nil
        }
    }

    private func retitle(_ id: UInt32, _ title: String) {
        guard !title.isEmpty, titles[id] != title else { return }
        titles[id] = title
        guard let index = windows.firstIndex(where: { $0.id == id }), windows[index].title != title else { return }
        windows[index].title = title
    }

    private func glance() {
        let now = trusted ? Access.front()?.id : nil
        if now != front { front = now }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(items).write(to: url, options: .atomic)
    }
}
