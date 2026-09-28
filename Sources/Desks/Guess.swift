import Foundation
import SQLite3

enum Guess {
    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static let support = home.appendingPathComponent("Library/Application Support")

    private static let guide = """
    You sort a person's coding-assistant conversations into their task list.
    You are given their numbered tasks and the messages the person sent in one conversation.
    Decide which single task the conversation is work on.
    Answer 0 when no task fits, when two fit equally well, or when you would be guessing.
    Sharing a topic is not enough. The conversation must be work on that task.
    Reply with only this JSON and nothing else: {"about": "<one sentence on what the conversation is doing>", "task": <number or 0>}
    """

    struct Brain {
        let agent: Agent
        let path: String
        let args: (String, String) -> [String]
    }

    private static var picked: Brain?
    private static var refused: Set<String> = []
    private static var learned: [Agent: String] = [:]

    static func learn(_ paths: [Agent: String]) {
        for (agent, path) in paths where learned[agent] != path {
            guard FileManager.default.isExecutableFile(atPath: path) else { continue }
            learned[agent] = path
            refused.remove(path)
        }
    }

    private static func model(_ agent: Agent, _ fallback: String) -> String {
        UserDefaults.standard.string(forKey: "model." + agent.rawValue) ?? fallback
    }

    private static func newest(_ folder: String) -> String? {
        let root = support.appendingPathComponent(folder).appendingPathComponent("claude-code")
        let manager = FileManager.default
        let versions = (try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        let ready = versions.filter { manager.fileExists(atPath: $0.appendingPathComponent(".verified").path) }
        let sorted = ready.sorted { left, right in
            left.lastPathComponent.compare(right.lastPathComponent, options: .numeric) == .orderedAscending
        }
        guard let last = sorted.last else { return nil }
        let binary = last.appendingPathComponent("claude.app/Contents/MacOS/claude")
        return manager.isExecutableFile(atPath: binary.path) ? binary.path : nil
    }

    private static var brains: [Brain] {
        let manager = FileManager.default
        func first(_ paths: [String]) -> String? {
            paths.first { manager.isExecutableFile(atPath: $0) }
        }
        func local(_ agent: Agent) -> [String] {
            let name = agent.rawValue
            return [learned[agent],
                    home.appendingPathComponent(".local/bin/" + name).path,
                    "/opt/homebrew/bin/" + name,
                    "/usr/local/bin/" + name].compactMap { $0 }
        }
        var found: [Brain] = []
        if let path = first(local(.devin) + ["/Applications/Devin.app/Contents/Resources/app/extensions/windsurf/devin/bin/devin"]) {
            let name = model(.devin, "gpt-6-luna-none")
            found.append(Brain(agent: .devin, path: path) { guide, body in
                ["--model", name, "--permission-mode", "auto", "--respect-workspace-trust", "false", "-p", guide + "\n\n" + body]
            })
        }
        if let path = first(local(.codex)) {
            let name = model(.codex, "gpt-5.6-luna")
            found.append(Brain(agent: .codex, path: path) { guide, body in
                ["exec", "-m", name, "-c", "model_reasoning_effort=\"low\"", "--skip-git-repo-check",
                 "--ephemeral", "--ignore-rules", guide + "\n\n" + body]
            })
        }
        if let path = first(local(.claude) + [newest("Claude-3p"), newest("Claude")].compactMap { $0 }) {
            let name = model(.claude, "haiku")
            found.append(Brain(agent: .claude, path: path) { guide, body in
                ["-p", "--model", name, "--system-prompt", guide, "--strict-mcp-config",
                 "--disallowedTools", "*", "--no-session-persistence", body]
            })
        }
        return found.filter { !refused.contains($0.path) }
    }

    static func sort(_ chat: Chat, title: String, cwd: String, tasks: [(id: UUID, text: String)]) -> UUID? {
        guard tasks.count > 0 else { return nil }
        let said = turns(chat)
        guard !said.isEmpty else { return nil }
        var order = Array(tasks.indices)
        var seed = UInt64(truncatingIfNeeded: chat.id.hashValue) | 1
        for slot in stride(from: order.count - 1, to: 0, by: -1) {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            order.swapAt(slot, Int(seed >> 33) % (slot + 1))
        }
        let card = order.enumerated().map { "\($0.offset + 1). \(tasks[$0.element].text)" }.joined(separator: "\n")
        let folder = URL(fileURLWithPath: cwd).lastPathComponent
        var body = "Tasks:\n" + card + "\n\nThe person's messages"
        if !folder.isEmpty { body += ", in a conversation held in the folder \(folder)" }
        if !title.isEmpty, title != "Untitled" { body += ", titled \"\(title)\"" }
        body += ":\n" + said.enumerated().map { "\($0.offset + 1)) \($0.element)" }.joined(separator: "\n")

        for brain in (picked.map { [$0] } ?? brains) {
            guard let reply = call(brain, body), let slot = number(reply) else {
                if picked?.path == brain.path { picked = nil }
                refused.insert(brain.path)
                continue
            }
            picked = brain
            guard slot >= 1, slot <= order.count else { return nil }
            return tasks[order[slot - 1]].id
        }
        return nil
    }

    private static var scratch: String? {
        let manager = FileManager.default
        let real = home.appendingPathComponent(".local/share/devin/credentials.toml")
        guard manager.fileExists(atPath: real.path) else { return nil }
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("desks", isDirectory: true)
        let folder = root.appendingPathComponent("devin", isDirectory: true)
        let link = folder.appendingPathComponent("credentials.toml")
        try? manager.createDirectory(at: folder, withIntermediateDirectories: true)
        if !manager.fileExists(atPath: link.path) {
            try? manager.removeItem(at: link)
            try? manager.createSymbolicLink(at: link, withDestinationURL: real)
        }
        return manager.fileExists(atPath: link.path) ? root.path : nil
    }

    private static func shell(_ brain: Brain) -> [String: String] {
        var env = [
            "HOME": home.path,
            "USER": NSUserName(),
            "LOGNAME": NSUserName(),
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "TERM": "dumb",
            "DESKS_CLASSIFY": "1",
        ]
        if brain.agent == .devin, let scratch { env["XDG_DATA_HOME"] = scratch }
        return env
    }

    private static func call(_ brain: Brain, _ body: String) -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: brain.path)
        task.arguments = brain.args(guide, body)
        task.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        task.environment = shell(brain)
        let out = Pipe()
        task.standardOutput = out
        task.standardError = Pipe()
        task.standardInput = FileHandle.nullDevice
        do {
            try task.run()
        } catch {
            return nil
        }
        let watch = DispatchWorkItem { if task.isRunning { task.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 90, execute: watch)
        let data = (try? out.fileHandleForReading.readToEnd()) ?? Data()
        task.waitUntilExit()
        watch.cancel()
        guard task.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func number(_ reply: String) -> Int? {
        let pattern = try? NSRegularExpression(pattern: "\\{[^{}]*\"task\"[^{}]*\\}")
        let range = NSRange(reply.startIndex..., in: reply)
        let hits = pattern?.matches(in: reply, range: range) ?? []
        for hit in hits.reversed() {
            guard let found = Range(hit.range, in: reply),
                  let data = String(reply[found]).data(using: .utf8),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            if let slot = row["task"] as? Int { return slot }
            if let text = row["task"] as? String, let slot = Int(text) { return slot }
        }
        return nil
    }

    private static func turns(_ chat: Chat, limit: Int = 6, each: Int = 400) -> [String] {
        var found: [String] = []
        switch chat.agent {
        case .claude:
            guard let file = transcript(chat.session) else { return [] }
            for line in lines(file) {
                guard let data = line.data(using: .utf8),
                      let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      row["type"] as? String == "user", row["isSidechain"] as? Bool != true,
                      let message = row["message"] as? [String: Any], message["role"] as? String == "user"
                else { continue }
                if let text = message["content"] as? String {
                    keep(text, &found, each)
                } else if let blocks = message["content"] as? [[String: Any]] {
                    guard !blocks.contains(where: { $0["type"] as? String == "tool_result" }) else { continue }
                    keep(blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: " "), &found, each)
                }
                if found.count >= limit { break }
            }
        case .codex:
            guard let file = rollout(chat.session) else { return [] }
            for line in lines(file) {
                guard let data = line.data(using: .utf8),
                      let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      row["type"] as? String == "response_item",
                      let payload = row["payload"] as? [String: Any],
                      payload["type"] as? String == "message", payload["role"] as? String == "user",
                      let blocks = payload["content"] as? [[String: Any]]
                else { continue }
                keep(blocks.compactMap { $0["text"] as? String }.joined(separator: " "), &found, each)
                if found.count >= limit { break }
            }
        case .devin:
            let path = home.appendingPathComponent(".local/share/devin/cli/sessions.db").path
            for message in rows(path, "select chat_message from message_nodes where session_id = ? order by created_at", chat.session) {
                guard let data = message.data(using: .utf8),
                      let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      row["role"] as? String == "user"
                else { continue }
                if let text = row["content"] as? String {
                    keep(text, &found, each)
                } else if let blocks = row["content"] as? [[String: Any]] {
                    keep(blocks.compactMap { $0["text"] as? String }.joined(separator: " "), &found, each)
                }
                if found.count >= limit { break }
            }
        case .code:
            return []
        }
        return found
    }

