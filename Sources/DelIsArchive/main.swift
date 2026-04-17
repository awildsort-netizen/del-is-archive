import AppKit
import ApplicationServices
import ServiceManagement

private enum KeyCode {
    static let delete: Int64 = 51
    static let forwardDelete: Int64 = 117
}

private enum AccessibilityPermission {
    private static let fallbackBundleIdentifier = "com.awildsort.del-is-archive"

    static var isEnabled: Bool {
        AXIsProcessTrusted()
    }

    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    static func resetCurrentAppAuthorization() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = [
            "reset",
            "Accessibility",
            Bundle.main.bundleIdentifier ?? fallbackBundleIdentifier
        ]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            NSLog("Del is Archive could not reset Accessibility permission: %@", error.localizedDescription)
            return false
        }
    }
}

private enum AutomationPermission {
    private static let systemEventsBundleIdentifier = "com.apple.systemevents"

    static var isEnabled: Bool {
        authorizationStatus(askUserIfNeeded: false) == noErr
    }

    static func request() {
        _ = authorizationStatus(askUserIfNeeded: true)
    }

    private static func authorizationStatus(askUserIfNeeded: Bool) -> OSStatus {
        let target = NSAppleEventDescriptor(bundleIdentifier: systemEventsBundleIdentifier)

        return AEDeterminePermissionToAutomateTarget(
            target.aeDesc,
            typeWildCard,
            typeWildCard,
            askUserIfNeeded
        )
    }
}

private enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

