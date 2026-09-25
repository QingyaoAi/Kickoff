// Kickoff — menu bar app that creates a task folder and opens it in VS Code.
//
//   Kickoff                       run as menu bar app (default hotkey ⌃⌥⌘T, changeable in the menu)
//   Kickoff --cleanup             move stale temp folders to the Trash (run by launchd at 05:00)

import Cocoa
import Carbon.HIToolbox
import ServiceManagement

let tempPrefix = "tmp-"
let baseDirKey = "BaseDirectory"
let vscodeBundleID = "com.microsoft.VSCode"

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

    static let `default` = Shortcut(keyCode: kVK_ANSI_T, modifiers: controlKey | optionKey | cmdKey)

    static var saved: Shortcut {
        let d = UserDefaults.standard
        guard d.object(forKey: "HotKeyCode") != nil else { return .default }
        return Shortcut(keyCode: d.integer(forKey: "HotKeyCode"), modifiers: d.integer(forKey: "HotKeyModifiers"))
    }

    func save() {
        UserDefaults.standard.set(keyCode, forKey: "HotKeyCode")
        UserDefaults.standard.set(modifiers, forKey: "HotKeyModifiers")
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
    private static var action: (() -> Void)?

    init(action: @escaping () -> Void) {
        HotKey.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.action?() }
            return noErr
        }, 1, &spec, nil, nil)
    }

    /// Registers exclusively, so it fails if another app holds the combination exclusively.
    /// (Apps registering non-exclusively can't be detected by any public API.)
    func register(_ shortcut: Shortcut) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x4B43_4B31), id: 1) // 'KCK1'
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), UInt32(shortcut.modifiers), id,
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
        if status != noErr { ref = nil }
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}

// MARK: - App

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey!
    private var hotKeyActive = false
    private var newTaskItem: NSMenuItem!
    private var shortcutItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var baseItem: NSMenuItem!

    func applicationDidFinishLaunching(_ note: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: "Kickoff")

        let menu = NSMenu()
        newTaskItem = menu.addItem(withTitle: "New Task…", action: #selector(newTask), keyEquivalent: "")
        menu.addItem(.separator())
        baseItem = menu.addItem(withTitle: "", action: #selector(revealBase), keyEquivalent: "")
        menu.addItem(withTitle: "Choose Agent Folder…", action: #selector(chooseBase), keyEquivalent: "")
        shortcutItem = menu.addItem(withTitle: "", action: #selector(setShortcut), keyEquivalent: "")
        menu.addItem(withTitle: "Trash All Temp Folders Now", action: #selector(cleanupNow), keyEquivalent: "")
        loginItem = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.delegate = self
        statusItem.menu = menu

        hotKey = HotKey { [weak self] in self?.newTask() }
        hotKeyActive = hotKey.register(.saved)
    }

    @objc func newTask() {
        guard let base = baseDirectory() ?? promptForBase() else { return }

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSImage(systemSymbolName: "folder.badge.plus", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 48, weight: .regular))
        alert.messageText = "Kickoff a New Task"
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
            openInVSCode(folder)
        } catch {
            NSAlert(error: error).runModal()
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

    @objc func chooseBase() { _ = promptForBase() }

    @objc func revealBase() {
        if let base = baseDirectory() { NSWorkspace.shared.open(base) }
    }

    @objc func setShortcut() {
        let current = Shortcut.saved
        hotKey.unregister() // so pressing the current combination records it instead of firing
        hotKeyActive = false

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 48, weight: .regular))
        alert.messageText = "Set Shortcut"
        alert.informativeText = """
            Press the new key combination: ⌘, ⌥ or ⌃ with any key, ⇧ with Space, Tab or an arrow, or an F-key alone.

            If the modifiers appear below but the full combination doesn't, macOS or another app \
            already uses it. Try a different one.
            """
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Reset to \(Shortcut.default.display)")
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
        case .alertFirstButtonReturn: apply(candidate, previous: current)
        case .alertThirdButtonReturn: apply(.default, previous: current)
        default: hotKeyActive = hotKey.register(current)
        }
    }

    /// Validates and registers `shortcut`; on a problem, explains it and reopens the recorder.
    private func apply(_ shortcut: Shortcut, previous: Shortcut) {
        func reject(_ message: String) {
            let alert = NSAlert()
            alert.messageText = "\(shortcut.display) can't be used"
            alert.informativeText = message
            alert.runModal()
            hotKeyActive = hotKey.register(previous)
            setShortcut()
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
                    hotKeyActive = hotKey.register(previous)
                    return setShortcut()
                }
            }
        }
        guard hotKey.register(shortcut) else {
            return reject("Another app has reserved it. Pick another one.")
        }
        hotKeyActive = true
        shortcut.save()
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
        baseItem.title = "Folder: " + (baseDirectory().map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "(not set)")
        baseItem.isEnabled = baseDirectory() != nil
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off

        let shortcut = Shortcut.saved
        newTaskItem.keyEquivalent = hotKeyActive ? shortcut.menuEquivalent : ""
        newTaskItem.keyEquivalentModifierMask = shortcut.cocoaModifiers
        shortcutItem.title = hotKeyActive ? "Set Shortcut…" : "Set Shortcut… (\(shortcut.display) is taken by another app)"
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
