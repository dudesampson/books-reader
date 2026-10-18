import Cocoa
import AVFoundation
import ApplicationServices
import MediaPlayer

// Short first segment starts playback quickly; remaining segments are generated ahead.
func segments(_ text: String) -> [String] {
    let sentences = text.components(separatedBy: .newlines).flatMap { paragraph -> [String] in
        var result: [String] = []
        paragraph.enumerateSubstrings(in: paragraph.startIndex..<paragraph.endIndex, options: .bySentences) { s, _, _, _ in
            if let s = s { result.append(s) }
        }
        return result.isEmpty && !paragraph.isEmpty ? [paragraph] : result
    }
    var result: [String] = [], chunk = ""
    for sentence in sentences {
        for word in sentence.split(whereSeparator: { $0.isWhitespace }) {
            let limit = result.isEmpty ? 280 : 900
            if !chunk.isEmpty && chunk.count + word.count + 1 > limit { result.append(chunk); chunk = "" }
            chunk += (chunk.isEmpty ? "" : " ") + word
        }
    }
    if !chunk.isEmpty { result.append(chunk) }
    return result
}
func seekPosition(_ seconds: Double, durations: [Double]) -> (Int, Double) {
    var remaining = max(0, seconds)
    for (index, length) in durations.enumerated() {
        if remaining < length || index == durations.count - 1 { return (index, min(remaining, max(0, length - 0.05))) }
        remaining -= length
    }
    return (0, 0)
}
enum TransportAction { case play, pause, toggle }
func pauseState(for action: TransportAction, currentlyPaused: Bool) -> Bool {
    switch action { case .play: return false; case .pause: return true; case .toggle: return !currentlyPaused }
}
struct Page { let window: AXUIElement; let title: String; let text: String; let label: String }
struct AudioPart { let url: URL; let duration: Double }

// Accessible native buttons with a clear, circular transport hierarchy.
final class PlaybackButton: NSButton {
    var symbolName: String { didSet { needsDisplay = true } }
    let primary: Bool
    var sizeConstraints: [NSLayoutConstraint] = []
    init(symbol: String, title: String, primary: Bool, target: AnyObject?, action: Selector) {
        self.symbolName = symbol; self.primary = primary
        super.init(frame: .zero)
        self.title = title; self.target = target; self.action = action
        isBordered = false; setButtonType(.momentaryPushIn)
        setAccessibilityLabel(title); toolTip = title
        let size: CGFloat = primary ? 72 : 52
        sizeConstraints = [widthAnchor.constraint(equalToConstant: size), heightAnchor.constraint(equalToConstant: size)]
        NSLayoutConstraint.activate(sizeConstraints)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    func setCompact(_ compact: Bool) {
        let size: CGFloat = primary ? (compact ? 54 : 72) : (compact ? 42 : 52)
        for constraint in sizeConstraints { constraint.constant = size }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let opacity: CGFloat = isEnabled ? (isHighlighted ? 0.75 : 1) : 0.35
        let fill = primary ? NSColor.controlAccentColor : NSColor.quaternaryLabelColor.withAlphaComponent(0.08)
        fill.withAlphaComponent(fill.alphaComponent * opacity).setFill()
        NSBezierPath(ovalIn: bounds.insetBy(dx: 2, dy: 2)).fill()
        let color = primary ? NSColor.white : NSColor.labelColor
        let config = NSImage.SymbolConfiguration(pointSize: (primary ? 27 : 25) * bounds.width / (primary ? 72 : 52), weight: .semibold).applying(.init(paletteColors: [color.withAlphaComponent(opacity)]))
        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
            let size = image.size
            image.draw(in: NSRect(x: (bounds.width-size.width)/2, y: (bounds.height-size.height)/2, width: size.width, height: size.height))
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.5, dy: 0.5)); ring.lineWidth = 2; ring.stroke()
        }
    }
}