private final class DelIsArchiveApp: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private static let appName = "Del is Archive"
    private static let defaultStatusTitle = "Del is Archive"
    private static let successStatusTitle = "Archive successful"
    private static let animateSuccessKey = "AnimateSuccessIcon"

    private lazy var interceptor = MailArchiveInterceptor(
        onArchiveSuccess: { [weak self] in
            self?.showArchiveSuccess()
        },
        onAutomationPermissionNeeded: { [weak self] in
            self?.showAbout()
        }
    )

    private var statusItem: NSStatusItem?
    private var aboutWindow: NSWindow?
    private var resetStatusTitleWorkItem: DispatchWorkItem?
    private var permissionPollTimer: Timer?
    private var lastRenderedPermissionSignature: String?
    private var isShowingArchiveSuccess = false
    private var lastInterceptorStartAttempt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Self.animateSuccessKey: true])
        configureStatusItem()
        observeFrontmostApplicationChanges()
        updateStatusItemVisibility()
        let didStartInterceptor = startInterceptorIfPermitted()
        if !didStartInterceptor || !isAutomationReady {
            showAbout()
        }
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        configureStatusButton(symbolName: "archivebox", fallbackTitle: Self.defaultStatusTitle, description: Self.appName)
        item.button?.target = self
        item.button?.action = #selector(showAbout)
    }

    private func observeFrontmostApplicationChanges() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(frontmostApplicationDidChange(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func frontmostApplicationDidChange(_ notification: Notification) {
        updateStatusItemVisibility()
    }

    private func updateStatusItemVisibility() {
        statusItem?.isVisible = isShowingArchiveSuccess
            || NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.mail"
    }

    @objc private func showAbout() {
        refreshPermissionState()

        let window = aboutWindow ?? makeAboutWindow()
        window.contentView = makeAboutContentView()
        aboutWindow = window
        lastRenderedPermissionSignature = permissionSignature

        NSApplication.shared.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
        startPermissionPolling()
    }

    private func makeAboutWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.appName
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }

    private func makeAboutContentView() -> NSView {
        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 420))

        let root = NSStackView()
        root.orientation = .vertical
        root.alignment = .leading
        root.spacing = 16
        root.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(root)

        root.addArrangedSubview(makeAboutHeader())
        root.addArrangedSubview(makeSeparator())
        root.addArrangedSubview(makePermissionSection())
        root.addArrangedSubview(makeSettingsSection())
        root.addArrangedSubview(makeSpacer())
        root.addArrangedSubview(makeAboutFooter())

        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            root.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            root.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18)
        ])

        return contentView
    }

    private func makeAboutHeader() -> NSView {
        let icon = NSImageView()
        icon.image = statusImage(named: "archivebox", description: Self.appName, pointSize: 30)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 30, weight: .medium)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 42),
            icon.heightAnchor.constraint(equalToConstant: 42)
        ])

        let title = NSTextField(labelWithString: Self.appName)
        title.font = NSFont.systemFont(ofSize: 22, weight: .semibold)

        let subtitle = NSTextField(wrappingLabelWithString: "Press Delete ⌫ to archive the selected message in Mail.")
        subtitle.font = NSFont.systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.maximumNumberOfLines = 2

        let text = NSStackView(views: [title, subtitle])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 3

        let header = NSStackView(views: [icon, text])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12
        return header
    }

    private func makePermissionSection() -> NSView {
        let section = NSStackView()
        section.orientation = .vertical
        section.alignment = .leading
        section.spacing = 8
        section.addArrangedSubview(makeSectionTitle("Permissions"))

        section.addArrangedSubview(makePermissionRow(
            isEnabled: isAccessibilityReady,
            enabledTitle: "Accessibility is enabled",
            disabledTitle: "Accessibility needs permission",
            enabledDetail: "Keyboard interception and focused-element checks can run.",
            disabledDetail: "Enable Accessibility so Del is Archive can listen for Delete in Mail.",
            buttonTitle: "Enable Accessibility...",
            action: #selector(requestAccessibilityPermissionFromAbout)
        ))

        section.addArrangedSubview(makePermissionRow(
            isEnabled: isAutomationReady,
            enabledTitle: "Automation is enabled",
            disabledTitle: "Automation needs permission",
            enabledDetail: "The archive AppleScript can ask System Events to click Mail's Archive command.",
            disabledDetail: "Enable Automation so Del is Archive can run Mail's Archive command.",
            buttonTitle: "Enable Automation...",
            action: #selector(requestAutomationPermissionFromAbout)
        ))

        return section
    }

    private func makePermissionRow(
        isEnabled: Bool,
        enabledTitle: String,
        disabledTitle: String,
        enabledDetail: String,
        disabledDetail: String,
        buttonTitle: String,
        action: Selector
    ) -> NSView {
        let symbolName = isEnabled ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
        let title = isEnabled ? enabledTitle : disabledTitle
        let detail = isEnabled ? enabledDetail : disabledDetail

        let icon = NSImageView()
        icon.image = statusImage(named: symbolName, description: title, pointSize: 18)
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 24),
            icon.heightAnchor.constraint(equalToConstant: 24)
        ])

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)

        let detailLabel = NSTextField(wrappingLabelWithString: detail)
        detailLabel.font = NSFont.systemFont(ofSize: 12)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.maximumNumberOfLines = 3

        let labels = NSStackView(views: [titleLabel, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        let row = NSStackView(views: [icon, labels])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 8

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.addArrangedSubview(row)

        if !isEnabled {
            let button = NSButton(title: buttonTitle, target: self, action: action)
            stack.addArrangedSubview(button)
        }

        return stack
    }

    private func makeSettingsSection() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.addArrangedSubview(makeSectionTitle("Options"))

        let loginItemCheckbox = NSButton(checkboxWithTitle: "Open at Login", target: self, action: #selector(toggleOpenAtLoginFromAbout(_:)))
        loginItemCheckbox.state = LoginItem.isEnabled ? .on : .off
        stack.addArrangedSubview(loginItemCheckbox)

        let animateCheckbox = NSButton(checkboxWithTitle: "Animate Success Icon", target: self, action: #selector(toggleSuccessAnimationFromAbout(_:)))
        animateCheckbox.state = animateSuccessIcon ? .on : .off
        stack.addArrangedSubview(animateCheckbox)

        return stack
    }

    private func makeAboutFooter() -> NSView {
        let quit = NSButton(title: "Quit", target: self, action: #selector(quitFromAbout))
        let done = NSButton(title: "Done", target: self, action: #selector(closeAbout))
        done.keyEquivalent = "\r"

        let footer = NSStackView(views: [makeSpacer(), quit, done])
        footer.orientation = .horizontal
        footer.alignment = .centerY
        footer.spacing = 8
        return footer
    }

    private func makeSectionTitle(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        return label
    }

    private func makeSeparator() -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        return separator
    }

    private func makeSpacer() -> NSView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentHuggingPriority(.defaultLow, for: .vertical)
        return spacer
    }

    @objc private func requestAccessibilityPermissionFromAbout() {
        interceptor.stop()
        lastInterceptorStartAttempt = nil
        if !AccessibilityPermission.resetCurrentAppAuthorization() {
            NSLog("Del is Archive could not reset Accessibility permission with tccutil.")
        }
        AccessibilityPermission.request()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        refreshPermissionState()
        startPermissionPolling()
    }

    @objc private func requestAutomationPermissionFromAbout() {
        AutomationPermission.request()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
        refreshPermissionState()
        startPermissionPolling()
    }

    @objc private func closeAbout() {
        aboutWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        stopPermissionPolling()
    }

    @objc private func quitFromAbout() {
        NSApplication.shared.terminate(nil)
    }

    @objc private func toggleOpenAtLoginFromAbout(_ sender: NSButton) {
        do {
            try LoginItem.setEnabled(sender.state == .on)
        } catch {
            sender.state = LoginItem.isEnabled ? .on : .off
            showLoginItemError(error)
        }
    }

    private func showLoginItemError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Could not update Open at Login."
        alert.informativeText = "Install the app with make install, then launch it from /Applications and try again.\n\n\(error.localizedDescription)"
        alert.alertStyle = .warning
        alert.runModal()
    }

    @objc private func toggleSuccessAnimationFromAbout(_ sender: NSButton) {
        UserDefaults.standard.set(sender.state == .on, forKey: Self.animateSuccessKey)
    }

    private func showArchiveSuccess() {
        resetStatusTitleWorkItem?.cancel()
        cancelSuccessAnimation()

        isShowingArchiveSuccess = true
        updateStatusItemVisibility()

        if animateSuccessIcon {
            animateThumbsUp()
        } else {
            configureSuccessStatusButton(symbolName: "hand.thumbsup.fill")
        }

        let reset = DispatchWorkItem { [weak self] in
            self?.cancelSuccessAnimation()
            self?.isShowingArchiveSuccess = false
            self?.statusItem?.length = NSStatusItem.variableLength
            self?.configureStatusButton(symbolName: "archivebox", fallbackTitle: Self.defaultStatusTitle, description: Self.appName)
            self?.updateStatusItemVisibility()
        }

        resetStatusTitleWorkItem = reset
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: reset)
    }

    private var animateSuccessIcon: Bool {
        UserDefaults.standard.bool(forKey: Self.animateSuccessKey)
    }

    private func animateThumbsUp() {
        guard let button = statusItem?.button else {
            configureSuccessStatusButton(symbolName: "hand.thumbsup.fill")
            return
        }

        button.alphaValue = 0.35
        configureSuccessStatusButton(symbolName: "hand.thumbsup.fill")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            button.animator().alphaValue = 1
        }
    }

    private func cancelSuccessAnimation() {
        statusItem?.button?.alphaValue = 1
    }

    private func configureStatusButton(symbolName: String, fallbackTitle: String, description: String) {
        configureStatusButton(symbolName: symbolName, fallbackTitle: fallbackTitle, description: description, pointSize: 15)
    }

    private func configureStatusButton(symbolName: String, fallbackTitle: String, description: String, pointSize: CGFloat) {
        guard let button = statusItem?.button else {
            return
        }

        button.font = NSFont.systemFont(ofSize: 13)

        if let image = statusImage(named: symbolName, description: description, pointSize: pointSize) {
            button.title = ""
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.title = fallbackTitle
        }
        button.needsDisplay = true
    }

    private func configureSuccessStatusButton(symbolName: String) {
        statusItem?.length = NSStatusItem.variableLength

        guard let button = statusItem?.button else {
            return
        }

        button.title = ""
        button.font = NSFont.systemFont(ofSize: 13)

        if let image = statusImage(named: symbolName, description: "Archive successful", pointSize: 15) {
            button.image = image
            button.imagePosition = .imageOnly
        } else {
            button.image = nil
            button.title = Self.successStatusTitle
        }

        button.needsDisplay = true
    }

    private func statusImage(named symbolName: String, description: String, pointSize: CGFloat) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .regular)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: description)?
            .withSymbolConfiguration(configuration)
        image?.isTemplate = true
        return image
    }

    private func startInterceptorIfPermitted() -> Bool {
        guard shouldAttemptInterceptorStart else {
            return false
        }

        lastInterceptorStartAttempt = Date()
        return interceptor.start()
    }

    private func refreshPermissionState() {
        _ = startInterceptorIfPermitted()

        let signature = permissionSignature
        guard lastRenderedPermissionSignature != signature else {
            return
        }

        lastRenderedPermissionSignature = signature
        aboutWindow?.contentView = makeAboutContentView()
    }

    private func startPermissionPolling() {
        guard permissionPollTimer == nil else {
            return
        }

        permissionPollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.refreshPermissionState()
        }
    }

    private func stopPermissionPolling() {
        permissionPollTimer?.invalidate()
        permissionPollTimer = nil
    }

    private var isAccessibilityReady: Bool {
        AccessibilityPermission.isEnabled || interceptor.isStarted
    }

    private var isAutomationReady: Bool {
        AutomationPermission.isEnabled
    }

    private var permissionSignature: String {
        "\(isAccessibilityReady)-\(isAutomationReady)"
    }

    private var shouldAttemptInterceptorStart: Bool {
        if isAccessibilityReady {
            return true
        }

        guard let lastInterceptorStartAttempt else {
            return true
        }

        return Date().timeIntervalSince(lastInterceptorStartAttempt) > 2
    }
}

