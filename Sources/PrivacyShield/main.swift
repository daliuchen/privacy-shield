import AppKit
import Carbon.HIToolbox
import QuartzCore

final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class OverlayView: NSView {
    private let titleLabel = NSTextField(labelWithString: "Privacy Shield")
    private let subtitleLabel = NSTextField(labelWithString: "Screen hidden. Press Return or click to unlock.")

    // Inline PIN entry — avoids NSAlert level/modal issues entirely.
    private let pinField = NSSecureTextField()
    private let errorLabel = NSTextField(labelWithString: "Incorrect PIN")
    private let pinStack = NSStackView()

    override var acceptsFirstResponder: Bool { true }

    var onUnlockAttempt: ((String) -> Void)?
    var onForceHide: (() -> Void)?

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

        pinField.placeholderString = "Enter PIN"
        pinField.font = .systemFont(ofSize: 16)
        pinField.alignment = .center
        pinField.focusRingType = .none

        errorLabel.font = .systemFont(ofSize: 13)
        errorLabel.textColor = .systemRed
        errorLabel.alignment = .center
        errorLabel.isHidden = true

        let unlockButton = NSButton(title: "Unlock", target: self, action: #selector(attemptUnlock))
        unlockButton.keyEquivalent = "\r"
        unlockButton.bezelStyle = .rounded

        let cancelButton = NSButton(title: "Cancel", target: self, action: #selector(cancelUnlock))
        cancelButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [cancelButton, unlockButton])
        buttonRow.spacing = 12

        pinStack.orientation = .vertical
        pinStack.alignment = .centerX
        pinStack.spacing = 10
        pinStack.addArrangedSubview(pinField)
        pinStack.addArrangedSubview(errorLabel)
        pinStack.addArrangedSubview(buttonRow)
        pinStack.isHidden = true

        [titleLabel, subtitleLabel, pinStack].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }

        NSLayoutConstraint.activate([
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor, constant: -60),
            subtitleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            pinStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            pinStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 20),
            pinField.widthAnchor.constraint(equalToConstant: 220),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func showPINEntry() {
        guard pinStack.isHidden else { return }
        subtitleLabel.isHidden = true
        errorLabel.isHidden = true
        pinField.stringValue = ""
        pinStack.isHidden = false
        window?.makeFirstResponder(pinField)
    }

    func resetToIdle() {
        pinStack.isHidden = true
        subtitleLabel.isHidden = false
        pinField.stringValue = ""
        window?.makeFirstResponder(self)
    }

    func showWrongPIN() {
        errorLabel.isHidden = false
        pinField.stringValue = ""
        window?.makeFirstResponder(pinField)
    }

    @objc private func attemptUnlock() {
        onUnlockAttempt?(pinField.stringValue)
    }

    @objc private func cancelUnlock() {
        resetToIdle()
    }

    override func mouseDown(with event: NSEvent) {
        showPINEntry()
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case UInt16(kVK_Escape):
            onForceHide?()
        case UInt16(kVK_Return), UInt16(kVK_ANSI_KeypadEnter) where pinStack.isHidden:
            showPINEntry()
        default:
            super.keyDown(with: event)
        }
    }
}

