import AppKit
import SQLite3

enum Agent: String, Codable, CaseIterable {
    case claude, codex, devin, code

    var name: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .devin: "Devin"
        case .code: "VS Code"
        }
    }

    var bundle: String {
        switch self {
        case .claude: "com.anthropic.claudefordesktop"
        case .codex: "com.openai.codex"
        case .devin: "com.exafunction.windsurf"
        case .code: "com.microsoft.VSCode"
        }
    }

    var app: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
    }

    var icon: NSImage? {
        let url = app?.bundleURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle)
        return url.map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

    func link(_ session: String) -> URL? {
        switch self {
        case .claude: return URL(string: "claude://claude.ai/epitaxy/\(session)")
        case .codex: return URL(string: "codex://threads/\(session)")
        case .code: return URL(string: "vscode://agents/agent-host-session/copilotcli/\(Self.peer(session))")
        case .devin:
            var parts = URLComponents(string: "devin://acp/session")
            parts?.queryItems = [URLQueryItem(name: "sessionId", value: session), URLQueryItem(name: "connectorId", value: "devin-cli")]
            return parts?.url
        }
    }

    func look(_ session: String) -> (title: String, hidden: Bool)? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch self {
        case .claude:
            let support = home.appendingPathComponent("Library/Application Support")
            for folder in ["Claude-3p", "Claude"] {
                let root = support.appendingPathComponent(folder).appendingPathComponent("claude-code-sessions")
                for account in Self.folders(root) {
                    for org in Self.folders(account) {
                        let file = org.appendingPathComponent(session + ".json")
                        guard let data = try? Data(contentsOf: file),
                              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        return (json["title"] as? String ?? "", json["isArchived"] as? Bool ?? false)
                    }
                }
            }
            return nil
        case .codex:
            let path = home.appendingPathComponent(".codex/state_5.sqlite").path
            guard let row = Self.row(path, "select coalesce(nullif(name, ''), title), archived, source from threads where id = ?", session) else { return nil }
            let source = row[2] ?? ""
            return (row[0] ?? "", row[1] == "1" || source.hasPrefix("{"))
        case .devin:
            let path = home.appendingPathComponent(".local/share/devin/cli/sessions.db").path
            guard let row = Self.row(path, "select title, hidden from sessions where id = ?", session) else { return nil }
            return (row[0] ?? "", row[1] == "1")
        case .code:
            let path = home.appendingPathComponent("Library/Application Support/Code/User/globalStorage/agent-host.db").path
            guard let row = Self.row(path, "select payload from sessions_v2 where session_uri = ?", "copilotcli:/" + Self.peer(session)),
                  let data = row[0]?.data(using: .utf8),
                  let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["data"] as? [String: Any]
            else { return nil }
            return (json["summary"] as? String ?? "", json["isArchived"] as? Bool ?? false)
        }
    }

    private static func peer(_ session: String) -> String {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Code/agentSessionData")
            .appendingPathComponent(session).appendingPathComponent("session.db").path
        guard let value = row(path, "select value from session_metadata where key = ?", "peerChatBacking")?.first ?? nil,
              var encoded = value.split(separator: "/").last.map(String.init)
        else { return session }
        encoded = encoded.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded), let uri = String(data: data, encoding: .utf8),
              uri.hasPrefix("copilotcli:/")
        else { return session }
        return String(uri.dropFirst("copilotcli:/".count))
    }

    private static func folders(_ url: URL) -> [URL] {
        let items = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        return items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private static func row(_ path: String, _ sql: String, _ value: String) -> [String?]? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 200)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return (0..<sqlite3_column_count(statement)).map { index in
            sqlite3_column_text(statement, index).map { String(cString: $0) }
        }
    }
}

enum Status: Equatable {
    case idle, running, waiting, done, ended

    init(_ event: String) {
        switch event {
        case "UserPromptSubmit", "userPromptSubmitted", "PostToolUse", "postToolUse": self = .running
        case "PermissionRequest", "Notification:permission_prompt", "Notification:agent_needs_input", "Notification:elicitation_dialog": self = .waiting
        case "Stop", "agentStop", "sessionEnd", "Notification:idle_prompt": self = .done
        case "SessionEnd": self = .ended
        default: self = .idle
        }
    }

    var label: String {
        switch self {
        case .idle: "Idle"
        case .running: "Working"
        case .waiting: "Needs you"
        case .done: "Done"
        case .ended: "Ended"
        }
    }
}

struct Beat: Equatable {
    let agent: Agent
    let session: String
    let status: Status
    let cwd: String
    let time: Date

    var id: String { agent.rawValue + ":" + session }
}

struct Chat: Codable, Hashable, Identifiable {
    let agent: Agent
    let session: String
    var title: String

    var id: String { agent.rawValue + ":" + session }
}
