import AppKit
import ServiceManagement

let env = ProcessInfo.processInfo.environment
func envNum(_ k: String, _ d: Double) -> Double { env[k].flatMap(Double.init) ?? d }

let INTERVAL = envNum("YONDER_INTERVAL", 20 * 60)   // работа до перерыва
let BREAK    = envNum("YONDER_BREAK", 30)           // длина перерыва
let IDLE     = envNum("YONDER_IDLE", 5 * 60)        // простой = отдых
let TICK     = envNum("YONDER_TICK", 5)

/// Русский — если система на русском (или YONDER_LANG=ru), иначе английский.
let RU = (env["YONDER_LANG"] ?? Locale.preferredLanguages.first ?? "en").hasPrefix("ru")
func L(_ ru: String, _ en: String) -> String { RU ? ru : en }

func log(_ s: String) {
    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
    FileHandle.standardError.write("\(f.string(from: Date())) \(s)\n".data(using: .utf8)!)
}

/// Счётчик за день: сколько перерывов сделано и сколько пропущено.
struct Stats {
    let d = UserDefaults.standard
    var dayKey: String { let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; return f.string(from: Date()) }
    var done: Int { d.integer(forKey: "done-\(dayKey)") }
    var skipped: Int { d.integer(forKey: "skip-\(dayKey)") }
    func add(done ok: Bool) { let k = (ok ? "done-" : "skip-") + dayKey; d.set(d.integer(forKey: k) + 1, forKey: k) }
}

final class BreakPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

func sound(_ name: String) -> NSSound? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "wav") else { return NSSound(named: "Tink") }
    let s = NSSound(contentsOf: url, byReference: true); s?.volume = 0.6; return s
}

final class App: NSObject, NSApplicationDelegate {
    var sched = Scheduler(interval: INTERVAL, idleReset: IDLE)
    let stats = Stats()
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var timer: Timer?
    var lastTick = Date()
    var windows: [NSWindow] = []
    var countLabels: [NSTextField] = []
    var titleLabels: [NSTextField] = []
    var doneButtons: [NSButton] = []
    var breakTimer: Timer?
    var breakLeft = 0
    var pauseItem: NSMenuItem!
    var statsItem: NSMenuItem!
    var loginItem: NSMenuItem!
    let startSound = sound("start"), endSound = sound("end")

    var inBreak: Bool { !windows.isEmpty }

