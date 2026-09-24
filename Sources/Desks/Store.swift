import AppKit

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
    @Published private(set) var hovered: UInt64?
    @Published private(set) var front: UInt32?
    private var zones: [UInt64: CGRect] = [:]
    var snap: () -> Void = {}

    private let url: URL
    private var titles: [UInt32: String] = [:]
    private var fronts: [UInt64: Sky.Window] = [:]
    private var loop: Task<Void, Never>?
    private var pulse: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []

    init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Desks", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appendingPathComponent("items.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        items = (try? decoder.decode([Item].self, from: Data(contentsOf: url))) ?? []
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

    func space(for item: Item) -> Sky.Space? {
        guard let uuid = item.space, let space = spaces.first(where: { $0.uuid == uuid }), space != home else { return nil }
        return space
    }

    func windows(on space: Sky.Space) -> [Sky.Window] {
        windows.filter { $0.space == space.id }
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

    func add(_ title: String) {
        let item = Item(title: title)
        items.append(item)
        create(for: item)
    }

    func create(for item: Item) {
        guard ready() else { return }
        let id = item.id
        let display = spaces.first { $0.id == current }?.display ?? home?.display ?? ""
        run {
            let before = Set(Sky.spaces().map(\.id))
            guard await Mission.add(on: display) else { return }
            var made: Sky.Space?
            for _ in 0..<30 where made == nil {
                try? await Task.sleep(for: .milliseconds(100))
                made = Sky.spaces().first { !before.contains($0.id) }
            }
            await Mission.close()
            guard let made else { return }
            self.link(id, to: made)
            try? await Task.sleep(for: .milliseconds(700))
            await self.go(to: made)
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
        let fallback = siblings.first { $0 == home } ?? siblings.last { $0.index < space.index } ?? siblings[0]
        let back = current
        run {
            if !Sky.visible().contains(fallback.id) {
                await self.go(to: fallback)
                try? await Task.sleep(for: .milliseconds(400))
            }
            guard await Mission.remove(at: space.index, on: space.display) else { return }
            try? await Task.sleep(for: .milliseconds(500))
            if back != space.id, back != Sky.current(), let previous = Sky.spaces().first(where: { $0.id == back }) {
                await self.go(to: previous)
            }
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
                if !Sky.visible().contains(space.id) {
                    await self.go(to: space)
                    try? await Task.sleep(for: .milliseconds(350))
                }
                if let frame = Sky.frame(of: space.display), Carry.place(window, in: frame) {
                    try? await Task.sleep(for: .milliseconds(400))
                    moved = Sky.windows(in: [space.id]).contains { $0.id == window.id }
                }
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

    func track(_ window: Sky.Window, at point: CGPoint) {
        if carrying?.id != window.id { carrying = window }
        pointer = point
        let hit = zone(at: point)
        if hovered != hit { hovered = hit }
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
        if spaces != self.spaces { self.spaces = spaces }
        if windows != self.windows { self.windows = windows }
        if current != self.current { self.current = current }
    }

    private func tell(_ message: String) {
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
