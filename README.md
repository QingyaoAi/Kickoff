# Kickoff

A native Swift menu bar app (universal binary for Apple Silicon and Intel, macOS 13+, no Dock icon). It creates a task folder in your agent folder and opens it in VS Code or in the [dsh](https://github.com/deepseek-ai/deepseek-harness) (DeepSeek Harness) web UI.

## Usage

- Press **⌃⌥⌘T** to open the task in VS Code, or **⌥D** to open it in dsh (the default shortcuts; see below to change them). You can also click the 📁+ icon in the menu bar and choose **New Task in VS Code…** or **New Task in dsh…**.
- Type a task name and press Enter. The app creates `<agent folder>/<name>` and opens it. If a folder with that name already exists, the app opens it.
- Leave the name empty and press Enter. The app creates `<agent folder>/tmp-YYYYMMDD-HHmmss` and opens it.
- Press Esc to cancel.

The first time you use it, the app asks you to choose the agent folder. To change it later, use **Choose Agent Folder…** in the menu.

## Opening in dsh

**New Task in dsh** opens `http://127.0.0.1:3080` as a Chrome app window (or in your default browser if Chrome isn't installed). In that window, the task folder is the workspace and a new session is ready.
- To give dsh its own Dock icon, install it as a Chrome app once: open `http://127.0.0.1:3080` in Chrome (exactly this address, not `localhost`), then click the install icon in the address bar, or choose ⋮ › Cast, Save and Share › Install Page as App…. Install it in the Chrome profile you normally use, because Chrome opens the app in its last-used profile. Kickoff finds the installed app and opens dsh through it from then on. Without it, the window works the same but appears in the Dock as Chrome.
- Chrome can keep at most 6 dsh pages (windows or tabs) open at once, because each page holds a connection for dsh's live plugin updates (`client-hmr`) and Chrome allows 6 connections per address. A 7th window stays blank until you close another dsh window.
- If dsh web isn't running, Kickoff starts `dsh web --no-open` through your login shell and waits for it, which can take a few seconds. The server keeps running after Kickoff quits. Log: `/tmp/Kickoff-dsh-web.log`
- A dsh web that is already running, for example one started by the VS Code extension, is used as it is.
- The **dsh-kickoff** plugin in [`dsh-plugin/`](dsh-plugin/) does the dsh side, and `./install.sh` adds it to the dsh web profile (`~/.dsh/profiles/web`). Restart dsh web once after installing it. The plugin:
  - opens the folder that Kickoff names in the URL as a workspace, the same as **Add workspace** in dsh;
  - writes the running server's sign-in URL to `~/.dsh/kickoff-web-url` (readable only by you), so the window signs in even if the browser has no dsh cookie yet;
  - removes temp workspaces from the dsh sidebar after their `tmp-*` folder has been trashed. It archives their sessions (shown again under the archived-sessions filter) and removes the workspace. It checks when dsh web starts and then every hour.

## Temp folder cleanup

A launchd job runs `Kickoff --cleanup` every day at 05:00. The job moves `tmp-*` folders created before that 05:00 to the **Trash**, where you can still recover them.
- A renamed folder no longer starts with `tmp-`, so the job keeps it.
- If the Mac is asleep at 05:00, the job runs when it wakes. It still removes only the folders created before 05:00.
- **Trash All Temp Folders Now** in the menu trashes every `tmp-*` folder immediately.
- Log: `/tmp/Kickoff-cleanup.log`

## Recent folders

**Recent Folders** in the menu lists the last 8 folders you opened through Kickoff, newest first. Click one to open it in VS Code again, or hold ⌥ and click it to open it in dsh. Folders that no longer exist (for example trashed temp folders) are hidden, and **Clear Menu** empties the list.

## Install

**Prebuilt (no Xcode needed):** download `Kickoff.zip` from the [latest release](https://github.com/QingyaoAi/Kickoff/releases/latest), unzip it and move `Kickoff.app` to `~/Applications`. The app isn't notarized, so run `xattr -cr ~/Applications/Kickoff.app` once before opening it. The prebuilt app doesn't include the 05:00 cleanup job or the dsh plugin; use the build-from-source steps below for those.

**From source:**

Requirements: macOS 13 or later, [VS Code](https://code.visualstudio.com), and the Xcode Command Line Tools (run `xcode-select --install` if `swiftc` isn't found). For **New Task in dsh** you also need [dsh](https://github.com/deepseek-ai/deepseek-harness), with `dsh web` run at least once so its web profile exists.

```bash
git clone https://github.com/QingyaoAi/Kickoff.git
cd Kickoff
./install.sh     # build → ~/Applications/Kickoff.app, load the 05:00 cleanup job, add the dsh plugin, launch the app
```

To update, pull and run `./install.sh` again. To remove everything, run `./uninstall.sh`. It deletes the app, the cleanup job, the settings and the dsh plugin, and keeps your task folders.

To start the app at login, turn on **Launch at Login** in the menu.

## Changing the shortcuts

Choose **Set VS Code Shortcut…** or **Set dsh Shortcut…** in the menu, press the new combination and click **Save**. The change takes effect immediately and is kept after restarts. The two shortcuts must be different.
- Allowed: ⌘, ⌥ or ⌃ with any key; ⇧ with a key that doesn't type a character (Space, Tab, Return, an arrow); or an F-key alone. ⇧ with a letter, digit or symbol is refused, because you could no longer type that character.
- While you hold modifiers, the recorder shows them (e.g. `⌃⌥…`). If they appear but the full combination doesn't, macOS or another app is intercepting it.
- Kickoff refuses a combination that macOS already uses (for example ⌘Space for Spotlight or ⌃Space for switching input sources). It also refuses one that another app has reserved exclusively.
- For a plain ⌘, ⌘⇧ or ⇧ shortcut (e.g. ⌘J, ⇧Space), Kickoff asks you to confirm first, because it would take that shortcut over in every app.
- **Reset to ⌃⌥⌘T** (VS Code) or **Reset to ⌥D** (dsh) restores the default.
- Some apps claim shortcuts in a way macOS can't detect. If your shortcut does nothing, choose another one.
- If another app holds your shortcut when Kickoff starts, the menu shows *Set … Shortcut… (… is taken by another app)*.

## License

MIT
