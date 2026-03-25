import AppKit
import Carbon.HIToolbox

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Privacy Shield")
    private let subtitleLabel = NSTextField(labelWithString: "Screen hidden. Press Return or click to unlock.")

    var onUnlockRequest: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor

        titleLabel.font = .systemFont(ofSize: 34, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.alignment = .center

        subtitleLabel.font = .systemFont(ofSize: 16, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        subtitleLabel.alignment = .center

        [titleLabel, subtitleLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -18),
            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        onUnlockRequest?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Return) || event.keyCode == UInt16(kVK_ANSI_KeypadEnter) {
            onUnlockRequest?()
            return
        }
        super.keyDown(with: event)
    }
}

final class ShieldController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let pinDefaultsKey = "PrivacyShieldPIN"
    private let defaultPin = "2468"
    private var statusItem: NSStatusItem!
    private var windows: [OverlayWindow] = []
    private var isShieldVisible = false
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ensureDefaultPIN()
        configureStatusItem()
        configureHotKey()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }

    private func ensureDefaultPIN() {
        let defaults = UserDefaults.standard
        if defaults.string(forKey: pinDefaultsKey) == nil {
            defaults.set(defaultPin, forKey: pinDefaultsKey)
        }
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Shield"

        let menu = NSMenu()
        menu.addItem(withTitle: "Activate Shield", action: #selector(toggleShieldFromMenu), keyEquivalent: "")
        menu.addItem(withTitle: "Set PIN", action: #selector(promptForPINChange), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
    }

    private func configureHotKey() {
        var hotKeyID = EventHotKeyID(signature: OSType(0x50534844), id: UInt32(1))
        let modifiers = UInt32(controlKey | cmdKey)
        let keyCode = UInt32(kVK_ANSI_L)
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)

        guard registerStatus == noErr else {
            NSLog("Failed to register global hotkey: \(registerStatus)")
            return
        }

        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData in
                guard let userData, let eventRef else { return noErr }
                let controller = Unmanaged<ShieldController>.fromOpaque(userData).takeUnretainedValue()
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                if status == noErr, hotKeyID.id == 1 {
                    controller.toggleShield()
                }
                return noErr
            },
            1,
            &eventSpec,
            UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque()),
            &eventHandlerRef
        )
    }

    @objc
    private func toggleShieldFromMenu() {
        toggleShield()
    }

    private func toggleShield() {
        isShieldVisible ? requestUnlock() : showShield()
    }

    private func showShield() {
        guard !isShieldVisible else { return }

        isShieldVisible = true
        rebuildWindows()

        NSApp.activate(ignoringOtherApps: true)
        windows.forEach { window in
            window.orderFrontRegardless()
            window.makeKey()
        }
    }

    private func hideShield() {
        isShieldVisible = false
        windows.forEach { $0.orderOut(nil) }
    }

    private func rebuildWindows() {
        windows.forEach { $0.close() }
        windows.removeAll()

        for screen in NSScreen.screens {
            let window = OverlayWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.level = .screenSaver
            window.backgroundColor = .black
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isMovable = false
            window.hidesOnDeactivate = false
            window.delegate = self

            let overlayView = OverlayView(frame: screen.frame)
            overlayView.onUnlockRequest = { [weak self] in
                self?.requestUnlock()
            }
            window.contentView = overlayView

            windows.append(window)
        }
    }

    private func requestUnlock() {
        guard isShieldVisible else { return }

        let alert = NSAlert()
        alert.messageText = "Unlock Privacy Shield"
        alert.informativeText = "Enter the PIN to remove the screen overlay."
        alert.alertStyle = .informational

        let pinField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        pinField.placeholderString = "PIN"
        alert.accessoryView = pinField

        alert.addButton(withTitle: "Unlock")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn, pinField.stringValue == currentPIN() {
            hideShield()
        }
    }

    @objc
    private func promptForPINChange() {
        let alert = NSAlert()
        alert.messageText = "Set Privacy Shield PIN"
        alert.informativeText = "This PIN is stored in UserDefaults for this prototype."
        alert.alertStyle = .informational

        let pinField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        pinField.placeholderString = "New PIN"
        alert.accessoryView = pinField

        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        let newPIN = pinField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newPIN.isEmpty else { return }
        UserDefaults.standard.set(newPIN, forKey: pinDefaultsKey)
    }

    private func currentPIN() -> String {
        UserDefaults.standard.string(forKey: pinDefaultsKey) ?? defaultPin
    }

    @objc
    private func quitApp() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = ShieldController()
app.delegate = delegate
app.run()
