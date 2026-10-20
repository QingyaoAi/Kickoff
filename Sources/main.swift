// Kickoff — menu bar app that creates a task folder and opens it in VS Code or in dsh web.
//
//   Kickoff                       run as menu bar app (default hotkeys ⌃⌥⌘T for VS Code, ⌥D for dsh;
//                                 changeable in the menu)
//   Kickoff --cleanup             move stale temp folders to the Trash (run by launchd at 05:00)

import Cocoa
import Carbon.HIToolbox
import ServiceManagement

let tempPrefix = "tmp-"
let baseDirKey = "BaseDirectory"
let vscodeBundleID = "com.microsoft.VSCode"
let chromeBundleID = "com.google.Chrome"
let recentKey = "RecentFolders"
let recentLimit = 8

/// Where a task folder opens. Each target has its own global shortcut.
enum Opener: UInt32, CaseIterable {
    case vscode = 1, dsh = 2 // also the Carbon hot key id

    var name: String { self == .vscode ? "VS Code" : "dsh" }

    var defaultShortcut: Shortcut {
        switch self {
        case .vscode: return Shortcut(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey | cmdKey)
        case .dsh: return Shortcut(keyCode: kVK_ANSI_D, modifiers: optionKey)
        }
    }

    /// UserDefaults key prefix; VS Code keeps the keys it had before dsh support.
    var defaultsPrefix: String { self == .vscode ? "HotKey" : "DshHotKey" }
}

/// Recently opened folders, newest first; entries that no longer exist are dropped.
func recentFolders() -> [URL] {
    let paths = UserDefaults.standard.stringArray(forKey: recentKey) ?? []
    return paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        .filter { FileManager.default.fileExists(atPath: $0.path) }
}

func rememberRecent(_ folder: URL) {
    var paths = (UserDefaults.standard.stringArray(forKey: recentKey) ?? []).filter { $0 != folder.path }
    paths.insert(folder.path, at: 0)
    UserDefaults.standard.set(Array(paths.prefix(recentLimit)), forKey: recentKey)
}

// MARK: - Folder logic (shared by app and cleanup mode)

func baseDirectory() -> URL? {
    guard let path = UserDefaults.standard.string(forKey: baseDirKey) else { return nil }
    return URL(fileURLWithPath: path, isDirectory: true)
}

/// Turns user input into a safe single path component.
func sanitize(_ name: String) -> String {
    var s = name.trimmingCharacters(in: .whitespacesAndNewlines)
    s = s.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    while s.hasPrefix(".") { s.removeFirst() }
    return s
}

/// Creates (or reuses) the folder for `taskName`; an empty name yields a new temp folder.
func makeTaskFolder(in base: URL, taskName: String) throws -> URL {
    let name = sanitize(taskName)
    let folderName: String
    if name.isEmpty {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        folderName = tempPrefix + f.string(from: Date())
    } else {
        folderName = name
    }
    let url = base.appendingPathComponent(folderName, isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Trashes temp folders. By default only those created before the most recent 05:00,
/// so a folder made after 5am survives even if the job runs late (e.g. Mac was asleep).
/// Renamed folders no longer match the prefix and are kept.
func cleanupTempFolders(all: Bool = false) {
    guard let base = baseDirectory() else { return }
    let cal = Calendar.current
    let now = Date()
    var cutoff = cal.date(bySettingHour: 5, minute: 0, second: 0, of: now)!
    if cutoff > now { cutoff = cal.date(byAdding: .day, value: -1, to: cutoff)! }
    if all { cutoff = .distantFuture }

    let fm = FileManager.default
    let items = (try? fm.contentsOfDirectory(at: base, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey])) ?? []
    for url in items where url.lastPathComponent.hasPrefix(tempPrefix) {
        guard let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey]),
              v.isDirectory == true,
              let created = v.creationDate, created < cutoff else { continue }
        do {
            try fm.trashItem(at: url, resultingItemURL: nil)
            print("Trashed \(url.path)")
        } catch {
            print("Failed to trash \(url.path): \(error)")
        }
    }
}

// MARK: - Global hotkey (Carbon; needs no Accessibility permission)

let modifierMask = cmdKey | shiftKey | optionKey | controlKey

