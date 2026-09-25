# Kickoff

A native Swift menu bar app (universal binary for Apple Silicon and Intel, macOS 13+, no Dock icon). It creates a task folder in your agent folder and opens it in VS Code.

## Usage

- Press **⌃⌥⌘T** (the default shortcut; see below to change it), or click the 📁+ icon in the menu bar and choose **New Task…**.
- Type a task name and press Enter. The app creates `<agent folder>/<name>` and opens it in VS Code. If a folder with that name already exists, the app opens it.
- Leave the name empty and press Enter. The app creates `<agent folder>/tmp-YYYYMMDD-HHmmss` and opens it.
- Press Esc to cancel.

The first time you use it, the app asks you to choose the agent folder. To change it later, use **Choose Agent Folder…** in the menu.

## Temp folder cleanup

A launchd job runs `Kickoff --cleanup` every day at 05:00. The job moves `tmp-*` folders created before that 05:00 to the **Trash**, where you can still recover them.
- A renamed folder no longer starts with `tmp-`, so the job keeps it.
- If the Mac is asleep at 05:00, the job runs when it wakes. It still removes only the folders created before 05:00.
- **Trash All Temp Folders Now** in the menu trashes every `tmp-*` folder immediately.
- Log: `/tmp/Kickoff-cleanup.log`

## Install

Requirements: macOS 13 or later, [VS Code](https://code.visualstudio.com), and the Xcode Command Line Tools (run `xcode-select --install` if `swiftc` isn't found).

```bash
git clone https://github.com/QingyaoAi/Kickoff.git
cd Kickoff
./install.sh     # build → ~/Applications/Kickoff.app, load the 05:00 cleanup job, launch the app
```

To update, pull and run `./install.sh` again. To remove everything, run `./uninstall.sh`. It deletes the app, the cleanup job and the settings, and keeps your task folders.

To start the app at login, turn on **Launch at Login** in the menu.

## Changing the shortcut

Choose **Set Shortcut…** in the menu, press the new combination and click **Save**. The change takes effect immediately and is kept after restarts.
- Allowed: ⌘, ⌥ or ⌃ with any key; ⇧ with a key that doesn't type a character (Space, Tab, Return, an arrow); or an F-key alone. ⇧ with a letter, digit or symbol is refused, because you could no longer type that character.
- While you hold modifiers, the recorder shows them (e.g. `⌃⌥…`). If they appear but the full combination doesn't, macOS or another app is intercepting it.
- Kickoff refuses a combination that macOS already uses (for example ⌘Space for Spotlight or ⌃Space for switching input sources). It also refuses one that another app has reserved exclusively.
- For a plain ⌘, ⌘⇧ or ⇧ shortcut (e.g. ⌘J, ⇧Space), Kickoff asks you to confirm first, because it would take that shortcut over in every app.
- **Reset to ⌃⌥⌘T** restores the default.
- Some apps claim shortcuts in a way macOS can't detect. If your shortcut does nothing, choose another one.
- If another app holds your shortcut when Kickoff starts, the menu shows *Set Shortcut… (… is taken by another app)*.

## License

MIT
