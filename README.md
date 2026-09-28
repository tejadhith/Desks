# Desks

A floating task panel for macOS where every task gets its own real desktop.

Keep a short list of what you are working on in the top-right corner of the screen. Each task owns a Mission Control desktop, so switching tasks switches desktops, and each task shows the windows that live on it.

![Desks answering a coding agent on its task's desktop, dropping a window onto a task, creating a task with its own desktop, and linking a conversation to it](docs/hero.gif)

## Features

<table>
<tr>
<td width="50%" valign="top">
<img src="docs/desktops.gif" alt="Creating a task, which adds its own desktop in Mission Control"><br>
<b>A desktop per task</b><br>
Creating a task takes you to its own desktop, reusing an empty spare one when there is one. Desktop 1 stays home for unsorted windows. Right-click a desktop that isn't a task to remove it.
</td>
<td width="50%" valign="top">
<img src="docs/upcoming.gif" alt="Saving a task for later with Command-Return, then moving an active task to Upcoming"><br>
<b>Upcoming tasks</b><br>
Press <code>⌘↩</code> instead of <code>↩</code> to save a task for later without a desktop, then start it when you are ready. Right-click an active task and choose <b>Move to Upcoming</b> to put it back; its desktop goes away and its windows stay open.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="docs/todos.gif" alt="Writing a description, adding and checking off to-dos, and tucking the list away"><br>
<b>Descriptions and to-dos</b><br>
Jot down what the task is about and keep a checklist. <code>↩</code> adds a to-do or moves to the next one, <code>↑</code>/<code>↓</code> move between them, and <code>⌘↩</code> checks or unchecks one and moves on. Click <b>To-dos</b> to tuck a long list away; collapsed tasks and lists show how many are done.
</td>
<td width="50%" valign="top">
<img src="docs/windows.gif" alt="Expanding a task and clicking its windows to jump to them"><br>
<b>Live window lists</b><br>
See which windows sit on each task's desktop and click one to jump to it.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="docs/switch.gif" alt="Switching tasks by clicking and with Control-number shortcuts"><br>
<b>Switch fast</b><br>
Click a task, or use the macOS <code>⌃1</code>–<code>⌃9</code> desktop shortcuts shown on each task.
</td>
<td width="50%" valign="top">
<img src="docs/organize.gif" alt="Reordering tasks by dragging, renaming one, and scrolling a long name"><br>
<b>Organize</b><br>
Drag a task by its name to reorder it; the others slide out of the way. Double-click a name to rename it, and hover a long name to scroll the rest into view.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="docs/move.gif" alt="Dragging a window by its title bar onto a task, dragging a window row, and using Send to"><br>
<b>Move windows</b><br>
Drag any window by its title bar onto a task in the panel, drag a window's row onto a task, right-click it and choose <b>Send to</b>, or send the front window to a task with one click. The window comes to the front on its new desktop and keeps its size and place, scaled to fit when it moves to another screen.
</td>
<td width="50%" valign="top">
<img src="docs/agents.gif" alt="Linking an unsorted conversation to a task, opening it on the task&#x27;s desktop, and unlinking another"><br>
<b>Coding-agent conversations</b><br>
Link conversations from Claude Code in the Claude app, Codex, Devin, and the VS Code Agents window to a task. Conversations that aren't linked yet wait in an unsorted list for each app; drag one onto a task to link it, and hover a linked one and click × to unlink it. Clicking a linked conversation brings the app's window to the task's desktop and opens that conversation; clicking an unlinked one takes you to the desktop where the app is. Each conversation shows whether it is working, needs you, or is done. See <a href="#coding-agents">Coding agents</a>.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="docs/displays.gif" alt="Moving a task and its windows to another screen"><br>
<b>Multiple displays</b><br>
Desktops on every screen are listed and switched correctly. Move a task to another screen from its right-click menu; it takes over an empty spare desktop there if there is one. When a screen is unplugged, its tasks move to the built-in screen and return when it is plugged back in.
</td>
<td width="50%" valign="top">
<img src="docs/away.gif" alt="Folding the panel, snapping it back to the corner, and stepping below a notification"><br>
<b>Stays out of the way</b><br>
Tasks collapse to a single line with app icons, the panel sizes itself to its content, and it snaps back to the corner after you move it. It steps below notification banners and returns when they leave.
</td>
</tr>
<tr>
<td width="50%" valign="top">
<img src="docs/gestures.gif" alt="Tucking the panel into the screen edge, seeing through it, and folding a task with Option"><br>
<b>Gestures from anywhere</b><br>
Double-tap <code>⌃</code> to tuck the panel into the screen edge (hover the edge to peek at it), or double-tap and hold <code>⌃</code> to see through it. Double-tap <code>⌥</code> to fold the to-dos or task under the pointer, or the whole panel when the pointer is elsewhere. Clicking the header also folds the panel.
</td>
<td width="50%"></td>
</tr>
</table>

## Requirements

- macOS 14 or later (developed on macOS 26)
- Xcode or the Swift command line tools (Swift 5.9+)
- Accessibility permission for Desks

## Build and run

```bash
./build.sh
```

The script builds a release binary, bundles `Desks.app`, signs it (with your Apple Development certificate if one is installed, otherwise ad hoc), installs it to `~/Applications`, and launches it.

On first launch, allow Desks under **System Settings → Privacy & Security → Accessibility**.

For instant switching, turn on **Switch to Desktop 1–9** under **System Settings → Keyboard → Keyboard Shortcuts → Mission Control**. Without them, Desks switches through Mission Control instead.

## Coding agents

Coding-agent support is off until you choose **Connect Coding Agents** from the Desks menu bar icon. Desks then adds hook entries for each agent it finds:

| Agent | File |
|---|---|
| Claude Code in the Claude app | `~/.claude/settings.json` |
| Codex (app and CLI) | `~/.codex/hooks.json` |
| Devin | `~/.config/devin/config.json` |
| VS Code Agents window (GitHub Copilot) | `~/.copilot/hooks/desks.json` |

Your existing entries and formatting are kept, and each file is copied to `<file>.desks-backup` before its first change. Codex runs new hooks only after you approve them with `/hooks`.

Each hook runs a small script that records the app, session ID, event name, working folder, the program that ran it, and the time in `~/Library/Application Support/Desks/events/`. Prompts and replies are never written there. Titles come from each app's own local session data. **Disconnect Coding Agents** removes the entries, the script, and the recorded events.

Desks sorts a new conversation onto a task by itself. It reads the messages you sent — from the app's own session files, not from the recorded events — and asks a coding agent's own CLI, whichever of Devin, Codex or Claude Code answers, which one task the conversation is work on. Your task names, descriptions and to-dos go with the question, and the answer is one task or none: a conversation that matches nothing stays unsorted, and you can still drag it yourself. The question runs as its own one-shot process, so it never enters the conversation you are having, and Devin's runs against a scratch folder so it leaves nothing in your own history. Unlinking a conversation from a task keeps it off that task for good, but it can still be sorted onto another.

A conversation appears after its next prompt and leaves the unsorted list 24 hours after its last activity, as each app records it. Archived, deleted and empty conversations never show. An app's unsorted list disappears while the app isn't running; conversations linked to tasks stay. An unlinked conversation goes back to the unsorted list if it was active in the last 24 hours, otherwise it leaves Desks. Not supported yet: agent CLIs running in a terminal, Claude chats (only Claude Code sessions), and cloud sessions.

## Archive

Every task keeps a Markdown file in `~/Documents/Desks/Archive`, so work leaves a record instead of disappearing. The file appears the first time you check off a to-do and each later tick appends a line with its date, which means a task you keep for months still logs what got finished:

```markdown
---
task: "Repaint the hallway"
created: 2026-04-02
tags: [desks/archive]
id: 00000000-0000-0000-0000-000000000000
---

# Repaint the hallway

## To-dos

- [x] Pick a colour · 3 Apr
- [x] Sand the trim · 11 Apr
```

Unchecking a to-do removes its line again if it was the last one written; edit the file yourself after that. Renaming a task renames the file and its heading.

Deleting a task closes its file out: whatever was left unfinished, the description, any linked conversations with their deep links, and how long the task was around. Nothing written earlier is rewritten, so your own edits survive.

```markdown
- [ ] Second coat

## Notes

Two coats, satin finish.

## Conversations

- Codex — Paint coverage per coat
  `codex://threads/00000000-0000-0000-0000-000000000000`

---

Archived 11 Apr 2026 · 9 days · 2/3 to-dos
```

`Archive.md` in the same folder gains a row per deleted task, grouped by month. Choose **Open Archive** from the Desks menu bar icon to get to the folder; macOS asks once for access to your Documents folder the first time something is written.

Files are written once and never rewritten, so you can edit them freely. To read the archive in a notes app that keeps a folder of Markdown, such as Obsidian, point the folder at your vault before the first delete:

```sh
ln -s ~/Vault/Desks ~/Documents/Desks
```

## How it works

macOS has no public API for desktops, so Desks combines a few techniques that do not require disabling System Integrity Protection:

- It reads desktops and their windows through private SkyLight functions.
- It moves a window to another desktop with SkyLight's bridged window-management operation, which works on any app's window without switching desktops. If that is unavailable it falls back to reassigning a single-window app, then to dragging the window's thumbnail in Mission Control.
- It adds, removes, and switches desktops through Mission Control and the desktop shortcuts, so the Dock always knows about every desktop. Moving a task to another screen makes a desktop there, moves the windows over, and removes the old one.
- It opens a conversation through the app's own link (`claude://`, `codex://`, `devin://`, `vscode://`), after moving the app's window with the same window operation.

Because these rely on private behavior, a macOS update can break them.

Tasks and their linked conversations are stored locally in `~/Library/Application Support/Desks/items.json`. Windows are read live and never stored. Desks makes no network connections.

## License

MIT, see [LICENSE](LICENSE). Space Grotesk is bundled under the SIL Open Font License 1.1, see [Resources/Fonts/OFL.txt](Resources/Fonts/OFL.txt).