/// Keys whose name/menu glyph can't come from the keyboard layout.
let specialKeys: [Int: (name: String, equivalent: String)] = {
    var t: [Int: (String, String)] = [
        kVK_Space: ("Space", " "), kVK_Return: ("↩", "\r"), kVK_Tab: ("⇥", "\t"),
        kVK_Delete: ("⌫", "\u{8}"), kVK_Escape: ("⎋", "\u{1b}"),
        kVK_LeftArrow: ("←", String(UnicodeScalar(NSLeftArrowFunctionKey)!)),
        kVK_RightArrow: ("→", String(UnicodeScalar(NSRightArrowFunctionKey)!)),
        kVK_UpArrow: ("↑", String(UnicodeScalar(NSUpArrowFunctionKey)!)),
        kVK_DownArrow: ("↓", String(UnicodeScalar(NSDownArrowFunctionKey)!)),
    ]
    let fKeys = [kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
                 kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19]
    for (i, code) in fKeys.enumerated() {
        t[code] = ("F\(i + 1)", String(UnicodeScalar(NSF1FunctionKey + i)!))
    }
    return t
}()

/// A key combination; `modifiers` uses Carbon flags (cmdKey, optionKey, …).
struct Shortcut: Equatable {
    var keyCode: Int
    var modifiers: Int

    static func saved(for opener: Opener) -> Shortcut {
        let d = UserDefaults.standard
        let key = opener.defaultsPrefix
        guard d.object(forKey: key + "Code") != nil else { return opener.defaultShortcut }
        return Shortcut(keyCode: d.integer(forKey: key + "Code"), modifiers: d.integer(forKey: key + "Modifiers"))
    }

    func save(for opener: Opener) {
        UserDefaults.standard.set(keyCode, forKey: opener.defaultsPrefix + "Code")
        UserDefaults.standard.set(modifiers, forKey: opener.defaultsPrefix + "Modifiers")
    }

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers & modifierMask
    }

    init(event: NSEvent) {
        let f = event.modifierFlags
        var m = 0
        if f.contains(.control) { m |= controlKey }
        if f.contains(.option) { m |= optionKey }
        if f.contains(.shift) { m |= shiftKey }
        if f.contains(.command) { m |= cmdKey }
        self.init(keyCode: Int(event.keyCode), modifiers: m)
    }

    var isFunctionKey: Bool { specialKeys[keyCode]?.name.hasPrefix("F") == true }

    /// Space, Tab, arrows, F-keys… as opposed to letters, digits and punctuation.
    var isNonTypingKey: Bool { specialKeys[keyCode] != nil }

    /// Must not swallow normal typing: needs ⌘, ⌥ or ⌃; or ⇧ with a non-typing key (⇧Space);
    /// or an F-key alone. ⇧ + letter would make that capital letter impossible to type.
    var isUsable: Bool {
        modifiers & (cmdKey | optionKey | controlKey) != 0 || isFunctionKey
            || (modifiers == shiftKey && isNonTypingKey)
    }

    /// Why the user should confirm first, if this would take over something common in other apps.
    var takeoverWarning: String? {
        if modifiers == cmdKey || modifiers == cmdKey | shiftKey {
            return "Most apps use ⌘ and ⌘⇧ shortcuts. Kickoff would take over \(display) in every app."
        }
        if modifiers == shiftKey {
            return "\(display) is also used while typing (for example, some input methods and browsers use it). Kickoff would take it over in every app."
        }
        return nil
    }

    var cocoaModifiers: NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if modifiers & controlKey != 0 { f.insert(.control) }
        if modifiers & optionKey != 0 { f.insert(.option) }
        if modifiers & shiftKey != 0 { f.insert(.shift) }
        if modifiers & cmdKey != 0 { f.insert(.command) }
        return f
    }

    var keyName: String {
        if let special = specialKeys[keyCode] { return special.name }
        return layoutCharacter?.uppercased() ?? "Key \(keyCode)"
    }

    /// For NSMenuItem.keyEquivalent (shown in the menu).
    var menuEquivalent: String {
        if let special = specialKeys[keyCode] { return special.equivalent }
        return layoutCharacter?.lowercased() ?? ""
    }

    var modifierSymbols: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s
    }

    var display: String { modifierSymbols + keyName }

    /// The character this key types on the current ASCII-capable layout (works while a Chinese IME is active).
    private var layoutCharacter: String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { raw in
            UCKeyTranslate(raw.bindMemory(to: UCKeyboardLayout.self).baseAddress!, UInt16(keyCode),
                           UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                           OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        let s = String(utf16CodeUnits: chars, count: length).trimmingCharacters(in: .whitespacesAndNewlines)
        return s.isEmpty ? nil : s
    }

    /// True if an enabled macOS shortcut (Spotlight, Mission Control, input source, …) uses this combination.
    var isSystemShortcut: Bool {
        var list: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&list) == noErr,
              let items = list?.takeRetainedValue() as? [[String: Any]] else { return false }
        return items.contains { item in
            (item[kHISymbolicHotKeyEnabled as String] as? Bool) == true &&
            (item[kHISymbolicHotKeyCode as String] as? Int) == keyCode &&
            // keep the fn/🌐 bit so e.g. fn-A (a system shortcut) doesn't match plain A
            ((item[kHISymbolicHotKeyModifiers as String] as? Int) ?? -1) & (modifierMask | Int(kEventKeyModifierFnMask)) == modifiers
        }
    }
}

