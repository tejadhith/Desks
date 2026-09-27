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

    private static let month: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter
    }()

    @discardableResult
    static func store(_ item: Item) -> Bool {
        let now = Date()
        guard let name = file(item, now) else { return false }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try page(item, now).write(to: folder.appendingPathComponent(name), atomically: true, encoding: .utf8)
        } catch {
            return false
        }
        list(item, now, name)
        return true
    }

    static func open() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    private static func file(_ item: Item, _ now: Date) -> String? {
        var title = item.title.components(separatedBy: CharacterSet(charactersIn: "/:\n\r"))
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        if title.count > 60 {
            title = String(title.prefix(60)).trimmingCharacters(in: .whitespaces) + "…"
        }
        if title.isEmpty { title = "Untitled" }
        let stem = day.string(from: now) + " " + title
        let manager = FileManager.default
        guard manager.fileExists(atPath: folder.appendingPathComponent(stem + ".md").path) else { return stem + ".md" }
        let tail = stem + " " + item.id.uuidString.prefix(8) + ".md"
        return manager.fileExists(atPath: folder.appendingPathComponent(tail).path) ? nil : tail
    }

    private static func page(_ item: Item, _ now: Date) -> String {
        let done = item.todos.filter(\.done).count
        var lines = [
            "---",
            "task: " + quote(item.title),
            "created: " + day.string(from: item.created),
            "archived: " + day.string(from: now),
            "tags: [desks/archive]",
            "id: " + item.id.uuidString,
            "---",
            "",
            "# " + item.title,
            "",
            summary(item, now, done),
        ]
        let detail = item.detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if !detail.isEmpty { lines += ["", detail] }
        if !item.todos.isEmpty {
            lines += ["", "## To-dos", ""]
            lines += item.todos.sorted { $0.done && !$1.done }
                .map { "- [" + ($0.done ? "x" : " ") + "] " + flat($0.text) }
        }
        if !item.chats.isEmpty {
            lines += ["", "## Conversations", ""]
            for chat in item.chats {
                lines.append("- " + chat.agent.name + " — " + flat(chat.title))
                if let link = chat.agent.link(chat.session) { lines.append("  `" + link.absoluteString + "`") }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func summary(_ item: Item, _ now: Date, _ done: Int) -> String {
        var parts = ["Archived " + long.string(from: now)]
        let days = Calendar.current.dateComponents([.day], from: item.created, to: now).day ?? 0
        switch days {
        case 0: parts.append("same day")
        case 1: parts.append("1 day")
        default: parts.append("\(days) days")
        }
        if !item.todos.isEmpty { parts.append("\(done)/\(item.todos.count) to-dos") }
        if item.space == nil { parts.append("never had a desktop") }
        return parts.joined(separator: " · ")
    }

    private static func list(_ item: Item, _ now: Date, _ name: String) {
        let heading = "## " + month.string(from: now)
        var text = (try? String(contentsOf: index, encoding: .utf8)) ?? "# Desks Archive\n"
        if !text.contains(heading) {
            text += "\n" + heading + "\n\n| Archived | Task | To-dos |\n|---|---|---|\n"
        }
        let count = item.todos.isEmpty ? "—" : "\(item.todos.filter(\.done).count)/\(item.todos.count)"
        let link = "[[" + name.replacingOccurrences(of: ".md", with: "") + "]]"
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
