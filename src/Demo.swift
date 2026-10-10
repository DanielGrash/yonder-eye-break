import AppKit

/// Снимки для README: обычный рабочий стол macOS (обои, строка меню, Dock) и настоящая панель перерыва.
/// YONDER_DEMO=out.png YONDER_DEMO_SCENE=menu|break|done
enum Demo {
    static var window: NSWindow?
    static let size = NSSize(width: 1440, height: 900)

    static func run(out: String, scene: String) {
        let screen = NSScreen.main!.frame
        let w = NSWindow(contentRect: NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                             width: size.width, height: size.height),
                         styleMask: .borderless, backing: .buffered, defer: false)
        w.level = .floating
        w.appearance = NSAppearance(named: .darkAqua)
        let root = NSView(frame: NSRect(origin: .zero, size: size))
        w.contentView = root

        let wall = NSImageView(frame: root.bounds)
        wall.image = NSImage(contentsOfFile: "/System/Library/Desktop Pictures/Sonoma.heic")
        wall.imageScaling = .scaleAxesIndependently
        root.addSubview(wall)
        root.addSubview(menuBar(minutes: scene == "menu" ? 12 : nil))
        root.addSubview(dock())

        if scene == "menu" {
            root.addSubview(dropdown())
        } else {
            let dim = NSView(frame: root.bounds)
            dim.wantsLayer = true
            dim.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.6).cgColor
            root.addSubview(dim)

