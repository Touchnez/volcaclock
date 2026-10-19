import CoreMIDI
import Darwin
import Foundation

/// Lit la timeline Ableton Link et emet une MIDI clock (24 impulsions par temps) horodatee.
/// Tout le travail se fait sur une file dediee, reveillee toutes les 10 ms.
final class ClockEngine {
    enum State {
        case stopped
        case armed   // attend le prochain temps 1 pour envoyer Start
        case running
    }

    private let queue = DispatchQueue(label: "volcaclock.engine", qos: .userInteractive)
    private let midi: MidiIO
    private var timer: DispatchSourceTimer?

    private let quantum = 4.0              // une mesure = 4 temps
    private let ticksPerBeat: Int64 = 24   // norme MIDI clock
    private let lookaheadMicros: Int64 = 40_000

    // Variables lues et ecrites uniquement sur `queue`.
    private var state: State = .stopped
    private var destination: MIDIEndpointRef = 0
    private var offsetMicros: Int64 = 0
    private var nextTick: Int64?
    private var lastTempo: Double = 0

    private var timebaseNumer: UInt64 = 1
    private var timebaseDenom: UInt64 = 1

    /// Appele sur le thread principal a chaque changement d'etat.
    var onStateChange: (@MainActor (State) -> Void)?

    init(midi: MidiIO) {
        self.midi = midi
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        timebaseNumer = UInt64(tb.numer)
        timebaseDenom = UInt64(tb.denom)
        lb_create(120)
        lb_enable(1)
    }

    func start() {
        let t = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        t.schedule(deadline: .now(), repeating: .milliseconds(10), leeway: .milliseconds(1))
        t.setEventHandler { [weak self] in self?.step() }
        t.resume()
        timer = t
    }

    func setDestination(_ dest: MIDIEndpointRef) {
        queue.async {
            if self.state == .running, self.destination != 0, self.destination != dest {
                self.midi.sendRealtime(0xFC, to: self.destination, at: 0)
                self.setState(.stopped)
            }
            self.destination = dest
            self.nextTick = nil
        }
    }

    func setOffset(ms: Int) {
        queue.async {
            self.offsetMicros = Int64(ms) * 1000
        }
    }

    /// Bouton Start/Stop : arret -> arme -> (Start au temps 1) -> en marche -> arret.
    func toggle() {
        queue.async {
            switch self.state {
            case .stopped:
                self.setState(.armed)
            case .armed:
                self.setState(.stopped)
            case .running:
                if self.destination != 0 {
                    self.midi.sendRealtime(0xFC, to: self.destination, at: 0)
                }
                self.setState(.stopped)
            }
        }
    }

    /// Envoie Stop avant de quitter, si le Volca tourne.
    func shutdown() {
        queue.sync {
            if self.state == .running, self.destination != 0 {
                self.midi.sendRealtime(0xFC, to: self.destination, at: 0)
            }
            self.timer?.cancel()
        }
    }

    func status(_ completion: @escaping @MainActor (Double, Int) -> Void) {
        queue.async {
            let tempo = self.lastTempo
            let peers = Int(lb_num_peers())
            DispatchQueue.main.async {
                completion(tempo, peers)
            }
        }
    }

    /// Programme le prochain temps : renvoie l'instant d'horloge machine (en nanosecondes,
    /// base DispatchTime.uptimeNanoseconds) du prochain temps, son index, et le tempo.
    /// Calcule sur la timeline Link pour un clignotement cale au temps, sans latence de
    /// sondage. Le choix mesure/battement est fait par l'appelant (decalage reglable).
    func nextBeatSchedule(_ completion: @escaping @MainActor (_ fireNanos: UInt64, _ beatIndex: Int, _ tempo: Double) -> Void) {
        queue.async {
            let tempo = self.lastTempo
            var nowMicros: Int64 = 0
            var nowHost: UInt64 = 0
            lb_sample(&nowMicros, &nowHost)
            let beat = lb_beat_at(nowMicros, self.quantum)
            guard tempo > 0, beat.isFinite else {
                DispatchQueue.main.async { completion(0, 0, tempo) }
                return
            }
            let nextBeatIndex = Int(beat.rounded(.down)) + 1
            let beatMicros = lb_time_at_beat(Double(nextBeatIndex), self.quantum)
            let dt = beatMicros - nowMicros
            let fireHost = dt > 0 ? nowHost &+ self.microsToHost(dt) : nowHost
            let fireNanos = fireHost * self.timebaseNumer / self.timebaseDenom
            DispatchQueue.main.async { completion(fireNanos, nextBeatIndex, tempo) }
        }
    }

    private func setState(_ s: State) {
        state = s
        let callback = onStateChange
        DispatchQueue.main.async {
            callback?(s)
        }
    }

    private func microsToHost(_ us: Int64) -> UInt64 {
        UInt64(us) * 1000 * timebaseDenom / timebaseNumer
    }

    // Garde-fou : nombre maximum d'impulsions emises en une passe. L'horizon de
    // 40 ms ne couvre que quelques impulsions, meme a tempo tres eleve ; au-dela,
    // c'est que la timeline Link est aberrante, et on evite une boucle sans fin.
    private let maxTicksPerStep = 64

    private func step() {
        lb_capture()
        let tempo = lb_tempo()

        // Un tempo nul, infini ou NaN signifie une session Link invalide : on ne
        // calcule rien ce tour-ci et on se recalera a la prochaine passe valable.
        guard tempo.isFinite, tempo > 0 else {
            nextTick = nil
            return
        }
        lastTempo = tempo

        guard destination != 0 else {
            nextTick = nil
            return
        }

        var nowMicros: Int64 = 0
        var nowHost: UInt64 = 0
        lb_sample(&nowMicros, &nowHost)

        // Position (en impulsions) qui doit sortir maintenant, decalage compris.
        let currentTick = lb_beat_at(nowMicros - offsetMicros, quantum) * Double(ticksPerBeat)
        guard currentTick.isFinite else {
            nextTick = nil
            return
        }

        // Premier passage, ou saut de timeline (nouvelle session Link) : on se recale.
        if let n = nextTick, abs(Double(n) - currentTick) < 48 {
            // on poursuit la sequence
        } else {
            nextTick = Int64(currentTick.rounded(.up))
        }

        guard var k = nextTick else { return }
        let horizon = nowMicros + lookaheadMicros
        let ticksPerBar = Int64(quantum) * ticksPerBeat

        var emitted = 0
        while emitted < maxTicksPerStep {
            let t = lb_time_at_beat(Double(k) / Double(ticksPerBeat), quantum) + offsetMicros
            if t > horizon { break }
            let host: UInt64 = t > nowMicros ? nowHost + microsToHost(t - nowMicros) : 0

            if state == .armed && k % ticksPerBar == 0 {
                midi.sendRealtime(0xFA, to: destination, at: host)
                setState(.running)
            }
            midi.sendRealtime(0xF8, to: destination, at: host)
            k += 1
            emitted += 1
        }
        nextTick = k
    }
}