    private static func keep(_ text: String, _ found: inout [String], _ each: Int) {
        let clean = scrub(text)
        guard clean.count > 12, !clean.hasPrefix("<"), !clean.hasPrefix("#") else { return }
        found.append(String(clean.prefix(each)))
    }

    private static func scrub(_ text: String) -> String {
        var out = text.replacingOccurrences(of: "\\[[^\\]]*\\]\\([^)]*\\)", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\S+://\\S+", with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func lines(_ url: URL) -> [String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
    }

    private static func transcript(_ session: String) -> URL? {
        let manager = FileManager.default
        for folder in ["Claude-3p", "Claude"] {
            let root = support.appendingPathComponent(folder).appendingPathComponent("claude-code-sessions")
            guard let file = hunt(root, { $0 == session + ".json" }),
                  let data = try? Data(contentsOf: file),
                  let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cli = row["cliSessionId"] as? String
            else { continue }
            let projects = home.appendingPathComponent(".claude/projects")
            if let cwd = row["cwd"] as? String {
                let slug = cwd.replacingOccurrences(of: "[/._]", with: "-", options: .regularExpression)
                let direct = projects.appendingPathComponent(slug).appendingPathComponent(cli + ".jsonl")
                if manager.fileExists(atPath: direct.path) { return direct }
            }
            return hunt(projects, { $0 == cli + ".jsonl" })
        }
        return nil
    }

    private static func rollout(_ session: String) -> URL? {
        hunt(home.appendingPathComponent(".codex/sessions"), { $0.hasSuffix("-" + session + ".jsonl") })
    }

    private static func hunt(_ root: URL, _ match: (String) -> Bool) -> URL? {
        guard let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return nil }
        for case let url as URL in walk where match(url.lastPathComponent) { return url }
        return nil
    }

    private static func rows(_ path: String, _ sql: String, _ value: String?) -> [String] {
        guard FileManager.default.fileExists(atPath: path) else { return [] }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return []
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        if let value { sqlite3_bind_text(statement, 1, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        var found: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) { found.append(String(cString: text)) }
        }
        return found
    }
}