private final class MailArchiveInterceptor {
    private let onArchiveSuccess: () -> Void
    private let onAutomationPermissionNeeded: () -> Void
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private(set) var isStarted = false

    init(onArchiveSuccess: @escaping () -> Void, onAutomationPermissionNeeded: @escaping () -> Void) {
        self.onArchiveSuccess = onArchiveSuccess
        self.onAutomationPermissionNeeded = onAutomationPermissionNeeded
    }

    func start() -> Bool {
        guard !isStarted else {
            return true
        }

        let keyDownMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: keyDownMask,
            callback: eventTapCallback,
            userInfo: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        ) else {
            NSLog("Del is Archive could not create keyboard event tap.")
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        CGEvent.tapEnable(tap: tap, enable: true)
        isStarted = true
        return true
    }

    fileprivate func handle(event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isPlainDelete(event) else {
            return Unmanaged.passUnretained(event)
        }

        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.mail" else {
            return Unmanaged.passUnretained(event)
        }

        let focus = MailFocus.current()
        guard focus.canArchiveWithDelete else {
            return Unmanaged.passUnretained(event)
        }

        archiveSelectedMessages()
        return nil
    }

    fileprivate func reenableTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    fileprivate func stop() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }

        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }

        runLoopSource = nil
        eventTap = nil
        isStarted = false
    }

    private func isPlainDelete(_ event: CGEvent) -> Bool {
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        guard keycode == KeyCode.delete || keycode == KeyCode.forwardDelete else {
            return false
        }

        let disallowedFlags: CGEventFlags = [
            .maskCommand,
            .maskControl,
            .maskAlternate,
            .maskShift,
            .maskSecondaryFn,
            .maskHelp
        ]

        return event.flags.intersection(disallowedFlags).isEmpty
    }

    private func archiveSelectedMessages() {
        DispatchQueue.main.async {
            let script = """
            tell application "System Events"
                tell process "Mail"
                    click menu item "Archive" of menu "Message" of menu bar 1
                end tell
            end tell
            """

            var error: NSDictionary?
            guard let appleScript = NSAppleScript(source: script) else {
                return
            }

            appleScript.executeAndReturnError(&error)
            if let error {
                NSLog("Del is Archive AppleScript error: %@", error)
                if let errorNumber = error[NSAppleScript.errorNumber] as? NSNumber,
                   errorNumber.int32Value == Int32(errAEEventNotPermitted) {
                    self.onAutomationPermissionNeeded()
                }
            } else {
                self.onArchiveSuccess()
            }
        }
    }
}

