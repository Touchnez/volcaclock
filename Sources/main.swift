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
    private var lastBeatBucket: Int?
    private var blinkReset: DispatchWorkItem?
    private var shownSignature = ""

    private let offsets = [-20, -15, -10, -5, 0, 5, 10, 15, 20]

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Empeche macOS de mettre l'app en veille (App Nap), ce qui degraderait la clock.
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
            reason: "Emission de la MIDI clock")

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        if let data = defaults.data(forKey: "control") {
            control = try? JSONDecoder().decode(MidiControl.self, from: data)
        }
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

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }

    // MARK: Interface

    private func setEngineState(_ state: ClockEngine.State) {
        engineState = state
        // Le clignotement n'a lieu que lorsque le Volca tourne : on n'anime pas
        // le picto (ni ne reveille un timer rapide) quand il n'y a rien a marquer.
        if state == .running {
            startBlink()
        } else {
            stopBlink()
        }
        updateIcon()
    }

    private func refreshTempo() {
        engine.status { [weak self] tempo, peers in
            self?.currentTempo = tempo
            self?.currentPeers = peers
            self?.updateIcon()
        }
    }

    private func startBlink() {
        guard blinkTimer == nil else { return }
        lastBeatBucket = nil
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
        lastBeatBucket = nil
    }

    private func blinkTick() {
        engine.beatPhase { [weak self] beat, tempo in
            guard let self else { return }
            self.currentTempo = tempo
            guard tempo > 0 else { self.updateIcon(); return }
            // Une tranche = 8 battues ; on marque chaque passage a la tranche suivante.
            let bucket = Int((beat / 8.0).rounded(.down))
            if let last = self.lastBeatBucket, bucket > last {
                self.flash()
            }
            self.lastBeatBucket = bucket
            self.updateIcon()
        }
    }

    // Marque le passage a chaque tranche de 8 battues par une breve pulsation
    // d'opacite du picto. On ne redessine pas l'image (qui ne change qu'avec le BPM).
    private func flash() {
        statusItem.button?.alphaValue = 0.3
        blinkReset?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.statusItem.button?.alphaValue = 1.0
        }
        blinkReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func updateIcon() {
        // On affiche le BPM seulement quand il y a un vrai pair Link (djay connecte) :
        // le tempo est alors reel. Sans pair, le tempo ne veut rien dire, donc on
        // reste en idle (mini-metronome seul). Tempo affiche avec un chiffre apres la virgule.
        let label: String? = (currentPeers > 0 && currentTempo > 0)
            ? String(format: "%.1f", currentTempo) : nil
        // On ne redessine que si l'apparence change vraiment, pour eviter de
        // reconstruire l'image a chaque reveil du timer.
        let signature = "\(label ?? "idle")|\(learning)"
        guard signature != shownSignature else { return }
        shownSignature = signature

        statusItem.button?.image = MenuIcon.image(label: label, learning: learning)
        statusItem.button?.title = ""
    }

    private func stateLabel() -> String {
        if learning { return NSLocalizedString("En attente d'un appui sur le bouton", comment: "") }
        switch engineState {
        case .stopped: return NSLocalizedString("Volca : arret", comment: "")
        case .armed: return NSLocalizedString("Volca : arme, depart au prochain temps 1", comment: "")
        case .running: return NSLocalizedString("Volca : en marche", comment: "")
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

        let linkInfo = item(NSLocalizedString("Link : lecture...", comment: ""), nil)
        menu.addItem(linkInfo)
        engine.status { tempo, peers in
            linkInfo.title = peers == 0
                ? NSLocalizedString("Link : aucun pair (active Link dans djay)", comment: "")
                : String(format: NSLocalizedString("Link : %.1f BPM, %d pair(s)", comment: "tempo, nombre de pairs"), tempo, peers)
        }
        menu.addItem(item(stateLabel(), nil))
        menu.addItem(.separator())

        menu.addItem(item(NSLocalizedString("Demarrer / Arreter", comment: ""), #selector(toggleFromMenu(_:))))
        menu.addItem(.separator())

        // Sortie MIDI
        let outItem = NSMenuItem(title: NSLocalizedString("Sortie MIDI", comment: ""), action: nil, keyEquivalent: "")
        let outMenu = NSMenu()
        let savedID = defaults.integer(forKey: "destinationID")
        let destinations = MidiIO.destinations()
        if destinations.isEmpty {
            outMenu.addItem(item(NSLocalizedString("Aucun port MIDI detecte", comment: ""), nil))
        }
        for dest in destinations {
            let d = item(dest.name, #selector(chooseDestination(_:)))
            d.representedObject = NSNumber(value: dest.id)
            d.state = Int(dest.id) == savedID ? .on : .off
            outMenu.addItem(d)
        }
        outItem.submenu = outMenu
        menu.addItem(outItem)

        // Bouton
        let controlLabel = control?.label ?? NSLocalizedString("aucun", comment: "aucun bouton appris")
        menu.addItem(item(String(format: NSLocalizedString("Bouton : %@", comment: "bouton appris"), controlLabel), nil))
        menu.addItem(item(learning ? NSLocalizedString("Annuler l'apprentissage", comment: "") : NSLocalizedString("Apprendre le bouton...", comment: ""), #selector(startLearning(_:))))

        // Decalage
        let offsetItem = NSMenuItem(title: NSLocalizedString("Decalage", comment: "decalage de latence"), action: nil, keyEquivalent: "")
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

        menu.addItem(.separator())
        menu.addItem(item(NSLocalizedString("Quitter VolcaClock", comment: ""), #selector(quit(_:)), key: "q"))
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