            let ps = NSSize(width: 400, height: 250)
            let holder = NSView(frame: NSRect(x: (size.width - ps.width) / 2, y: (size.height - ps.height) / 2,
                                              width: ps.width, height: ps.height))
            holder.wantsLayer = true
            holder.layer?.shadowColor = NSColor.black.cgColor
            holder.layer?.shadowOpacity = 0.5
            holder.layer?.shadowRadius = 30
            holder.layer?.shadowOffset = .init(width: 0, height: -10)
            let finished = scene == "done"
            let (bg, _, title, done) = breakView(size: ps, target: NSObject(), left: finished ? 0 : 17, behindWindow: false)
            if finished { title.stringValue = L("Можно возвращаться", "You can go back"); done.isEnabled = true }
            holder.addSubview(bg)
            root.addSubview(holder)
        }

        w.orderFrontRegardless()
        window = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            p.arguments = ["-x", "-o", "-l\(w.windowNumber)", out]
            try? p.run(); p.waitUntilExit()
            exit(p.terminationStatus)
        }
    }

    static func label(_ s: String, _ font: NSFont, _ color: NSColor = .white) -> NSTextField {
        let t = NSTextField(labelWithString: s)
        t.font = font; t.textColor = color
        t.wantsLayer = true
        t.shadow = { let s = NSShadow(); s.shadowColor = .black.withAlphaComponent(0.35); s.shadowBlurRadius = 2; return s }()
        return t
    }

    static func symbol(_ name: String, _ pt: CGFloat = 14) -> NSImageView {
        let cfg = NSImage.SymbolConfiguration(pointSize: pt, weight: .medium)
        let v = NSImageView(image: NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!)
        v.contentTintColor = .white
        return v
    }

    static func row(_ views: [NSView], spacing: CGFloat) -> NSStackView {
        let s = NSStackView(views: views); s.spacing = spacing; s.alignment = .centerY
        return s
    }

    /// Строка меню: слева Finder, справа иконка приложения с минутами до перерыва, Wi-Fi, батарея, часы.
    static func menuBar(minutes: Int?) -> NSView {
        let h: CGFloat = 26
        let bar = NSView(frame: NSRect(x: 0, y: size.height - h, width: size.width, height: h))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.12).cgColor

        let menus = ["File", "Edit", "View", "Go", "Window", "Help"].map { label($0, .systemFont(ofSize: 13.5)) as NSView }
        let left = row([symbol("apple.logo", 15), label("Finder", .boldSystemFont(ofSize: 13.5))] + menus, spacing: 19)

        var mine: [NSView] = [symbol("eye")]
        if let m = minutes { mine.append(label("\(m)" + L("м", "m"), .systemFont(ofSize: 13.5))) }
        let eye = row(mine, spacing: 4)
        let eyeBox = NSView()
        eyeBox.wantsLayer = true
        if minutes != nil {   // подсветка открытого пункта, как у системы
            eyeBox.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.22).cgColor
            eyeBox.layer?.cornerRadius = 5
        }
        eye.translatesAutoresizingMaskIntoConstraints = false
        eyeBox.addSubview(eye)
        NSLayoutConstraint.activate([
            eye.leadingAnchor.constraint(equalTo: eyeBox.leadingAnchor, constant: 8),
            eye.trailingAnchor.constraint(equalTo: eyeBox.trailingAnchor, constant: -8),
            eye.centerYAnchor.constraint(equalTo: eyeBox.centerYAnchor),
            eyeBox.heightAnchor.constraint(equalToConstant: 22),
        ])
        let right = row([eyeBox, symbol("wifi"), symbol("battery.75percent", 16), symbol("magnifyingglass"),
                         symbol("switch.2"), label("Sat Oct 10  13:40", .systemFont(ofSize: 13.5))], spacing: 14)

        for (v, lead) in [(left, true), (right, false)] {
            v.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(v)
            NSLayoutConstraint.activate([v.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
                lead ? v.leadingAnchor.constraint(equalTo: bar.leadingAnchor, constant: 20)
                     : v.trailingAnchor.constraint(equalTo: bar.trailingAnchor, constant: -14)])
        }
        return bar
    }

    /// Меню приложения — те же пункты, что в настоящем.
    static func dropdown() -> NSView {
        let items: [(String, String, Bool)] = [
            (L("Сегодня: сделано 7 · пропущено 1", "Today: 7 taken · 1 skipped"), "", false),
            ("-", "", false),
            (L("Перерыв сейчас", "Break now"), "⌘B", true),
            (L("Пауза на час", "Pause for an hour"), "⌘P", true),
            ("✓" + L("Открывать при входе", "Open at login"), "", true),
            ("-", "", false),
            (L("Выйти", "Quit"), "⌘Q", true),
        ]
        let wdt: CGFloat = 290, rowH: CGFloat = 24, sepH: CGFloat = 11
        let height = items.reduce(10) { $0 + ($1.0 == "-" ? sepH : rowH) }
        let menu = NSVisualEffectView(frame: NSRect(x: size.width - 452, y: size.height - 30 - height, width: wdt, height: height))
        menu.material = .menu
        menu.blendingMode = .withinWindow
        menu.state = .active
        menu.wantsLayer = true
        menu.layer?.cornerRadius = 10
        menu.layer?.borderWidth = 0.5
        menu.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor

        var y = height - 5
        for (text, key, enabled) in items {
            if text == "-" {
                y -= sepH
                let line = NSView(frame: NSRect(x: 14, y: y + sepH / 2, width: wdt - 28, height: 1))
                line.wantsLayer = true; line.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.15).cgColor
                menu.addSubview(line)
                continue
            }
            y -= rowH
            let checked = text.hasPrefix("✓")
            let title = checked ? String(text.dropFirst()) : text
            let color: NSColor = enabled ? .labelColor : .secondaryLabelColor
            if checked {
                let c = NSTextField(labelWithString: "✓"); c.font = .systemFont(ofSize: 13, weight: .semibold)
                c.textColor = color; c.frame = NSRect(x: 9, y: y + 3, width: 14, height: 17); menu.addSubview(c)
            }
            let t = NSTextField(labelWithString: title); t.font = .menuFont(ofSize: 13.5); t.textColor = color
            t.frame = NSRect(x: 26, y: y + 3, width: wdt - 80, height: 18); menu.addSubview(t)
            if !key.isEmpty {
                let k = NSTextField(labelWithString: key); k.font = .menuFont(ofSize: 13.5); k.textColor = .secondaryLabelColor
                k.alignment = .right; k.frame = NSRect(x: wdt - 64, y: y + 3, width: 50, height: 18); menu.addSubview(k)
            }
        }
        return menu
    }

    /// Dock с настоящими иконками системных приложений.
    static func dock() -> NSView {
        let apps = ["/System/Library/CoreServices/Finder.app", "/System/Cryptexes/App/System/Applications/Safari.app",
                    "/System/Applications/Mail.app", "/System/Applications/Messages.app",
                    "/System/Applications/Calendar.app", "/System/Applications/Notes.app",
                    "/System/Applications/Photos.app", "/System/Applications/Music.app",
                    "/Applications/Xcode.app", "/System/Applications/System Settings.app"]
            .filter { FileManager.default.fileExists(atPath: $0) }
        let icon: CGFloat = 54, gap: CGFloat = 6, pad: CGFloat = 8
        let wdt = CGFloat(apps.count) * (icon + gap) - gap + pad * 2
        let d = NSVisualEffectView(frame: NSRect(x: (size.width - wdt) / 2, y: 6, width: wdt, height: icon + pad * 2))
        d.material = .hudWindow
        d.blendingMode = .withinWindow
        d.state = .active
        d.wantsLayer = true
        d.layer?.cornerRadius = 20
        d.layer?.borderWidth = 0.5
        d.layer?.borderColor = NSColor.white.withAlphaComponent(0.25).cgColor
        for (i, path) in apps.enumerated() {
            let v = NSImageView(frame: NSRect(x: pad + CGFloat(i) * (icon + gap), y: pad, width: icon, height: icon))
            v.image = NSWorkspace.shared.icon(forFile: path)
            v.imageScaling = .scaleProportionallyUpOrDown
            d.addSubview(v)
        }
        return d
    }
}
