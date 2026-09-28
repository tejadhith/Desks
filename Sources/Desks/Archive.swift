import AppKit

enum Archive {
    static let folder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/Desks/Archive", isDirectory: true)

    private static let index = folder.appendingPathComponent("Archive.md")

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let long: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    private static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM"
        return formatter
    }()

    private static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    static func log(_ todo: Todo, in item: Item) {
        let text = flat(todo.text)
        guard !text.isEmpty, let file = open(item) else { return }
        add(file, "- [x] " + text + " · " + short.string(from: Date()))
    }

    static func undo(_ todo: Todo, in item: Item) {
        let text = flat(todo.text)
        guard !text.isEmpty, let file = find(item), var lines = body(file) else { return }
        guard lines.last?.hasPrefix("- [x] " + text + " · ") == true else { return }
        lines.removeLast()
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    @discardableResult
    static func store(_ item: Item) -> Bool {
        let now = Date()
        guard let file = open(item), var lines = body(file) else { return false }
        if let mark = lines.firstIndex(where: { $0.hasPrefix("created: ") }) {
            lines.insert("archived: " + day.string(from: now), at: mark + 1)
        }
        for todo in item.todos where !todo.done && !flat(todo.text).isEmpty {
            lines.append("- [ ] " + flat(todo.text))
        }
        if lines.last == "## To-dos" { lines.removeLast() }
        let detail = flat(item.detail)
        if !detail.isEmpty, !lines.contains(detail) {
            lines += ["", "## Notes", "", detail]
        }
        if !item.chats.isEmpty {
            lines += ["", "## Conversations", ""]
            for chat in item.chats {
                lines.append("- " + chat.agent.name + " — " + flat(chat.title))
                if let link = chat.agent.link(chat.session) { lines.append("  `" + link.absoluteString + "`") }
            }
        }
        lines += ["", "---", "", summary(item, now)]
        guard (try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)) != nil else { return false }
        list(item, now, file)
        return true
    }

    static func open() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    private static func open(_ item: Item) -> URL? {
        if let file = find(item) { return rename(file, item) }
        guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)) != nil else { return nil }
        let file = folder.appendingPathComponent(name(item))
        let header = [
            "---",
            "task: " + quote(item.title),
            "created: " + day.string(from: item.created),
            "tags: [desks/archive]",
            "id: " + item.id.uuidString,
            "---",
            "",
            "# " + flat(item.title),
            "",
            "## To-dos",
            "",
        ]
        guard (try? header.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)) != nil else { return nil }
        return file
    }

    private static func find(_ item: Item) -> URL? {
        let manager = FileManager.default
        let mark = "id: " + item.id.uuidString
        let expected = folder.appendingPathComponent(name(item))
        if let text = try? String(contentsOf: expected, encoding: .utf8), text.contains(mark) { return expected }
        guard let files = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return nil }
        return files.first { file in
            guard file.pathExtension == "md", file != index,
                  let handle = try? FileHandle(forReadingFrom: file) else { return false }
            defer { try? handle.close() }
            let head = (try? handle.read(upToCount: 512)).flatMap { String(data: $0, encoding: .utf8) }
            return head?.contains(mark) == true
        }
    }

    private static func rename(_ file: URL, _ item: Item) -> URL {
        var file = file
        let wanted = folder.appendingPathComponent(name(item))
        if file != wanted, !FileManager.default.fileExists(atPath: wanted.path),
           (try? FileManager.default.moveItem(at: file, to: wanted)) != nil {
            file = wanted
        }
        guard var lines = body(file) else { return file }
        let title = flat(item.title)
        let task = "task: " + quote(item.title)
        let heading = "# " + title
        guard lines.first(where: { $0.hasPrefix("task: ") }) != task || !lines.contains(heading) else { return file }
        if let mark = lines.firstIndex(where: { $0.hasPrefix("task: ") }) { lines[mark] = task }
        if let mark = lines.firstIndex(where: { $0.hasPrefix("# ") }) { lines[mark] = heading }
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
        return file
    }

    private static func name(_ item: Item) -> String {
        var title = flat(item.title).components(separatedBy: CharacterSet(charactersIn: "/:[]#^|"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if title.count > 60 { title = String(title.prefix(60)).trimmingCharacters(in: .whitespaces) + "…" }
        if title.isEmpty { title = "Untitled" }
        return title + " " + item.id.uuidString.prefix(8) + ".md"
    }

    private static func body(_ file: URL) -> [String]? {
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return nil }
        var lines = text.components(separatedBy: "\n")
        while lines.last?.isEmpty == true { lines.removeLast() }
        return lines
    }

    private static func add(_ file: URL, _ line: String) {
        guard var lines = body(file) else { return }
        if lines.last?.hasPrefix("#") == true { lines.append("") }
        lines.append(line)
        try? (lines.joined(separator: "\n") + "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    private static func summary(_ item: Item, _ now: Date) -> String {
        var parts = ["Archived " + long.string(from: now)]
        let days = Calendar.current.dateComponents([.day], from: item.created, to: now).day ?? 0
        switch days {
        case 0: parts.append("same day")
        case 1: parts.append("1 day")
        default: parts.append("\(days) days")
        }
        if !item.todos.isEmpty { parts.append("\(item.todos.filter(\.done).count)/\(item.todos.count) to-dos") }
        if item.space == nil { parts.append("never had a desktop") }
        return parts.joined(separator: " · ")
    }

    private static func list(_ item: Item, _ now: Date, _ file: URL) {
        let heading = "## " + month.string(from: now)
        var text = (try? String(contentsOf: index, encoding: .utf8)) ?? "# Desks Archive\n"
        if !text.contains(heading) {
            text += "\n" + heading + "\n\n| Archived | Task | To-dos |\n|---|---|---|\n"
        }
        let count = item.todos.isEmpty ? "—" : "\(item.todos.filter(\.done).count)/\(item.todos.count)"
        let link = "[[" + file.deletingPathExtension().lastPathComponent + "]]"
        text += "| " + long.string(from: now) + " | " + link + " | " + count + " |\n"
        try? text.write(to: index, atomically: true, encoding: .utf8)
    }

    private static func flat(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func quote(_ text: String) -> String {
        "\"" + flat(text).replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