private let eventTapCallback: CGEventTapCallBack = { _, type, event, refcon in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let refcon {
            let interceptor = Unmanaged<MailArchiveInterceptor>
                .fromOpaque(refcon)
                .takeUnretainedValue()
            interceptor.reenableTap()
        }
        return Unmanaged.passUnretained(event)
    }

    guard type == .keyDown else {
        return Unmanaged.passUnretained(event)
    }

    guard let refcon else {
        return Unmanaged.passUnretained(event)
    }

    let interceptor = Unmanaged<MailArchiveInterceptor>
        .fromOpaque(refcon)
        .takeUnretainedValue()
    return interceptor.handle(event: event)
}

private struct MailFocus {
    let chain: [AXElementSnapshot]

    var canArchiveWithDelete: Bool {
        guard !chain.isEmpty else {
            return false
        }

        if chain.contains(where: \.isEditableTextContext) {
            return false
        }

        if chain.contains(where: \.isComposeOrSearchContext) {
            return false
        }

        return chain.contains(where: \.looksLikeMessageList)
    }

    static func current() -> MailFocus {
        let system = AXUIElementCreateSystemWide()
        guard let focused = system.copyAttribute(kAXFocusedUIElementAttribute) else {
            return MailFocus(chain: [])
        }

        var snapshots: [AXElementSnapshot] = []
        var visited = Set<CFHashCode>()
        var current: AXUIElement? = focused

        while let element = current, snapshots.count < 12 {
            let elementHash = CFHash(element)
            if visited.contains(elementHash) {
                break
            }
            visited.insert(elementHash)

            snapshots.append(AXElementSnapshot(element: element))
            current = element.copyAttribute(kAXParentAttribute)
        }

        return MailFocus(chain: snapshots)
    }
}