final class Reader: NSObject, NSApplicationDelegate, AVAudioPlayerDelegate, NSWindowDelegate {
    var window: NSWindow!
    let status = NSTextField(wrappingLabelWithString: "Open a book in Apple Books, then click Read Page.")
    let position = NSTextField(labelWithString: "Ready")
    let pageSubtitle = NSTextField(labelWithString: "Open a book to get started")
    let primaryCaption = NSTextField(labelWithString: "Read Page")
    var seekButtons: [NSButton] = []
    var stopButton: NSButton!
    let time = NSTextField(labelWithString: "0:00")
    let scrub = NSSlider(value: 0, minValue: 0, maxValue: 1, target: nil, action: nil)
    let speed = NSPopUpButton()
    let auto = NSButton(checkboxWithTitle: "Automatically turn pages", target: nil, action: nil)
    var pauseButton: NSButton!, nextButton: NSButton!, previousButton: NSButton!
    var player: AVAudioPlayer?, job: Process?, folder: URL?
    var token = 0, running = false, paused = false, turning = false
    var chunks: [String] = [], audio: [AudioPart] = [], index = 0
    var page: Page?
    var rate: Float = 1
    var timer: Timer?
    var updateDensity: (() -> Void)?
    var remoteTargets: [(MPRemoteCommand, Any)] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let menu = NSMenu(); let root = NSMenuItem(); menu.addItem(root)
        let items = NSMenu(); items.addItem(withTitle: "Quit Books Reader", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); root.submenu = items; NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 580), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Books Reader"; window.level = .floating; window.center()
        // Floating windows otherwise default to transient and disappear in Mission Control.
        window.collectionBehavior = [.managed, .participatesInCycle]
        window.contentMinSize = NSSize(width: 420, height: 430)
        window.setFrameAutosaveName("BooksReaderControls")
        let background = NSVisualEffectView(); background.material = .windowBackground; background.blendingMode = .behindWindow; background.state = .active
        window.contentView = background
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .centerX; stack.spacing = 18; stack.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(stack)
        let leftInset = stack.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 28)
        let rightInset = stack.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -28)
        let topInset = stack.topAnchor.constraint(equalTo: background.topAnchor, constant: 24)
        NSLayoutConstraint.activate([leftInset, rightInset, topInset])
        func fullWidth(_ view: NSView) { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        func label(_ text: String, size: CGFloat = 11, weight: NSFont.Weight = .regular) -> NSTextField {
            let field = NSTextField(labelWithString: text); field.font = .systemFont(ofSize: size, weight: weight); field.textColor = .secondaryLabelColor; return field
        }
        func symbol(_ name: String, size: CGFloat) -> NSImage? { NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: size, weight: .medium)) }
        let icon = NSImageView(); icon.image = symbol("book.closed.fill", size: 30); icon.contentTintColor = .systemOrange
        icon.widthAnchor.constraint(equalToConstant: 52).isActive = true; let iconHeight = icon.heightAnchor.constraint(equalToConstant: 64); iconHeight.isActive = true
        let headings = NSStackView(); headings.orientation = .vertical; headings.alignment = .leading; headings.spacing = 4
        headings.addArrangedSubview(label("APPLE BOOKS  /  READ ALOUD", size: 10, weight: .semibold))
        position.stringValue = "Ready to read"; position.font = .systemFont(ofSize: 23, weight: .semibold); position.lineBreakMode = .byTruncatingTail
        position.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        headings.addArrangedSubview(position)
        pageSubtitle.font = .systemFont(ofSize: 12); pageSubtitle.textColor = .secondaryLabelColor; headings.addArrangedSubview(pageSubtitle)
        let header = NSStackView(views: [icon, headings]); header.spacing = 14; header.alignment = .centerY
        stack.addArrangedSubview(header); fullWidth(header)
        headings.widthAnchor.constraint(equalTo: header.widthAnchor, constant: -66).isActive = true
        position.widthAnchor.constraint(equalTo: headings.widthAnchor).isActive = true
        let divider = NSBox(); divider.boxType = .separator; stack.addArrangedSubview(divider); fullWidth(divider)

        let progress = NSStackView(); progress.orientation = .vertical; progress.alignment = .leading; progress.spacing = 6
        scrub.target = self; scrub.action = #selector(seek(_:)); scrub.isContinuous = false
        scrub.toolTip = "Seek within prepared audio for this page"; scrub.setAccessibilityLabel("Page audio position")
        progress.addArrangedSubview(scrub)
        scrub.widthAnchor.constraint(equalTo: progress.widthAnchor).isActive = true
        let timeRow = NSStackView(); timeRow.spacing = 8
        let timeCaption = label("PAGE AUDIO", size: 10, weight: .semibold)
        let spacer = NSView(); timeRow.addArrangedSubview(timeCaption); timeRow.addArrangedSubview(spacer)
        time.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium); time.textColor = .secondaryLabelColor; time.setContentHuggingPriority(.required, for: .horizontal); timeRow.addArrangedSubview(time)
        progress.addArrangedSubview(timeRow); timeRow.widthAnchor.constraint(equalTo: progress.widthAnchor).isActive = true
        stack.addArrangedSubview(progress); fullWidth(progress)

        let transportRow = NSStackView(); transportRow.spacing = 32; transportRow.alignment = .centerY
        func skipControl(_ backwards: Bool) -> NSStackView {
            let b = PlaybackButton(symbol: backwards ? "gobackward.15" : "goforward.15", title: backwards ? "Back 15 seconds" : "Forward 15 seconds", primary: false, target: self, action: backwards ? #selector(back(_:)) : #selector(forward(_:)))
            b.tag = 15; seekButtons.append(b)
            let group = NSStackView(views: [b, label(backwards ? "Back 15s" : "Forward 15s")]); group.orientation = .vertical; group.spacing = 7; return group
        }
        transportRow.addArrangedSubview(skipControl(true))
        pauseButton = PlaybackButton(symbol: "play.fill", title: "Read Page", primary: true, target: self, action: #selector(primaryPlayback))
        pauseButton.keyEquivalent = " "; pauseButton.keyEquivalentModifierMask = []
        primaryCaption.font = .systemFont(ofSize: 12, weight: .medium)
        let primaryGroup = NSStackView(views: [pauseButton, primaryCaption]); primaryGroup.orientation = .vertical; primaryGroup.spacing = 7
        transportRow.addArrangedSubview(primaryGroup); transportRow.addArrangedSubview(skipControl(false)); stack.addArrangedSubview(transportRow)

        let extra = NSStackView(); extra.spacing = 10
        for seconds in [60, 30] { let b = button("−\(seconds)s", #selector(back(_:))); b.tag = seconds; b.toolTip = "Back \(seconds) seconds"; b.setAccessibilityLabel("Back \(seconds) seconds"); seekButtons.append(b); extra.addArrangedSubview(b) }
        stopButton = button("Stop", #selector(stop)); stopButton.image = symbol("stop.fill", size: 10); stopButton.imagePosition = .imageLeading; stopButton.keyEquivalent = "\u{1b}"; extra.addArrangedSubview(stopButton)
        for seconds in [30, 60] { let b = button("+\(seconds)s", #selector(forward(_:))); b.tag = seconds; b.toolTip = "Forward \(seconds) seconds"; b.setAccessibilityLabel("Forward \(seconds) seconds"); seekButtons.append(b); extra.addArrangedSubview(b) }
        stack.addArrangedSubview(extra)
        let secondDivider = NSBox(); secondDivider.boxType = .separator; stack.addArrangedSubview(secondDivider); fullWidth(secondDivider)

        let navigation = NSStackView(); navigation.spacing = 12
        previousButton = button("Previous Page", #selector(previousPage)); previousButton.image = symbol("chevron.left", size: 11); previousButton.imagePosition = .imageLeading
        nextButton = button("Next Page", #selector(nextPage)); nextButton.image = symbol("chevron.right", size: 11); nextButton.imagePosition = .imageTrailing
        let reread = button("Read visible page", #selector(start)); reread.toolTip = "Start reading the page currently visible in Books from the beginning"
        navigation.addArrangedSubview(previousButton); navigation.addArrangedSubview(reread); navigation.addArrangedSubview(nextButton); stack.addArrangedSubview(navigation)
        let settings = NSStackView(); settings.spacing = 10
        settings.addArrangedSubview(label("Speed", size: 12))
        speed.addItems(withTitles: ["1×", "1.25×", "1.5×", "2×"]); speed.target = self; speed.action = #selector(changeSpeed)
        let saved = UserDefaults.standard.integer(forKey: "speedIndex"); speed.selectItem(at: min(max(saved, 0), 3)); rate = [1, 1.25, 1.5, 2][speed.indexOfSelectedItem]
        settings.addArrangedSubview(speed); settings.addArrangedSubview(NSView()); auto.state = .on; auto.font = .systemFont(ofSize: 12); settings.addArrangedSubview(auto); stack.addArrangedSubview(settings); fullWidth(settings)
        status.font = .systemFont(ofSize: 12); status.textColor = .secondaryLabelColor; status.alignment = .center
        stack.addArrangedSubview(status); fullWidth(status)
        let hint = label("Space: play/pause   ·   Esc: stop   ·   Time skips stay on this page", size: 10)
        hint.alignment = .center; hint.maximumNumberOfLines = 2; hint.lineBreakMode = .byWordWrapping
        stack.addArrangedSubview(hint); fullWidth(hint)
        var appliedCompact: Bool?
        updateDensity = { [weak self] in
            guard let self = self else { return }
            let size = background.bounds.size
            let compact = size.width < 540 || size.height < 560
            guard appliedCompact != compact else { return }
            appliedCompact = compact
            stack.spacing = compact ? 9 : 18
            leftInset.constant = compact ? 18 : 28; rightInset.constant = compact ? -18 : -28
            topInset.constant = compact ? 14 : 24
            iconHeight.constant = compact ? 48 : 64
            headings.spacing = compact ? 2 : 4
            self.position.font = .systemFont(ofSize: compact ? 18 : 23, weight: .semibold)
            self.status.font = .systemFont(ofSize: compact ? 11 : 12)
            self.pageSubtitle.font = .systemFont(ofSize: compact ? 11 : 12)
            self.primaryCaption.font = .systemFont(ofSize: compact ? 11 : 12, weight: .medium)
            transportRow.spacing = compact ? 24 : 32; extra.spacing = compact ? 6 : 10
            navigation.spacing = compact ? 6 : 12
            func resizeControls(_ view: NSView) {
                if let b = view as? PlaybackButton { b.setCompact(compact) }
                else if let b = view as? NSButton {
                    b.controlSize = compact ? .small : .regular
                    b.font = .systemFont(ofSize: compact ? 11 : 13)
                }
                for child in view.subviews { resizeControls(child) }
            }
            resizeControls(stack)
            self.auto.font = .systemFont(ofSize: compact ? 11 : 12)
            self.speed.controlSize = compact ? .small : .regular
            background.needsLayout = true
        }
        window.delegate = self; updateDensity?()
        configureMediaControls()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in self?.updateTimeline() }
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); updateControls()
    }
    func windowDidResize(_ notification: Notification) { updateDensity?() }
    func button(_ title: String, _ selector: Selector) -> NSButton { NSButton(title: title, target: self, action: selector) }
    func attr(_ e: AXUIElement, _ key: String) -> CFTypeRef? { var v: CFTypeRef?; AXUIElementCopyAttributeValue(e, key as CFString, &v); return v }
    func children(_ e: AXUIElement) -> [AXUIElement] { attr(e, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    func text(_ e: AXUIElement, inside: Bool = false, depth: Int = 0) -> [String] {
        guard depth < 35 else { return [] }
        let role = attr(e, kAXRoleAttribute) as? String ?? ""
        if (inside || role == "AXWebArea") && role == "AXStaticText" { return [attr(e, kAXValueAttribute) as? String ?? ""] }
        return children(e).flatMap { text($0, inside: inside || role == "AXWebArea", depth: depth + 1) }
    }
    func pageLabel(_ e: AXUIElement, depth: Int = 0) -> String {
        guard depth < 35 else { return "" }
        if let d = attr(e, kAXDescriptionAttribute) as? String, d.hasPrefix("Page ") { return d }
        for c in children(e) { let found = pageLabel(c, depth: depth + 1); if !found.isEmpty { return found } }
        return ""
    }
    func snapshot() -> Page? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iBooksX").first else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier); AXUIElementSetMessagingTimeout(root, 1)
        for w in attr(root, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
            let words = text(w).filter { !$0.isEmpty }.joined(separator: "\n")
            if !words.isEmpty { return Page(window: w, title: attr(w, kAXTitleAttribute) as? String ?? "Books", text: words, label: pageLabel(w)) }
        }
        return nil
    }
    func permitted() -> Bool {
        if AXIsProcessTrusted() { return true }
        status.stringValue = "Enable Books Reader in System Settings → Privacy & Security → Accessibility. If already enabled, remove and re-add this updated app."
        return false
    }
    @objc func start() {
        stop(); guard permitted() else { return }
        guard let p = snapshot() else { status.stringValue = "Open a readable book page in Apple Books first."; return }
        running = true; begin(p)
    }
    func begin(_ p: Page) {
        page = p; chunks = segments(p.text); audio = []; index = 0
        guard !chunks.isEmpty else { fail("This page contains no readable text."); return }
        position.stringValue = p.title
        pageSubtitle.stringValue = p.label.isEmpty ? "Current page" : p.label
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("BooksReader-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: folder!, withIntermediateDirectories: true) } catch { fail(error.localizedDescription); return }
        status.stringValue = "Preparing the opening passage…"; updateControls(); generateNext()
    }
    func generateNext() {
        guard running, job == nil, audio.count < chunks.count, let dir = folder else { return }
        let n = audio.count, generation = token
        let input = dir.appendingPathComponent("\(n).txt"), output = dir.appendingPathComponent("\(n).aiff")
        do {
            try chunks[n].write(to: input, atomically: true, encoding: .utf8)
            let p = Process(); p.executableURL = URL(fileURLWithPath: "/usr/bin/say"); p.arguments = ["-r", "175", "-f", input.path, "-o", output.path]
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { [weak self] process in DispatchQueue.main.async {
                guard let s = self, generation == s.token, s.running else { try? FileManager.default.removeItem(at: dir); return }
                s.job = nil
                guard process.terminationStatus == 0 else { s.fail("Could not prepare speech. Click Read Page to retry."); return }
                do {
                    let probe = try AVAudioPlayer(contentsOf: output)
                    s.audio.append(AudioPart(url: output, duration: probe.duration))
                    if s.player == nil && s.index < s.audio.count { s.playPart(s.index) }
                    s.generateNext(); s.updateNowPlaying()
                } catch { s.fail(error.localizedDescription) }
            }}
            job = p; try p.run()
        } catch { fail(error.localizedDescription) }
    }
    func playPart(_ part: Int, offset: Double = 0) {
        guard running, part < audio.count else { return }
        do {
            let p = try AVAudioPlayer(contentsOf: audio[part].url)
            player?.stop(); player = p; index = part; p.delegate = self; p.enableRate = true; p.rate = rate; p.currentTime = offset
            if !paused { p.play() }
            status.stringValue = paused ? "Paused. Your position is saved." : "Reading. Remaining audio is prepared in the background."
            updateControls()
        } catch { fail(error.localizedDescription) }
    }
    // Explicit play/pause commands are idempotent; headset toggles use the same path as the UI.
    func transport(_ action: TransportAction) {
        guard running else { return }
        paused = pauseState(for: action, currentlyPaused: paused)
        if paused { player?.pause() } else { player?.play() }
        status.stringValue = paused ? "Paused. Your position is saved." : (player == nil ? "Preparing audio…" : "Reading…")
        updateControls()
    }
    @objc func primaryPlayback() { if running { transport(.toggle) } else { start() } }
    @objc func togglePause() { transport(.toggle) }
    @objc func changeSpeed() { rate = [1, 1.25, 1.5, 2][speed.indexOfSelectedItem]; player?.rate = rate; UserDefaults.standard.set(speed.indexOfSelectedItem, forKey: "speedIndex"); updateNowPlaying() }
    func configureMediaControls() {
        let center = MPRemoteCommandCenter.shared()
        func register(_ command: MPRemoteCommand, available: @escaping (Reader) -> Bool = { $0.running }, action: @escaping (Reader) -> Void) {
            let target = command.addTarget { [weak self] _ -> MPRemoteCommandHandlerStatus in
                let perform = { () -> MPRemoteCommandHandlerStatus in
                    guard let self = self, available(self) else { return .noSuchContent }
                    action(self)
                    return .success
                }
                return Thread.isMainThread ? perform() : DispatchQueue.main.sync(execute: perform)
            }
            remoteTargets.append((command, target))
        }
        register(center.playCommand) { $0.transport(.play) }
        register(center.pauseCommand) { $0.transport(.pause) }
        register(center.togglePlayPauseCommand) { $0.transport(.toggle) }
        register(center.stopCommand) { $0.stop() }
        // AirPods double/triple presses send next/previous track commands.
        // Interpret them as page-local skips instead of navigating to another page.
        register(center.nextTrackCommand, available: { $0.canSeek }) { $0.jump($0.elapsed + 15) }
        register(center.previousTrackCommand, available: { $0.canSeek }) { $0.jump($0.elapsed - 15) }
        updateNowPlaying()
    }
    func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        for (command, _) in remoteTargets { command.isEnabled = running }
        let commands = MPRemoteCommandCenter.shared()
        commands.nextTrackCommand.isEnabled = canSeek
        commands.previousTrackCommand.isEnabled = canSeek
        guard running, let page = page else {
            center.playbackState = .stopped
            center.nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: page.title,
            MPMediaItemPropertyArtist: "Books Reader",
            MPMediaItemPropertyAlbumTitle: page.label.isEmpty ? "Current page" : page.label,
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: (!paused && player?.isPlaying == true) ? Double(rate) : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: Double(rate)
        ]
        // The final duration is unknown until every passage has been generated.
        if !audio.isEmpty && audio.count == chunks.count {
            info[MPMediaItemPropertyPlaybackDuration] = audio.reduce(0) { $0 + $1.duration }
        }
        center.nowPlayingInfo = info
        // macOS requires playbackState as well as metadata to route headset/media commands.
        // Keep this reading session registered through pauses and preparation gaps.
        center.playbackState = paused ? .paused : .playing
    }
    var elapsed: Double { audio.prefix(index).reduce(0) { $0 + $1.duration } + (player?.currentTime ?? 0) }
    var canSeek: Bool { running && !turning && !audio.isEmpty }
    func jump(_ seconds: Double) { guard canSeek else { return }; let (i, t) = seekPosition(seconds, durations: audio.map { $0.duration }); playPart(i, offset: t) }
    @objc func back(_ sender: NSButton) { jump(elapsed - Double(sender.tag)) }
    @objc func forward(_ sender: NSButton) { jump(elapsed + Double(sender.tag)) }
    @objc func seek(_ sender: NSSlider) { jump(sender.doubleValue) }
    func updateTimeline() {
        let total = audio.reduce(0) { $0 + $1.duration }
        scrub.maxValue = max(1, total); scrub.doubleValue = elapsed
        func stamp(_ t: Double) -> String { String(format: "%d:%02d", Int(t)/60, Int(t)%60) }
        time.stringValue = "\(stamp(elapsed)) / \(stamp(total))\(audio.count < chunks.count ? "+" : "")"
        scrub.isEnabled = running && !audio.isEmpty && !turning
        for b in seekButtons where b.isEnabled != canSeek { b.isEnabled = canSeek; b.needsDisplay = true }
    }
    func updateControls() {
        let caption = !running ? "Read Page" : (paused ? "Resume" : "Pause")
        pauseButton.title = caption; pauseButton.setAccessibilityLabel(caption); pauseButton.toolTip = caption + " (Space)"
        (pauseButton as? PlaybackButton)?.symbolName = running && !paused ? "pause.fill" : "play.fill"
        primaryCaption.stringValue = caption; pauseButton.isEnabled = !turning
        stopButton.isEnabled = running
        nextButton.isEnabled = !turning; previousButton.isEnabled = !turning
        for b in seekButtons { b.isEnabled = canSeek; b.needsDisplay = true }
        updateNowPlaying()
    }
    func cancelAudio() {
        token += 1; player?.stop(); player = nil
        let p = job; job = nil; if let p = p, p.isRunning { p.terminate() }
        if let dir = folder { try? FileManager.default.removeItem(at: dir) }; folder = nil
        audio = []; chunks = []; index = 0
    }
    @objc func stop() { running = false; paused = false; turning = false; cancelAudio(); status.stringValue = "Stopped. Read Page starts the visible page again."; if pauseButton != nil { updateControls(); updateTimeline() } }
    func fail(_ message: String) { stop(); status.stringValue = message }
    @objc func nextPage() { navigatePage(forward: true) }
    @objc func previousPage() { navigatePage(forward: false) }
    func navigatePage(forward: Bool) {
        guard !turning, permitted() else { return }
        guard let p = snapshot() else { fail("Open a book page first."); return }
        turn(from: p, forward: forward)
    }
    func turn(from p: Page, forward: Bool = true) {
        cancelAudio(); running = true; paused = false; turning = true; updateControls(); status.stringValue = forward ? "Turning to next page…" : "Turning to previous page…"
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.iBooksX").first else { fail("Books is no longer open."); return }
        let id = token
        AXUIElementPerformAction(p.window, kAXRaiseAction as CFString)
        app.activate(options: [])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let s = self, s.running, s.token == id else { return }
            guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.iBooksX", let check = s.snapshot(), check.title == p.title, check.text == p.text else { s.fail("Page or app changed. Click Read Page to continue where you are."); return }
            // Target Books directly; controls do not need to be visible.
            let down = CGEvent(keyboardEventSource: nil, virtualKey: forward ? 124 : 123, keyDown: true)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: forward ? 124 : 123, keyDown: false)
            down?.postToPid(app.processIdentifier); up?.postToPid(app.processIdentifier)
            s.waitForPage(p, generation: id, attempts: 16, candidate: nil)
        }
    }
    func waitForPage(_ old: Page, generation: Int, attempts: Int, candidate: String?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let s = self, s.running, s.token == generation else { return }
            if let p = s.snapshot(), p.title == old.title, p.text != old.text {
                if candidate == p.text { s.turning = false; s.begin(p); return }
                if attempts > 0 { s.waitForPage(old, generation: generation, attempts: attempts - 1, candidate: p.text); return }
            }
            if attempts > 0 { s.waitForPage(old, generation: generation, attempts: attempts - 1, candidate: nil) }
            else { s.fail("No new readable page. This may be the beginning or end of the book or sample.") }
        }
    }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard running, player === self.player else { return }; self.player = nil
        guard flag else { fail("Playback interrupted. Click Read Page to restart."); return }
        index += 1
        if index < audio.count { playPart(index) }
        else if index < chunks.count { status.stringValue = paused ? "Paused." : "Preparing the next passage…"; updateNowPlaying() }
        else if auto.state == .on {
            guard let old = page, let now = snapshot(), now.title == old.title, now.text == old.text else { fail("You changed the page. Click Read Page to read the page now visible."); return }
            turn(from: old)
        } else { stop(); status.stringValue = "Page finished. Click Next Page to continue." }
    }
    func applicationWillTerminate(_ notification: Notification) { timer?.invalidate(); stop(); for (command, target) in remoteTargets { command.removeTarget(target) }; remoteTargets.removeAll() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
if CommandLine.arguments.contains("--self-test") {
    let source = String(repeating: "This is a sentence with several words. ", count: 100)
    let pieces = segments(source)
    assert(pieces.count > 2 && pieces[0].count <= 280 && pieces.dropFirst().allSatisfy { $0.count <= 900 })
    assert(pieces.joined(separator: " ").split(whereSeparator: { $0.isWhitespace }) == source.split(whereSeparator: { $0.isWhitespace }))
    assert(segments("").isEmpty)
    let a = seekPosition(35, durations: [20, 30, 40]); assert(a.0 == 1 && a.1 == 15)
    let b = seekPosition(-15, durations: [20, 30]); assert(b.0 == 0 && b.1 == 0)
    let c = seekPosition(100, durations: [20, 30]); assert(c.0 == 1 && c.1 < 30)
    let forward = seekPosition(10 + 15, durations: [20, 30]); assert(forward.0 == 1 && forward.1 == 5)
    let backward = seekPosition(25 - 15, durations: [20, 30]); assert(backward.0 == 0 && backward.1 == 10)
    let endSkip = seekPosition(45 + 15, durations: [20, 30]); assert(endSkip.0 == 1 && endSkip.1 < 30)
    for paused in [true, false] {
        assert(pauseState(for: .play, currentlyPaused: paused) == false)
        assert(pauseState(for: .pause, currentlyPaused: paused) == true)
        assert(pauseState(for: .toggle, currentlyPaused: paused) == !paused)
    }
    print("PASS: media play/pause idempotence, headset toggle, and 15-second skip boundaries")
    print("PASS: segment bounds, complete text preservation, empty text, cross-segment seeking and bounds")
} else {
    let app = NSApplication.shared; let reader = Reader(); app.delegate = reader; app.setActivationPolicy(.regular); app.run()
}