final class HotKey {
    private var ref: EventHotKeyRef?
    private let id: UInt32
    private static var actions: [UInt32: () -> Void] = [:]

    /// One handler serves every HotKey and dispatches on the hot key id.
    private static let handler: Void = {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKey.actions[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }()

    init(id: UInt32, action: @escaping () -> Void) {
        self.id = id
        HotKey.actions[id] = action
        _ = HotKey.handler
    }

    /// Registers exclusively, so it fails if another app holds the combination exclusively.
    /// (Apps registering non-exclusively can't be detected by any public API.)
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4B43_4B31), id: id) // 'KCK1'
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), hotKeyID,
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        if status != noErr { ref = nil }
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}

// MARK: - dsh web

/// The user's login shell, so `dsh` and `node` resolve as they do in Terminal.
func loginShell() -> String {
    if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell { return String(cString: shell) }
    return "/bin/zsh"
}

/// True if something accepts TCP connections at the URL's host and port.
func isListening(_ url: URL) -> Bool {
    guard let host = url.host, let port = url.port else { return false }
    var hints = addrinfo()
    hints.ai_socktype = SOCK_STREAM
    var list: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, String(port), &hints, &list) == 0, let first = list else { return false }
    defer { freeaddrinfo(first) }
    for info in sequence(first: first, next: { $0.pointee.ai_next }) {
        let fd = socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { continue }
        defer { close(fd) }
        if connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 { return true }
    }
    return false
}

/// The app id of dsh web installed as a Chrome app (PWA), from the app shim Chrome keeps in
/// ~/Applications/Chrome Apps.localized. A window launched through the app gets its own Dock icon;
/// a plain `--app=` window is part of Chrome and doesn't. (Chrome's own data folder, which would
/// say which profile has the app, is off limits to other apps, so Chrome picks its last-used profile.)
func installedChromeAppID(for url: URL) -> String? {
    let shims = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications/Chrome Apps.localized")
    for shim in (try? FileManager.default.contentsOfDirectory(at: shims, includingPropertiesForKeys: nil)) ?? []
    where shim.pathExtension == "app" {
        guard let info = NSDictionary(contentsOf: shim.appendingPathComponent("Contents/Info.plist")),
              info["CrBundleIdentifier"] as? String == chromeBundleID,
              let id = info["CrAppModeShortcutID"] as? String,
              let start = (info["CrAppModeShortcutURL"] as? String).flatMap(URL.init(string:)),
              start.host == url.host, start.port == url.port else { continue }
        return id
    }
    return nil
}