final class ShieldController: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private let pinDefaultsKey = "PrivacyShieldPIN"
    private let defaultPin = "2468"

    private var statusItem: NSStatusItem!
    private var windows: [OverlayWindow] = []
    private var isShieldVisible = false
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private var needsKeyFocus = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ensureDefaultPIN()
        configureStatusItem()
        configureHotKey()
        showLaunchNotice()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenConfigurationChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Tear down overlay windows before sleep and rebuild on wake to avoid
        // use-after-free crashes in the compositor (_NSWindowTransformAnimation).
        let wsnc = NSWorkspace.shared.notificationCenter
        wsnc.addObserver(
            self,
            selector: #selector(handleWillSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(handleDidWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(handleScreensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(handleScreensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
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

    /// Draws the shield-lock icon as a template image for the menu bar.
    private func createMenuBarIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let s = rect.size.width
            ctx.translateBy(x: s / 2, y: s * 0.47)
            let scale = s / 740.0
            ctx.scaleBy(x: scale, y: scale)

            // Shield silhouette — same bezier as the app icon
            let shield = CGMutablePath()
            shield.move(to: .init(x: 0, y: 310))
            shield.addCurve(to: .init(x: 270, y: 190),
                            control1: .init(x: 150, y: 310), control2: .init(x: 270, y: 280))
            shield.addCurve(to: .init(x: 0, y: -330),
                            control1: .init(x: 270, y: -10), control2: .init(x: 90, y: -230))
            shield.addCurve(to: .init(x: -270, y: 190),
                            control1: .init(x: -90, y: -230), control2: .init(x: -270, y: -10))
            shield.addCurve(to: .init(x: 0, y: 310),
                            control1: .init(x: -270, y: 280), control2: .init(x: -150, y: 310))
            shield.closeSubpath()

            ctx.addPath(shield)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fillPath()

            // Lock cutout — clearBlendMode carves transparent shapes out of the shield
            ctx.setBlendMode(.clear)

            // Lock body
            let lockW: CGFloat = 130, lockH: CGFloat = 95
            let lockY: CGFloat = -110
            let lockRect = CGRect(x: -lockW / 2, y: lockY, width: lockW, height: lockH)
            ctx.addPath(CGPath(roundedRect: lockRect, cornerWidth: 14, cornerHeight: 14, transform: nil))
            ctx.fillPath()

            // Shackle
            let shR: CGFloat = 36
            let shBase = lockRect.maxY - 4
            ctx.setLineWidth(22)
            ctx.setLineCap(.round)
            ctx.move(to: .init(x: -shR, y: shBase))
            ctx.addLine(to: .init(x: -shR, y: shBase + 42))
            ctx.addArc(center: .init(x: 0, y: shBase + 42), radius: shR,
                       startAngle: .pi, endAngle: 0, clockwise: false)
            ctx.addLine(to: .init(x: shR, y: shBase))
            ctx.strokePath()

            return true
        }
        image.isTemplate = true
        return image
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = createMenuBarIcon()
            button.toolTip = "Privacy Shield"
        }

        let menu = NSMenu()
        menu.delegate = self
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

    private func showLaunchNotice() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            let alert = NSAlert()
            alert.messageText = "Privacy Shield Is Running"
            alert.informativeText = "The app is now running in the menu bar.\n\nUse the Shield menu or press Control + Command + L to activate the privacy overlay."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")

            NSApp.activate(ignoringOtherApps: true)
            alert.runModal()
            self.statusItem.button?.highlight(false)
        }
    }

    @objc
    private func toggleShieldFromMenu() {
        // Called synchronously from the menu item action.
        // Shield windows are at level 1000 (above menu at ~101),
        // so showing them while the menu is still on screen is fine.
        toggleShield()
    }

    private func toggleShield() {
        isShieldVisible ? requestUnlock() : showShield()
    }

    func menuDidClose(_ menu: NSMenu) {
        if !isShieldVisible {
            NSApp.setActivationPolicy(.accessory)
        }
        // If showShield() was called during menu tracking, the alpha flip
        // made the overlay visible immediately but makeKeyAndOrderFront was
        // deferred (it's a no-op during menu tracking). Execute it now.
        if needsKeyFocus {
            needsKeyFocus = false
            NSApp.activate(ignoringOtherApps: true)
            if let first = windows.first {
                first.makeKeyAndOrderFront(nil)
                first.makeFirstResponder(first.contentView)
            }
        }
    }

    private func showShield() {
        guard !isShieldVisible else { return }

        isShieldVisible = true
        NSApp.setActivationPolicy(.regular)

        // Create fresh windows each time — avoids stale window state that
        // can cause crashes on sleep/wake (the previous alphaValue=0 approach
        // left windows permanently in the compositor, triggering a
        // use-after-free in _NSWindowTransformAnimation on wake).
        rebuildWindows()

        windows.forEach { $0.orderFrontRegardless() }
        // Force compositor to present the windows RIGHT NOW, even if
        // we're inside the menu's event-tracking run-loop mode.
        CATransaction.flush()

        NSApp.activate(ignoringOtherApps: true)
        if let first = windows.first {
            first.makeKeyAndOrderFront(nil)
            first.makeFirstResponder(first.contentView)
        }
        needsKeyFocus = true
    }

    private func hideShield() {
        isShieldVisible = false
        needsKeyFocus = false
        windows.forEach { $0.orderOut(nil) }
        NSApp.setActivationPolicy(.accessory)
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
            window.hasShadow = false
            window.isOpaque = true
            window.delegate = self

            let overlayView = OverlayView(frame: NSRect(origin: .zero, size: screen.frame.size))
            overlayView.onUnlockAttempt = { [weak self, weak overlayView] pin in
                guard let self else { return }
                if pin == self.currentPIN() {
                    self.hideShield()
                } else {
                    overlayView?.showWrongPIN()
                }
            }
            overlayView.onForceHide = { [weak self] in
                self?.hideShield()
            }
            window.contentView = overlayView
            window.setFrame(screen.frame, display: true)

            windows.append(window)
        }
    }

    @objc
    private func handleScreenConfigurationChange() {
        guard isShieldVisible else { return }
        rebuildWindows()
        windows.forEach { $0.orderFrontRegardless() }
        if let first = windows.first {
            first.makeKeyAndOrderFront(nil)
            first.makeFirstResponder(first.contentView)
        }
    }

    // Sleep/wake: tear down windows before sleep, rebuild on wake.
    // This handles both system sleep AND display-only sleep (lid close,
    // screen timeout, etc.) to cover all paths that can crash the compositor.

    @objc
    private func handleWillSleep() {
        tearDownForSleep()
    }

    @objc
    private func handleDidWake() {
        rebuildAfterWake()
    }

    @objc
    private func handleScreensDidSleep() {
        tearDownForSleep()
    }

    @objc
    private func handleScreensDidWake() {
        rebuildAfterWake()
    }

    private var shieldWasVisibleBeforeSleep = false

    private func tearDownForSleep() {
        guard isShieldVisible else { return }
        shieldWasVisibleBeforeSleep = true
        windows.forEach { $0.close() }
        windows.removeAll()
    }

    private func rebuildAfterWake() {
        guard shieldWasVisibleBeforeSleep else { return }
        shieldWasVisibleBeforeSleep = false

        // Delay slightly to let the display fully initialize after wake.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self, self.isShieldVisible else { return }
            self.rebuildWindows()
            self.windows.forEach { $0.orderFrontRegardless() }
            NSApp.activate(ignoringOtherApps: true)
            if let first = self.windows.first {
                first.makeKeyAndOrderFront(nil)
                first.makeFirstResponder(first.contentView)
            }
        }
    }

    // Shows PIN entry on all overlays — used when hotkey is pressed while shield is active.
    private func requestUnlock() {
        guard isShieldVisible else { return }
        windows.forEach { ($0.contentView as? OverlayView)?.showPINEntry() }
        needsKeyFocus = true
        NSApp.activate(ignoringOtherApps: true)
        if let first = windows.first {
            first.makeKeyAndOrderFront(nil)
            first.makeFirstResponder(first.contentView)
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
