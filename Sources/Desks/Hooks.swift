import Foundation
import JavaScriptCore

enum Hooks {
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Desks", isDirectory: true)
    static let events = folder.appendingPathComponent("events", isDirectory: true)
    private static let script = folder.appendingPathComponent("hook")
    private static let mark = "Desks/hook"
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    private static let body = #"""
    #!/bin/sh
    agent="$1"
    event="$2"
    input=$(cat)
    field() {
        printf '%s' "$input" | /usr/bin/plutil -extract "$1" raw -o - - 2>/dev/null
    }
    if [ -n "$DEVIN_PROJECT_DIR" ]; then
        agent=devin
        session=$(field session_id)
    else
        case "$agent" in
            claude)
                case "$CLAUDE_CODE_ENTRYPOINT" in
                    claude-desktop*) session="$CLAUDE_CODE_HOST_SESSION_ID" ;;
                    *) exit 0 ;;
                esac
                ;;
            code)
                session=$(field sessionId)
                [ -n "$session" ] || session=$(field session_id)
                ;;
            *)
                session=$(field session_id)
                ;;
        esac
    fi
    [ -n "$session" ] || exit 0
    if [ "$event" = Notification ]; then
        kind=$(field notification_type)
        case "$kind" in
            permission_prompt|agent_needs_input|elicitation_dialog|idle_prompt) event="Notification:$kind" ;;
            *) exit 0 ;;
        esac
    fi
    cwd=$(field cwd | sed 's/\\/\\\\/g; s/"/\\"/g')
    dir="$HOME/Library/Application Support/Desks/events"
    mkdir -p "$dir"
    name=$(printf '%s.%s' "$agent" "$session" | tr -c 'A-Za-z0-9_.-' '_')
    printf '{"agent":"%s","session":"%s","event":"%s","cwd":"%s","time":%s}\n' "$agent" "$session" "$event" "$cwd" "$(date +%s)" > "$dir/.$name.$$" && mv -f "$dir/.$name.$$" "$dir/$name.json"
    exit 0

    """#

    private static let merge = """
    (function (text, plan, mark) {
        var root = text.trim() ? JSON.parse(text) : {};
        var before = JSON.stringify(root);
        if (!root.hooks || typeof root.hooks !== 'object' || Array.isArray(root.hooks)) root.hooks = {};
        var hooks = root.hooks;
        Object.keys(hooks).forEach(function (key) {
            if (Array.isArray(hooks[key])) hooks[key] = hooks[key].filter(function (group) { return JSON.stringify(group).indexOf(mark) < 0; });
        });
        var wanted = JSON.parse(plan);
        Object.keys(wanted).forEach(function (key) { (hooks[key] = hooks[key] || []).push(wanted[key]); });
        Object.keys(hooks).forEach(function (key) { if (Array.isArray(hooks[key]) && !hooks[key].length) delete hooks[key]; });
        if (!Object.keys(hooks).length) delete root.hooks;
        return JSON.stringify(root) === before ? null : JSON.stringify(root, null, 2) + '\\n';
    })
    """

    static var connected: Bool {
        FileManager.default.fileExists(atPath: script.path)
    }

    private static let claude = ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Notification", "Stop", "SessionEnd"]
    private static let devin = ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]
    private static let codex = ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]
    private static let copilot = ["sessionStart", "userPromptSubmitted", "postToolUse", "agentStop", "sessionEnd"]

    private static var targets: [(agent: Agent, file: URL, events: [String])] {
        let manager = FileManager.default
        func has(_ path: String) -> Bool { manager.fileExists(atPath: home.appendingPathComponent(path).path) }
        var targets: [(Agent, URL, [String])] = []
        if has(".claude") { targets.append((.claude, home.appendingPathComponent(".claude/settings.json"), claude)) }
        if has(".codex") { targets.append((.codex, home.appendingPathComponent(".codex/hooks.json"), codex)) }
        if has(".local/share/devin") { targets.append((.devin, home.appendingPathComponent(".config/devin/config.json"), devin)) }
        if has(".copilot") { targets.append((.code, home.appendingPathComponent(".copilot/hooks/desks.json"), copilot)) }
        return targets
    }

    @discardableResult
    static func install() -> [Agent] {
        let targets = targets
        guard !targets.isEmpty else { return [] }
        let manager = FileManager.default
        try? manager.createDirectory(at: events, withIntermediateDirectories: true)
        if (try? String(contentsOf: script, encoding: .utf8)) != body {
            try? body.write(to: script, atomically: true, encoding: .utf8)
        }
        try? manager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        for target in targets {
            let name = target.agent.rawValue
            if target.agent == .code {
                try? manager.createDirectory(at: target.file.deletingLastPathComponent(), withIntermediateDirectories: true)
                let hooks = plan(target.events) { ["type": "command", "bash": command(name, $0), "timeoutSec": 10] }.mapValues { [$0] }
                if let data = try? JSONSerialization.data(withJSONObject: ["version": 1, "hooks": hooks], options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
                   (try? Data(contentsOf: target.file)) != data {
                    try? data.write(to: target.file, options: .atomic)
                }
            } else {
                edit(target.file, plan(target.events) { ["hooks": [["type": "command", "command": command(name, $0), "timeout": 10]]] })
            }
        }
        return targets.map(\.agent)
    }

    static func remove() {
        let manager = FileManager.default
        for target in targets {
            if target.agent == .code {
                try? manager.removeItem(at: target.file)
                let folder = target.file.deletingLastPathComponent()
                if (try? manager.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try? manager.removeItem(at: folder) }
            } else if manager.fileExists(atPath: target.file.path) {
                edit(target.file, [:])
            }
        }
        try? manager.removeItem(at: script)
        try? manager.removeItem(at: events)
    }

    static func read() -> [Beat] {
        let manager = FileManager.default
        let files = (try? manager.contentsOfDirectory(at: events, includingPropertiesForKeys: nil)) ?? []
        let stale = Date().addingTimeInterval(-7 * 86400)
        return files.compactMap { file in
            guard file.pathExtension == "json", !file.lastPathComponent.hasPrefix("."),
                  let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let agent = (json["agent"] as? String).flatMap(Agent.init(rawValue:)),
                  let session = json["session"] as? String, !session.isEmpty,
                  let seconds = json["time"] as? Double
            else { return nil }
            let time = Date(timeIntervalSince1970: seconds)
            guard time > stale else {
                try? manager.removeItem(at: file)
                return nil
            }
            return Beat(agent: agent, session: session, status: Status(json["event"] as? String ?? ""), cwd: json["cwd"] as? String ?? "", time: time)
        }
    }

    private static func command(_ agent: String, _ event: String) -> String {
        "\"$HOME/Library/Application Support/Desks/hook\" \(agent) \(event)"
    }

    private static func plan(_ events: [String], _ entry: (String) -> [String: Any]) -> [String: [String: Any]] {
        Dictionary(uniqueKeysWithValues: events.map { ($0, entry($0)) })
    }

    private static func edit(_ file: URL, _ plan: [String: [String: Any]]) {
        let manager = FileManager.default
        let exists = manager.fileExists(atPath: file.path)
        guard let text = exists ? (try? String(contentsOf: file, encoding: .utf8)) : "",
              let data = try? JSONSerialization.data(withJSONObject: plan, options: [.sortedKeys, .withoutEscapingSlashes]),
              let wanted = String(data: data, encoding: .utf8),
              let context = JSContext(),
              let result = context.evaluateScript(merge)?.call(withArguments: [text, wanted, mark]),
              context.exception == nil, result.isString, let output = result.toString()
        else { return }
        let backup = file.appendingPathExtension("desks-backup")
        if exists, !manager.fileExists(atPath: backup.path) {
            try? manager.copyItem(at: file, to: backup)
        }
        let permissions = (try? manager.attributesOfItem(atPath: file.path))?[.posixPermissions]
        try? manager.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard (try? output.write(to: file, atomically: true, encoding: .utf8)) != nil else { return }
        if let permissions { try? manager.setAttributes([.posixPermissions: permissions], ofItemAtPath: file.path) }
    }
}
