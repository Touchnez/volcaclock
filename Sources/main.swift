import AppKit
import CoreMIDI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let midi = MidiIO()
    private lazy var engine = ClockEngine(midi: midi)
    private var statusItem: NSStatusItem!
    private var activity: NSObjectProtocol?
    private let defaults = UserDefaults.standard

    private var engineState: ClockEngine.State = .stopped
    private var learning = false
    private var control: MidiControl?
    private var lastPress = Date.distantPast

    // Affichage du picto : tempo courant, nombre de pairs Link, clignotement.
    private var currentTempo: Double = 0
    private var currentPeers = 0
    private var bpmTimer: Timer?
    private var blinkTimer: Timer?
    private var scheduledBeatIndex: Int?
    private var blinkReset: DispatchWorkItem?
    private var shownSignature = ""
    private var currentLabel: String?
    private var normalImage: NSImage?
    private var beatImage: NSImage?   // image avec le mini-metronome masque (clignotement du battement)

    private let offsets = [-20, -15, -10, -5, 0, 5, 10, 15, 20]
    // Longueur du cycle de mesure, en battues (le flash fort y tombe une fois). Reglable.
    private let measureChoices = [2, 4, 8, 16]
    private var measureBeats = 8
    // Temps (0 a measureBeats-1) qui porte le flash de mesure. La base suit la grille
    // de djay via la phase Link ; ce decalage n'est qu'une correction optionnelle
    // (choix de la barre, ou recalage si le downbeat de djay ne colle pas a l'oreille).
    private var downbeatOffset = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Empeche macOS de mettre l'app en veille (App Nap), ce qui degraderait la clock.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Sending MIDI clock")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if let data = defaults.data(forKey: "control") {
            control = try? JSONDecoder().decode(MidiControl.self, from: data)
        }
        if let m = defaults.object(forKey: "measureBeats") as? Int, measureChoices.contains(m) {
            measureBeats = m
        }
        downbeatOffset = (defaults.object(forKey: "downbeatOffset") as? Int).map { (($0 % measureBeats) + measureBeats) % measureBeats } ?? 0
        midi.setFilter(control: control, learning: learning)

        engine.onStateChange = { [weak self] state in
            self?.setEngineState(state)
        }
        midi.onChannelMessage = { [weak self] status, d1, d2 in
            DispatchQueue.main.async {
                self?.handleChannelMessage(status, d1, d2)
            }
        }
        midi.onSetupChanged = { [weak self] in
            self?.restoreDestination()
        }

        engine.setOffset(ms: defaults.integer(forKey: "offsetMs"))
        restoreDestination()
        engine.start()

        // Rafraichit le tempo affiche dans le picto, une fois par seconde.
        let bpm = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.refreshTempo() }
        RunLoop.main.add(bpm, forMode: .common)
        bpmTimer = bpm
        refreshTempo()
        updateIcon()
    }

    func applicationWillTerminate(_ notification: Notification) {
        engine.shutdown()
    }

    // MARK: Sortie MIDI

    private func restoreDestination() {
        let saved = Int32(truncatingIfNeeded: defaults.integer(forKey: "destinationID"))
        if saved != 0, let dest = MidiIO.destinations().first(where: { $0.id == saved }) {
            engine.setDestination(dest.ref)
        } else {
            engine.setDestination(0)
        }
    }

    @objc private func chooseDestination(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? NSNumber else { return }
        defaults.set(id.intValue, forKey: "destinationID")
        restoreDestination()
    }

    // MARK: Bouton du Launch Control

    private func handleChannelMessage(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) {
        let kind = status & 0xF0
        // Appui seulement : note on avec velocite, ou CC avec valeur non nulle.
        guard kind == 0x90 || kind == 0xB0, d2 > 0 else { return }
        let received = MidiControl(kind: kind, channel: status & 0x0F, number: d1)

        if learning {
            learning = false
            control = received
            if let data = try? JSONEncoder().encode(received) {
                defaults.set(data, forKey: "control")
            }
            midi.setFilter(control: control, learning: false)
            updateIcon()
            return
        }

        guard received == control else { return }
        let now = Date()
        guard now.timeIntervalSince(lastPress) > 0.15 else { return }
        lastPress = now
        engine.toggle()
    }

    @objc private func startLearning(_ sender: NSMenuItem) {
        learning.toggle()
        midi.setFilter(control: control, learning: learning)
        updateIcon()
    }

    @objc private func toggleFromMenu(_ sender: NSMenuItem) {
        engine.toggle()
    }

    @objc private func chooseOffset(_ sender: NSMenuItem) {
        defaults.set(sender.tag, forKey: "offsetMs")
        engine.setOffset(ms: sender.tag)
    }

    @objc private func chooseDownbeat(_ sender: NSMenuItem) {
        downbeatOffset = ((sender.tag % measureBeats) + measureBeats) % measureBeats
        defaults.set(downbeatOffset, forKey: "downbeatOffset")
    }

    @objc private func chooseMeasure(_ sender: NSMenuItem) {
        measureBeats = max(1, sender.tag)
        defaults.set(measureBeats, forKey: "measureBeats")
        downbeatOffset = ((downbeatOffset % measureBeats) + measureBeats) % measureBeats
        defaults.set(downbeatOffset, forKey: "downbeatOffset")
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    // MARK: Interface

    private func setEngineState(_ state: ClockEngine.State) {
        engineState = state
        updateIcon()
    }

    private func refreshTempo() {
        engine.status { [weak self] tempo, peers in
            guard let self else { return }
            self.currentTempo = tempo
            self.currentPeers = peers
            self.updateBlinkActive()
            self.updateIcon()
        }
    }

    // Le clignotement tourne des qu'il y a un vrai tempo Link, meme a l'arret ;
    // il s'arrete quand il n'y a plus de pair (rien a marquer).
    private func updateBlinkActive() {
        if currentPeers > 0 && currentTempo > 0 {
            startBlink()
        } else {
            stopBlink()
        }
    }

    private func startBlink() {
        guard blinkTimer == nil else { return }
        scheduledBeatIndex = nil
        // Sondage regulier : il ne declenche pas la pulsation, il programme la suivante
        // a l'instant exact du prochain temps. 50 ms suffisent largement.
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.blinkTick() }
        RunLoop.main.add(t, forMode: .common)
        blinkTimer = t
    }

    private func stopBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        blinkReset?.cancel()
        blinkReset = nil
        statusItem.button?.alphaValue = 1.0
        scheduledBeatIndex = nil
    }

    private func blinkTick() {
        engine.nextBeatSchedule { [weak self] fireNanos, beatIndex, tempo in
            guard let self else { return }
            self.currentTempo = tempo
            self.updateIcon()
            guard tempo > 0, fireNanos > 0, self.scheduledBeatIndex != beatIndex else { return }
            self.scheduledBeatIndex = beatIndex
            // Flash de mesure sur le downbeat de la phase de mesure Link (suit la grille
            // de djay), avec la correction optionnelle choisie.
            let isCycle = ((beatIndex % self.measureBeats) + self.measureBeats) % self.measureBeats == self.downbeatOffset
            // Programme la pulsation a l'instant precis du prochain temps.
            DispatchQueue.main.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: fireNanos)) { [weak self] in
                guard let self, self.blinkTimer != nil else { return }
                if isCycle {
                    self.cyclePulse(duration: 0.18)   // mesure : toute l'icone
                } else {
                    self.beatPulse(duration: 0.09)    // battement : le mini-metronome seul
                }
            }
        }
    }

    // Battement : on masque brievement le mini-metronome (le reste de l'icone ne bouge pas).
    private func beatPulse(duration: TimeInterval) {
        guard let beat = beatImage else { return }
        statusItem.button?.alphaValue = 1.0
        statusItem.button?.image = beat
        blinkReset?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.statusItem.button?.image = self?.normalImage
        }
        blinkReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    // Mesure : toute l'icone clignote par une baisse d'opacite.
    private func cyclePulse(duration: TimeInterval) {
        statusItem.button?.image = normalImage
        statusItem.button?.alphaValue = 0.12
        blinkReset?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.statusItem.button?.alphaValue = 1.0
        }
        blinkReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func updateIcon() {
        // On affiche le BPM seulement quand il y a un vrai pair Link (djay connecte) :
        // le tempo est alors reel. Sans pair, le tempo ne veut rien dire, donc on
        // reste en idle (mini-metronome seul). Tempo affiche avec un chiffre apres la virgule.
        let label: String? = (currentPeers > 0 && currentTempo > 0)
            ? String(format: "%.1f", currentTempo) : nil
        currentLabel = label
        // On ne redessine que si l'apparence change vraiment, pour eviter de
        // reconstruire l'image a chaque reveil du timer.
        let signature = "\(label ?? "idle")|\(learning)"
        guard signature != shownSignature else { return }
        shownSignature = signature

        let img = MenuIcon.image(label: label, learning: learning)
        normalImage = img
        beatImage = learning ? img : MenuIcon.image(label: label, learning: false, metronomeHidden: true)
        statusItem.button?.image = img
        statusItem.button?.title = ""
        // La largeur variable ne suit pas toujours une image qui change de largeur :
        // on fixe explicitement la longueur a celle de l'image pour que le nombre
        // complet reste visible (y compris au-dela de 99.9) et se mette a jour.
        statusItem.length = img.size.width
    }

    private func stateLabel() -> String {
        if learning { return "Waiting for a button press" }
        switch engineState {
        case .stopped: return "Volca: stopped"
        case .armed: return "Volca: armed, starts on next downbeat"
        case .running: return "Volca: running"
        }
    }

    private func item(_ title: String, _ action: Selector?, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        if action == nil { i.isEnabled = false }
        return i
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let linkInfo = item("Link: reading...", nil)
        menu.addItem(linkInfo)
        engine.status { tempo, peers in
            linkInfo.title = peers == 0
                ? "Link: no peer (enable Link in djay)"
                : String(format: "Link: %.1f BPM, %d peer(s)", tempo, peers)
        }
        menu.addItem(item(stateLabel(), nil))
        menu.addItem(.separator())

        menu.addItem(item("Start / Stop", #selector(toggleFromMenu(_:))))
        menu.addItem(.separator())

        // MIDI output
        let outItem = NSMenuItem(title: "MIDI output", action: nil, keyEquivalent: "")
        let outMenu = NSMenu()
        let savedID = defaults.integer(forKey: "destinationID")
        let destinations = MidiIO.destinations()
        if destinations.isEmpty {
            outMenu.addItem(item("No MIDI port found", nil))
        }
        for dest in destinations {
            let d = item(dest.name, #selector(chooseDestination(_:)))
            d.representedObject = NSNumber(value: dest.id)
            d.state = Int(dest.id) == savedID ? .on : .off
            outMenu.addItem(d)
        }
        outItem.submenu = outMenu
        menu.addItem(outItem)

        // Button
        menu.addItem(item("Button: " + (control?.label ?? "none"), nil))
        menu.addItem(item(learning ? "Cancel learning" : "Learn button...", #selector(startLearning(_:))))

        // Offset
        let offsetItem = NSMenuItem(title: "Offset", action: nil, keyEquivalent: "")
        let offsetMenu = NSMenu()
        let currentOffset = defaults.integer(forKey: "offsetMs")
        for ms in offsets {
            let o = item(String(format: "%+d ms", ms), #selector(chooseOffset(_:)))
            o.tag = ms
            o.state = ms == currentOffset ? .on : .off
            offsetMenu.addItem(o)
        }
        offsetItem.submenu = offsetMenu
        menu.addItem(offsetItem)

        // Measure flash : longueur du cycle (en battues) entre deux flashs de l'icone entiere.
        let measItem = NSMenuItem(title: "Measure flash", action: nil, keyEquivalent: "")
        let measMenu = NSMenu()
        for n in measureChoices {
            let m = item("\(n) beats", #selector(chooseMeasure(_:)))
            m.tag = n
            m.state = n == measureBeats ? .on : .off
            measMenu.addItem(m)
        }
        measItem.submenu = measMenu
        menu.addItem(measItem)

        // Downbeat : correction optionnelle du temps de la mesure qui porte le flash
        // (la base suit deja la grille de djay via la phase Link).
        let downItem = NSMenuItem(title: "Downbeat", action: nil, keyEquivalent: "")
        let downMenu = NSMenu()
        for n in 0..<measureBeats {
            let d = item("Beat \(n + 1)", #selector(chooseDownbeat(_:)))
            d.tag = n
            d.state = n == downbeatOffset ? .on : .off
            downMenu.addItem(d)
        }
        downItem.submenu = downMenu
        menu.addItem(downItem)

        menu.addItem(.separator())
        menu.addItem(item("Quit VolcaClock", #selector(quit(_:)), key: "q"))
    }
}

// Le code de demarrage s'execute sur le thread principal ; on le declare explicitement
// pour que le compilateur accepte la creation du delegue (isole sur le thread principal).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
