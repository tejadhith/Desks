import AppKit
import SwiftUI

struct Lift: Equatable {
    let id: UUID
    let order: [UUID]
    let frames: [UUID: CGRect]
    var shift: CGFloat = 0
    var slot: Int
}

enum Aim: Equatable {
    case card(UUID)
    case inbox(Agent)
}

@MainActor
final class Store: ObservableObject {
    @Published var items: [Item] { didSet { save() } }
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
    @Published private(set) var carrying: Sky.Window?
    @Published private(set) var pointer: CGPoint = .zero
    @Published private(set) var lift: Lift?
    private var cards: [UUID: CGRect] = [:]
    @Published private(set) var hovered: UInt64?
    @Published private(set) var front: UInt32?
    @Published private(set) var starting: UUID?
    @Published private(set) var beats: [String: Beat] = [:]
    @Published private(set) var named: [String: String] = [:]
    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var held: Chat?
    @Published private(set) var aim: Aim?
    private var zones: [UInt64: CGRect] = [:]
    private var inboxes: [Agent: CGRect] = [:]
    private var looked: [String: Date] = [:]
    var snap: () -> Void = {}

    private let url: URL
    private var titles: [UInt32: String] = [:]
    private var fronts: [UInt64: Sky.Window] = [:]
    private var loop: Task<Void, Never>?
    private var pulse: Task<Void, Never>?
    private var sense: Task<Void, Never>?
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
        let cutoff = Date().addingTimeInterval(-86400)
        let linked = linked
        return beats.values
            .filter { $0.agent == agent && $0.time > cutoff && !linked.contains($0.id) && !hidden.contains($0.id) }
            .sorted { $0.time > $1.time }
            .map { Chat(agent: $0.agent, session: $0.session, title: named[$0.id] ?? "") }
    }

    func chats(of item: Item) -> [Chat] {
        item.chats.map { chat in
            var chat = chat
            if let title = named[chat.id], !title.isEmpty { chat.title = title }
            return chat
        }
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
            guard let made = await self.provision(on: display) else { return }
            self.link(id, to: made)
            try? await Task.sleep(for: .milliseconds(700))
            await self.go(to: made)
        }
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
                guard let made = await self.provision(on: display) else { return }
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
            items.removeAll { $0.id == item.id }
            return
        }
        guard ready() else { return }
        items.removeAll { $0.id == item.id }
        let siblings = desktops.filter { $0.display == space.display && $0.id != space.id }
        guard !siblings.isEmpty else {
            tell("Desktop \(space.number ?? 0) is the only desktop on its screen, so it stays")
            return
        }
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
            guard let made = await self.provision(on: display) else {
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

    func send(_ window: Sky.Window, to space: Sky.Space) {
        guard window.space != space.id, ready() else { return }
        let back = current
        let origin = spaces.first { $0.id == window.space }
        run {
            if origin?.display == space.display, Bridge.move([window.id], to: space.id), await Carry.arrived(window.id, in: space.id) {
                return
            }
            if !Sky.visible().contains(window.space), let origin {
                await self.go(to: origin)
                try? await Task.sleep(for: .milliseconds(350))
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
            if !moved {
                self.tell("Couldn't move \(window.app). Drag it in Mission Control instead.")
            }
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

    func place(_ id: UInt64?, _ frame: CGRect?) {
        guard let id else { return }
        zones[id] = frame
    }

    func place(card id: UUID, _ frame: CGRect?) {
        cards[id] = frame
    }

    func place(inbox agent: Agent, _ frame: CGRect?) {
        inboxes[agent] = frame
    }

    func track(_ chat: Chat, at point: CGPoint) {
        if held != chat { held = chat }
        pointer = point
        let aim = aim(for: chat, at: point)
        if self.aim != aim { self.aim = aim }
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
        let center = frame.midY + lift.shift
        lift.slot = lift.order.filter { $0 != item.id }.filter { (lift.frames[$0]?.midY ?? 0) < center }.count
        if lift != self.lift { self.lift = lift }
    }

    func offset(for id: UUID) -> CGFloat {
        guard let lift, let from = lift.order.firstIndex(of: lift.id), let index = lift.order.firstIndex(of: id),
              let height = lift.frames[lift.id]?.height
        else { return 0 }
        if id == lift.id { return lift.shift }
        if from < lift.slot, index > from, index <= lift.slot { return -(height + 1) }
        if from > lift.slot, index >= lift.slot, index < from { return height + 1 }
        return 0
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
        if hovered != hit { hovered = hit }
    }

    func fold(at point: CGPoint) -> Bool {
        if let id = cards.filter({ $0.value.contains(point) }).min(by: { $0.value.height < $1.value.height })?.key,
           let index = items.firstIndex(where: { $0.id == id }) {
            withAnimation(Style.fold(items[index].folded)) { items[index].folded.toggle() }
            return true
        }
        if let agent = inboxes.first(where: { $0.value.contains(point) })?.key {
            let key = "folded.agent." + agent.rawValue
            let folded = UserDefaults.standard.bool(forKey: key)
            withAnimation(Style.fold(folded)) { UserDefaults.standard.set(!folded, forKey: key) }
            return true
        }
        guard let id = zone(at: point), let space = desktops.first(where: { $0.id == id }) else { return false }
        let key = "folded." + (space == home ? "home" : space.uuid)
        let folded = UserDefaults.standard.bool(forKey: key)
        withAnimation(Style.fold(folded)) { UserDefaults.standard.set(!folded, forKey: key) }
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
        let (found, named) = await Task.detached {
            let windows = Sky.windows(in: ids)
            let titles = trusted ? Access.titles(for: Set(windows.map(\.pid))) : [:]
            return (windows, titles)
        }.value
        var fronts: [UInt64: Sky.Window] = [:]
        for window in found where fronts[window.space] == nil { fronts[window.space] = window }
        self.fronts = fronts
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
        if current != self.current { self.current = current }
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
        pulse = Task { [weak self] in
            while !Task.isCancelled {
                self?.glance()
                try? await Task.sleep(for: .milliseconds(400))
            }
        }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(2))
            }
        }
        sense = Task { [weak self] in
            while !Task.isCancelled {
                await self?.listen()
                try? await Task.sleep(for: .milliseconds(1500))
            }
        }
    }

    private func listen() async {
        let found = await Task.detached { Hooks.read() }.value
        var beats: [String: Beat] = [:]
        for beat in found where (beats[beat.id]?.time ?? .distantPast) <= beat.time { beats[beat.id] = beat }
        if beats != self.beats { self.beats = beats }
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
        var titles: [String: String] = [:]
        for result in results {
            let title = result.found?.title ?? ""
            if !title.isEmpty { titles[result.id] = title }
            let fallback = result.cwd.isEmpty ? "Untitled" : URL(fileURLWithPath: result.cwd).lastPathComponent
            named[result.id] = title.isEmpty ? (named[result.id] ?? fallback) : title
            if result.found?.hidden == true || (result.found == nil && result.agent == .codex) {
                hidden.insert(result.id)
            } else {
                hidden.remove(result.id)
            }
        }
        if named != self.named { self.named = named }
        if hidden != self.hidden { self.hidden = hidden }
        let next = items.map { item in
            var item = item
            for index in item.chats.indices {
                if let title = titles[item.chats[index].id] { item.chats[index].title = title }
            }
            return item
        }
        if next != items { items = next }
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