/// Opens task folders in the dsh (DeepSeek Harness) web UI, in a Chrome app window when Chrome is
/// installed, and starts `dsh web` first if nothing is listening. The page URL carries the folder
/// in its fragment; the dsh-kickoff plugin (dsh-plugin/) registers it as a workspace and opens it.
final class DshLauncher {
    static let webURL = URL(string: "http://127.0.0.1:3080/")!
    static let logPath = "/tmp/Kickoff-dsh-web.log"
    static let startTimeout: TimeInterval = 90
    /// Written by the plugin while dsh web runs: the server's URL with its launch token.
    static let signInURLFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".dsh/kickoff-web-url")

    /// Unreserved ASCII and "/"; the plugin's URLSearchParams decodes everything else.
    private static let fragmentSafe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~/")

    /// Folders waiting while the server is checked or started; empty when neither is in progress.
    private var pending: [URL] = []

    func open(_ folder: URL) {
        pending.append(folder)
        guard pending.count == 1 else { return }
        DispatchQueue.global().async {
            let up = isListening(DshLauncher.webURL)
            DispatchQueue.main.async { up ? self.showPending(at: self.runningURL()) : self.startServer() }
        }
    }

    /// The running server's sign-in URL when the plugin published one, so a browser without a
    /// dsh cookie still gets in; otherwise the plain URL.
    private func runningURL() -> URL {
        guard let text = try? String(contentsOf: DshLauncher.signInURLFile, encoding: .utf8),
              let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              url.host == DshLauncher.webURL.host, url.port == DshLauncher.webURL.port else { return DshLauncher.webURL }
        return url
    }

    private func showPending(at base: URL) {
        for folder in pending { show(folder, at: base) }
        pending = []
    }

    private func show(_ folder: URL, at base: URL) {
        var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
        components.percentEncodedFragment = "kickoff-open="
            + folder.path.addingPercentEncoding(withAllowedCharacters: DshLauncher.fragmentSafe)!
        let page = components.url!
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: chromeBundleID) else {
            NSWorkspace.shared.open(page)
            return
        }
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true // like `open -n`, so a running Chrome gets the arguments
        if let appID = installedChromeAppID(for: base) {
            config.arguments = ["--app-id=" + appID, "--app-launch-url-for-shortcuts-menu-item=" + page.absoluteString]
        } else {
            config.arguments = ["--app=" + page.absoluteString]
        }
        NSWorkspace.shared.openApplication(at: chrome, configuration: config)
    }

    /// Runs `dsh web --no-open` through a login shell and waits for its "dsh web: <url>" line.
    /// That URL carries a launch token that signs the browser in. Output goes to a file rather
    /// than a pipe, so the server keeps running after Kickoff quits.
    private func startServer() {
        FileManager.default.createFile(atPath: DshLauncher.logPath, contents: nil)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: loginShell())
        process.arguments = ["-l", "-c", "exec dsh web --no-open"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle(forWritingAtPath: DshLauncher.logPath)
        process.standardError = process.standardOutput
        do {
            try process.run()
        } catch {
            return fail(error.localizedDescription)
        }

        let deadline = Date().addingTimeInterval(DshLauncher.startTimeout)
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if let url = self.announcedURL() {
                timer.invalidate()
                self.showPending(at: url)
            } else if !process.isRunning {
                timer.invalidate()
                // Another dsh web (e.g. VS Code's) may have taken the port in the meantime.
                if isListening(DshLauncher.webURL) { self.showPending(at: self.runningURL()) }
                else { self.fail("dsh web quit while starting.") }
            } else if Date() > deadline {
                timer.invalidate()
                self.fail("dsh web didn't start within \(Int(DshLauncher.startTimeout)) seconds.")
            }
        }
    }

    private func announcedURL() -> URL? {
        guard let data = FileManager.default.contents(atPath: DshLauncher.logPath) else { return nil }
        let prefix = "dsh web: http"
        for line in String(decoding: data, as: UTF8.self).split(whereSeparator: \.isNewline) where line.hasPrefix(prefix) {
            return URL(string: line.dropFirst("dsh web: ".count).trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private func fail(_ message: String) {
        pending = []
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Couldn't open dsh"
        alert.informativeText = "\(message)\n\nLog: \(DshLauncher.logPath)"
        alert.runModal()
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKeys: [Opener: HotKey] = [:]
    private var hotKeyActive: [Opener: Bool] = [:]
    private var newTaskItems: [Opener: NSMenuItem] = [:]
    private var shortcutItems: [Opener: NSMenuItem] = [:]
    private var loginItem: NSMenuItem!
    private var baseItem: NSMenuItem!
    private var recentItem: NSMenuItem!
    private let dsh = DshLauncher()

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Kickoff")

        let menu = NSMenu()
        for opener in Opener.allCases {
            let item = menu.addItem(withTitle: "New Task in \(opener.name)…", action: #selector(newTaskFromMenu(_:)), keyEquivalent: "")
            item.tag = Int(opener.rawValue)
            newTaskItems[opener] = item
        }
        recentItem = menu.addItem(withTitle: "Recent Folders", action: nil, keyEquivalent: "")
        recentItem.submenu = NSMenu()
        menu.addItem(.separator())
        baseItem = menu.addItem(withTitle: "", action: #selector(revealBase), keyEquivalent: "")
        menu.addItem(withTitle: "Choose Agent Folder…", action: #selector(chooseBase), keyEquivalent: "")
        for opener in Opener.allCases {
            let item = menu.addItem(withTitle: "", action: #selector(setShortcutFromMenu(_:)), keyEquivalent: "")
            item.tag = Int(opener.rawValue)
            shortcutItems[opener] = item
        }
        menu.addItem(withTitle: "Trash All Temp Folders Now", action: #selector(cleanupNow), keyEquivalent: "")
        loginItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu

        for opener in Opener.allCases {
            hotKeys[opener] = HotKey(id: opener.rawValue) { [weak self] in self?.newTask(opener) }
        }
        resumeHotKeys()
    }

    /// Registers every shortcut that isn't registered, from the saved settings.
    private func resumeHotKeys() {
        for opener in Opener.allCases where hotKeyActive[opener] != true {
            hotKeyActive[opener] = hotKeys[opener]!.register(.saved(for: opener))
        }
    }

    @objc func newTaskFromMenu(_ sender: NSMenuItem) { newTask(Opener(rawValue: UInt32(sender.tag))!) }

    func newTask(_ opener: Opener) {
        guard let base = baseDirectory() ?? promptForBase() else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 48, weight: .regular))
        alert.messageText = "Kickoff a New Task in \(opener.name)"
        alert.informativeText = "Task name (leave empty for a temp folder, removed at 5:00 AM unless renamed):"
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.placeholderString = "e.g. paper-rebuttal"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            let folder = try makeTaskFolder(in: base, taskName: field.stringValue)
            open(folder, in: opener)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func open(_ folder: URL, in opener: Opener) {
        rememberRecent(folder)
        switch opener {
        case .vscode: openInVSCode(folder)
        case .dsh: dsh.open(folder)
        }
    }

    private func openInVSCode(_ folder: URL) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: vscodeBundleID) else {
            NSWorkspace.shared.activateFileViewerSelecting([folder])
            return
        }
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    private func promptForBase() -> URL? {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.message = "Choose the folder where agent task folders are created"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use This Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        UserDefaults.standard.set(url.path, forKey: baseDirKey)
        return url
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        if let url = sender.representedObject as? URL { open(url, in: Opener(rawValue: UInt32(sender.tag))!) }
    }

    @objc func clearRecent() { UserDefaults.standard.removeObject(forKey: recentKey) }

    private func refreshRecentMenu() {
        let sub = recentItem.submenu!
        sub.removeAllItems()
        let recents = recentFolders()
        recentItem.isEnabled = !recents.isEmpty
        for url in recents {
            // Click opens in VS Code; holding ⌥ swaps in the dsh item.
            for opener in Opener.allCases {
                let item = sub.addItem(withTitle: url.lastPathComponent, action: #selector(openRecent(_:)), keyEquivalent: "")
                item.representedObject = url
                item.tag = Int(opener.rawValue)
                item.toolTip = (url.path as NSString).abbreviatingWithTildeInPath
                item.keyEquivalentModifierMask = []
                if opener == .dsh {
                    item.title += " — dsh"
                    item.keyEquivalentModifierMask = .option
                    item.isAlternate = true
                }
            }
        }
        if !recents.isEmpty {
            sub.addItem(.separator())
            sub.addItem(withTitle: "Clear Menu", action: #selector(clearRecent), keyEquivalent: "")
        }
    }

    @objc func chooseBase() { _ = promptForBase() }

    @objc func revealBase() {
        if let base = baseDirectory() { NSWorkspace.shared.open(base) }
    }

    @objc func setShortcutFromMenu(_ sender: NSMenuItem) { setShortcut(Opener(rawValue: UInt32(sender.tag))!) }

    func setShortcut(_ opener: Opener) {
        let current = Shortcut.saved(for: opener)
        // Pause every shortcut, so pressing one records it instead of firing it.
        hotKeys.values.forEach { $0.unregister() }
        hotKeyActive.removeAll()
        defer { resumeHotKeys() }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 48, weight: .regular))
        alert.messageText = "Set Shortcut for New Task in \(opener.name)"
        alert.informativeText = """
            Press the new key combination: ⌘, ⌥ or ⌃ with any key, ⇧ with Space, Tab or an arrow, or an F-key alone.

            If the modifiers appear below but the full combination doesn't, macOS or another app \
            already uses it. Try a different one.
            """
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset to \(opener.defaultShortcut.display)")
        let label = NSTextField(labelWithString: current.display)
        label.font = .systemFont(ofSize: 24, weight: .medium)
        label.alignment = .center
        label.frame = NSRect(x: 0, y: 0, width: 260, height: 34)
        alert.accessoryView = label

        var candidate = current
        var holdingModifiers = false
        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            let pressed = Shortcut(event: event)
            if event.type == .flagsChanged {
                // Live feedback while modifiers are held, so it's clear the recorder is listening.
                if pressed.modifiers != 0 {
                    label.stringValue = pressed.modifierSymbols + "…"
                    holdingModifiers = true
                } else if holdingModifiers { // released without pressing a key
                    label.stringValue = candidate.display
                    holdingModifiers = false
                }
                return event
            }
            holdingModifiers = false
            if pressed.isUsable {
                candidate = pressed
                label.stringValue = pressed.display
                return nil
            }
            // Plain Return / Esc keep working as Save / Cancel.
            if pressed.modifiers == 0 && (pressed.keyCode == kVK_Return || pressed.keyCode == kVK_Escape) { return event }
            NSSound.beep()
            label.stringValue = pressed.modifiers == shiftKey ? "⇧ + letter blocks typing" : "Add ⌘, ⌥ or ⌃"
            return nil
        }
        let response = alert.runModal()
        if let monitor { NSEvent.removeMonitor(monitor) }

        switch response {
        case .alertFirstButtonReturn: apply(candidate, previous: current, for: opener)
        case .alertThirdButtonReturn: apply(opener.defaultShortcut, previous: current, for: opener)
        default: break
        }
    }

    /// Validates and registers `shortcut`; on a problem, explains it and reopens the recorder.
    private func apply(_ shortcut: Shortcut, previous: Shortcut, for opener: Opener) {
        func reject(_ message: String) {
            let alert = NSAlert()
            alert.messageText = "\(shortcut.display) can't be used"
            alert.informativeText = message
            alert.runModal()
            setShortcut(opener)
        }

        if let other = Opener.allCases.first(where: { $0 != opener && Shortcut.saved(for: $0) == shortcut }) {
            return reject("It is already the shortcut for New Task in \(other.name).")
        }
        if shortcut != previous {
            if shortcut.isSystemShortcut {
                return reject("It is already a macOS shortcut. Pick another one, or turn that one off in System Settings › Keyboard › Keyboard Shortcuts.")
            }
            if let warning = shortcut.takeoverWarning {
                let alert = NSAlert()
                alert.messageText = "Use \(shortcut.display)?"
                alert.informativeText = warning
                alert.addButton(withTitle: "Use Anyway")
                alert.addButton(withTitle: "Choose Another")
                if alert.runModal() != .alertFirstButtonReturn {
                    return setShortcut(opener)
                }
            }
        }
        guard hotKeys[opener]!.register(shortcut) else {
            return reject("Another app has reserved it. Pick another one.")
        }
        hotKeyActive[opener] = true
        shortcut.save(for: opener)
    }

    @objc func cleanupNow() { cleanupTempFolders(all: true) }

    @objc func toggleLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusItem.menu else { return }
        refreshRecentMenu()
        baseItem.title = "Folder: " + (baseDirectory().map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "(not set)")
        baseItem.isEnabled = baseDirectory() != nil
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        for opener in Opener.allCases {
            let shortcut = Shortcut.saved(for: opener)
            let active = hotKeyActive[opener] == true
            newTaskItems[opener]!.keyEquivalent = active ? shortcut.menuEquivalent : ""
            newTaskItems[opener]!.keyEquivalentModifierMask = shortcut.cocoaModifiers
            shortcutItems[opener]!.title = "Set \(opener.name) Shortcut…"
                + (active ? "" : " (\(shortcut.display) is taken by another app)")
        }
    }
}

// MARK: - Entry point

if CommandLine.arguments.contains("--cleanup") {
    cleanupTempFolders()
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