private struct AXElementSnapshot {
    let role: String
    let subrole: String
    let title: String
    let description: String
    let identifier: String
    let value: String

    init(element: AXUIElement) {
        role = element.copyString(kAXRoleAttribute)
        subrole = element.copyString(kAXSubroleAttribute)
        title = element.copyString(kAXTitleAttribute)
        description = element.copyString(kAXDescriptionAttribute)
        identifier = element.copyString(kAXIdentifierAttribute)
        value = element.copyString(kAXValueAttribute)
    }

    var isEditableTextContext: Bool {
        let roles = [
            kAXTextAreaRole,
            kAXTextFieldRole,
            kAXComboBoxRole
        ].map { $0 as String }

        return roles.contains(role)
    }

    var isComposeOrSearchContext: Bool {
        let haystack = searchableText
        return haystack.contains("compose")
            || haystack.contains("message body")
            || haystack.contains("subject")
            || haystack.contains("to:")
            || haystack.contains("cc:")
            || haystack.contains("bcc:")
            || haystack.contains("search")
    }

    var looksLikeMessageList: Bool {
        let listRoles = [
            kAXTableRole,
            kAXOutlineRole,
            kAXRowRole,
            kAXCellRole
        ].map { $0 as String }

        guard listRoles.contains(role) else {
            return false
        }

        let haystack = searchableText
        return haystack.contains("message")
            || haystack.contains("messages")
            || haystack.contains("conversation")
            || haystack.contains("inbox")
    }

    private var searchableText: String {
        [role, subrole, title, description, identifier, value]
            .joined(separator: " ")
            .lowercased()
    }
}

private extension AXUIElement {
    func copyAttribute(_ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success else {
            return nil
        }
        return value as! AXUIElement?
    }

    func copyString(_ attribute: String) -> String {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(self, attribute as CFString, &value)
        guard result == .success, let value else {
            return ""
        }

        if let string = value as? String {
            return string
        }

        return "\(value)"
    }
}

private let app = NSApplication.shared
private let delegate = DelIsArchiveApp()
app.setActivationPolicy(.accessory)
app.delegate = delegate
app.run()
