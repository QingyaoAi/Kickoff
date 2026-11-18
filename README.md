# Kickoff

A native Swift menu bar app (universal binary for Apple Silicon and Intel, macOS 13+, no Dock icon). It creates a task folder in your agent folder and opens it in VS Code, DeepSeek Harness Desktop, or Codex.

## Usage

| Default shortcut | Menu item |
| --- | --- |
| **⌃⌥⌘T** | New Task in VS Code… |
| **⌥D** | New Task in DeepSeek Harness… |
| **⌥C** | New Task in Codex… |

- Press a shortcut or select the matching item from the 📁+ menu to open the task name prompt.
- Type a task name and press Enter. The app creates `<agent folder>/<name>` and opens it. If a folder with that name already exists, the app opens it.
- Leave the name empty and press Enter. The app creates `<agent folder>/tmp-YYYYMMDD-HHmmss` and opens it.
- Press Esc to cancel.

The first time you use it, the app asks you to choose the agent folder. To change it later, use **Choose Agent Folder…** in the menu.

## Opening in desktop apps

**DeepSeek Harness** opens the native desktop app and selects the task folder as its workspace. Open DeepSeek Harness once to initialize its profile, then quit it and install the `dsh-kickoff` plugin using either installation method below. The plugin loads when DeepSeek Harness next opens.

**Codex** opens the desktop app with the task folder as its workspace using `codex app <folder>`. Kickoff uses the CLI bundled with the app when available and falls back to `codex` on your login shell's `PATH`.

## Temp folder cleanup

A launchd job runs `Kickoff --cleanup` every day at 05:00. The job moves `tmp-*` folders created before that 05:00 to the **Trash**, where you can still recover them.
- A renamed folder no longer starts with `tmp-`, so the job keeps it.
- If the Mac is asleep at 05:00, the job runs when it wakes. It still removes only the folders created before 05:00.
- **Trash All Temp Folders Now** in the menu trashes every `tmp-*` folder immediately.
- Log: `/tmp/Kickoff-cleanup.log`
- The DeepSeek Harness plugin checks for trashed `tmp-*` workspaces at startup and every hour. It archives their sessions and removes their workspace entries from the sidebar.

## Recent folders

**Recent Folders** in the menu lists the last 8 folders you opened through Kickoff, newest first. Click one to open it in VS Code. Folders that no longer exist (for example trashed temp folders) are hidden, and **Clear Menu** empties the list.

## Install

**Prebuilt (no Xcode needed)**

Download `Kickoff.zip`, unzip it, and move `Kickoff.app` to `~/Applications`. The app is ad-hoc signed, so run `xattr -cr ~/Applications/Kickoff.app` once before opening it. [Latest release](https://github.com/QingyaoAi/Kickoff/releases/latest)

To enable the DeepSeek shortcut, install the bundled plugin while DeepSeek Harness is closed.

```bash
"/Applications/DeepSeek Harness.app/Contents/Resources/runtime/cli/bin/dsh" \
  plugin --profile desktop add --offline --ignore-scripts \
  "link:$HOME/Applications/Kickoff.app/Contents/Resources/dsh-kickoff"
```

Use the source installer below to register the 05:00 cleanup job.

**From source**

Requirements are macOS 13 or later and the Xcode Command Line Tools (run `xcode-select --install` if `swiftc` isn't found). Install the desktop apps you want to open through Kickoff.

```bash
git clone https://github.com/QingyaoAi/Kickoff.git
cd Kickoff
./install.sh     # build and install Kickoff, register the 05:00 cleanup, and set up the dsh plugin
```

To update, pull and run `./install.sh` again. To remove everything, run `./uninstall.sh`. It deletes the app, the cleanup job, the settings and the dsh plugin, and keeps your task folders.

To start the app at login, turn on **Launch at Login** in the menu.

## Changing the shortcuts

Choose **Set … Shortcut…** for the destination you want, press the new combination and click **Save**. The change takes effect immediately and is kept after restarts. Each destination needs a different shortcut.
- Allowed: ⌘, ⌥ or ⌃ with any key; ⇧ with a key that doesn't type a character (Space, Tab, Return, an arrow); or an F-key alone. ⇧ with a letter, digit or symbol is refused, because you could no longer type that character.
- While you hold modifiers, the recorder shows them (e.g. `⌃⌥…`). If they appear but the full combination doesn't, macOS or another app is intercepting it.
- Kickoff refuses a combination that macOS already uses (for example ⌘Space for Spotlight or ⌃Space for switching input sources). It also refuses one that another app has reserved exclusively.
- For a plain ⌘, ⌘⇧ or ⇧ shortcut (e.g. ⌘J, ⇧Space), Kickoff asks you to confirm first, because it would take that shortcut over in every app.
- **Reset to …** restores the default shown in the dialog.
- Some apps claim shortcuts in a way macOS can't detect. If your shortcut does nothing, choose another one.
- If another app holds your shortcut when Kickoff starts, the menu shows *Set … Shortcut… (… is taken by another app)*.

## License

MIT