    func applicationDidFinishLaunching(_ n: Notification) {
        item.button?.image = NSImage(systemSymbolName: "eye", accessibilityDescription: "Yonder")
        item.button?.imagePosition = .imageLeading
        buildMenu()

        let wc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification] {
            wc.addObserver(self, selector: #selector(resetAll), name: name, object: nil)
        }
        let dc = DistributedNotificationCenter.default()
        dc.addObserver(self, selector: #selector(resetAll), name: .init("com.apple.screenIsLocked"), object: nil)
        dc.addObserver(self, selector: #selector(resetAll), name: .init("com.apple.screenIsUnlocked"), object: nil)

        lastTick = Date()
        timer = Timer.scheduledTimer(withTimeInterval: TICK, repeats: true) { [weak self] _ in self?.tick() }
        timer?.tolerance = 1
        refreshTitle()
        log("start interval=\(Int(INTERVAL)) break=\(Int(BREAK)) idle=\(Int(IDLE))")
    }

    func buildMenu() {
        let m = NSMenu()
        statsItem = m.addItem(withTitle: "", action: nil, keyEquivalent: "")
        statsItem.isEnabled = false
        m.addItem(.separator())
        m.addItem(withTitle: L("Перерыв сейчас", "Break now"), action: #selector(breakNow), keyEquivalent: "b").target = self
        pauseItem = m.addItem(withTitle: L("Пауза на час", "Pause for an hour"), action: #selector(togglePause), keyEquivalent: "p")
        pauseItem.target = self
        loginItem = m.addItem(withTitle: L("Открывать при входе", "Open at login"), action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        m.addItem(.separator())
        m.addItem(withTitle: L("Выйти", "Quit"), action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = m
    }

    func idleSeconds() -> TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    func tick() {
        let now = Date()
        let dt = now.timeIntervalSince(lastTick)
        lastTick = now
        guard !inBreak else { return }
        if sched.tick(dt: dt, idle: idleSeconds(), now: now) { showBreak() }
        refreshTitle()
    }

    func refreshTitle() {
        statsItem?.title = L("Сегодня: сделано \(stats.done) · пропущено \(stats.skipped)",
                             "Today: \(stats.done) taken · \(stats.skipped) skipped")
        if sched.isPaused(Date()) {
            item.button?.title = L(" пауза", " paused")
            pauseItem.title = L("Возобновить", "Resume")
        } else {
            item.button?.title = inBreak ? "" : " \(Int(ceil(sched.remaining / 60)))" + L("м", "m")
            pauseItem.title = L("Пауза на час", "Pause for an hour")
        }
    }

    @objc func resetAll() {
        sched.reset(); lastTick = Date()
        if inBreak { closeBreak() }   // сон/блокировка — перерыв не засчитываем ни туда, ни туда
        refreshTitle()
    }

    @objc func breakNow() { showBreak() }

    @objc func togglePause() {
        if sched.isPaused(Date()) { sched.pausedUntil = nil; sched.reset() }
        else { sched.pausedUntil = Date().addingTimeInterval(3600) }
        refreshTitle()
    }

    @objc func toggleLogin() {
        let s = SMAppService.mainApp
        do {
            if s.status == .enabled { try s.unregister() } else { try s.register() }
        } catch { log("login item: \(error)") }
        loginItem.state = s.status == .enabled ? .on : .off
    }

    @objc func quit() { NSApp.terminate(nil) }

    // MARK: перерыв

    func showBreak() {
        guard !inBreak else { return }
        breakLeft = Int(BREAK)
        for screen in NSScreen.screens {
            makeDim(on: screen)
            makePanel(on: screen)
        }
        startSound?.play()
        breakTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.breakLeft -= 1
            self.updateCount()
            if self.breakLeft <= 0 { self.timerFinished() }
        }
        refreshTitle()
        log("break shown on \(NSScreen.screens.count) screen(s)")
    }

    /// Затемнение всего экрана. Клики проходят насквозь — работа и звук не прерываются.
    func makeDim(on screen: NSScreen) {
        let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .statusBar
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        w.isOpaque = false
        w.ignoresMouseEvents = true
        w.hasShadow = false
        w.setFrame(screen.frame, display: false)
        fadeIn(w)
    }

    func makePanel(on screen: NSScreen) {
        let w: CGFloat = 400, h: CGFloat = 250
        let f = screen.frame
        let rect = NSRect(x: f.midX - w / 2, y: f.midY - h / 2, width: w, height: h)
        let p = BreakPanel(contentRect: rect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.hidesOnDeactivate = false
        p.appearance = NSAppearance(named: .darkAqua)

        let (bg, count, title, done) = breakView(size: rect.size, target: self, left: breakLeft, behindWindow: true)
        p.contentView = bg

        fadeIn(p)
        countLabels.append(count); titleLabels.append(title); doneButtons.append(done)
    }

    func fadeIn(_ w: NSWindow) {
        w.alphaValue = 0
        w.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { $0.duration = 0.6; w.animator().alphaValue = 1 }
        windows.append(w)
    }

    func updateCount() { for l in countLabels { l.stringValue = "\(max(0, breakLeft))" } }

    func timerFinished() {
        breakTimer?.invalidate(); breakTimer = nil
        endSound?.play()
        for l in titleLabels { l.stringValue = L("Можно возвращаться", "You can go back") }
        for b in doneButtons { b.isEnabled = true }
        log("timer finished")
    }

    func closeBreak() {
        breakTimer?.invalidate(); breakTimer = nil
        startSound?.stop()
        let closing = windows
        windows = []; countLabels = []; titleLabels = []; doneButtons = []
        NSAnimationContext.runAnimationGroup({ $0.duration = 0.4; for w in closing { w.animator().alphaValue = 0 } },
                                             completionHandler: { for w in closing { w.orderOut(nil) } })
        sched.reset(); lastTick = Date()
        refreshTitle()
    }

    @objc func skipBreak() { stats.add(done: false); log("skip"); closeBreak() }
    @objc func doneBreak() { stats.add(done: true); log("done"); closeBreak() }
}

/// Панель перерыва: заголовок, обратный отсчёт, подсказка и две кнопки.
func breakView(size: NSSize, target: AnyObject, left: Int, behindWindow: Bool)
    -> (NSVisualEffectView, NSTextField, NSTextField, NSButton) {
    let bg = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
    bg.material = .hudWindow
    bg.state = .active
    bg.blendingMode = behindWindow ? .behindWindow : .withinWindow
    bg.wantsLayer = true
    bg.layer?.cornerRadius = 24
    bg.layer?.masksToBounds = true

    let title = NSTextField(labelWithString: L("Сделай перерыв", "Take a break"))
    title.font = .systemFont(ofSize: 26, weight: .semibold)

    let count = NSTextField(labelWithString: "\(left)")
    count.font = .monospacedDigitSystemFont(ofSize: 72, weight: .ultraLight)

    let hint = NSTextField(labelWithString: L("Смотри вдаль · моргай", "Look far away · blink"))
    hint.font = .systemFont(ofSize: 13)
    hint.textColor = .secondaryLabelColor

    let skip = NSButton(title: L("Пропустить", "Skip"), target: target, action: #selector(App.skipBreak))
    let done = NSButton(title: L("Готово", "Done"), target: target, action: #selector(App.doneBreak))
    done.keyEquivalent = "\r"
    done.isEnabled = false
    for b in [skip, done] { b.bezelStyle = .rounded; b.controlSize = .large }
    let buttons = NSStackView(views: [skip, done]); buttons.spacing = 12

    let stack = NSStackView(views: [title, count, hint, buttons])
    stack.orientation = .vertical
    stack.spacing = 4
    stack.setCustomSpacing(18, after: hint)
    stack.translatesAutoresizingMaskIntoConstraints = false
    bg.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.centerXAnchor.constraint(equalTo: bg.centerXAnchor),
        stack.centerYAnchor.constraint(equalTo: bg.centerYAnchor),
    ])
    return (bg, count, title, done)
}

let app = NSApplication.shared
if let out = env["YONDER_DEMO"] {   // снимки для README, см. Demo.swift
    app.setActivationPolicy(.accessory)
    Demo.run(out: out, scene: env["YONDER_DEMO_SCENE"] ?? "break")
    app.run()
}
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
