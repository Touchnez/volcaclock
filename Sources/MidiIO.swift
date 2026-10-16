import CoreMIDI
import Foundation

/// Bouton appris sur le controleur : type (note 0x90 ou CC 0xB0), canal, numero.
struct MidiControl: Codable, Equatable {
    var kind: UInt8
    var channel: UInt8
    var number: UInt8

    var label: String {
        let type = kind == 0x90 ? "Note" : "CC"
        return "\(type) \(number), canal \(Int(channel) + 1)"
    }
}

struct MidiDestination {
    let id: Int32
    let name: String
    let ref: MIDIEndpointRef
}

final class MidiIO {
    private var client = MIDIClientRef()
    private var outPort = MIDIPortRef()
    private var inPort = MIDIPortRef()
    private var connectedSources: [MIDIEndpointRef] = []

    // Tampon reutilise pour l'envoi : aucune allocation par message.
    // Utilise uniquement depuis la file du moteur d'horloge.
    private let sendBuffer = UnsafeMutablePointer<MIDIEventList>.allocate(capacity: 1)

    /// Appele sur le thread CoreMIDI a chaque message de canal recu (status, data1, data2).
    var onChannelMessage: ((UInt8, UInt8, UInt8) -> Void)?
    /// Appele sur le thread principal quand un appareil MIDI est branche ou debranche.
    var onSetupChanged: (@MainActor () -> Void)?

    init() {
        MIDIClientCreateWithBlock("VolcaClock" as CFString, &client) { [weak self] notification in
            if notification.pointee.messageID == .msgSetupChanged {
                DispatchQueue.main.async {
                    self?.connectAllSources()
                    self?.onSetupChanged?()
                }
            }
        }
        MIDIOutputPortCreate(client, "VolcaClock Out" as CFString, &outPort)
        MIDIInputPortCreateWithProtocol(client, "VolcaClock In" as CFString, ._1_0, &inPort) { [weak self] listPtr, _ in
            self?.handle(listPtr)
        }
        connectAllSources()
    }

    private func handle(_ listPtr: UnsafePointer<MIDIEventList>) {
        for packetPtr in listPtr.unsafeSequence() {
            var packet = packetPtr.pointee
            let count = Int(packet.wordCount)
            let words: [UInt32] = withUnsafeBytes(of: &packet.words) { raw in
                Array(raw.bindMemory(to: UInt32.self).prefix(count))
            }
            // Seuls les messages de canal MIDI 1.0 (type UMP 2) nous interessent.
            for w in words where (w >> 28) == 0x2 {
                let status = UInt8((w >> 16) & 0xFF)
                let d1 = UInt8((w >> 8) & 0x7F)
                let d2 = UInt8(w & 0x7F)
                onChannelMessage?(status, d1, d2)
            }
        }
    }

    func connectAllSources() {
        for src in connectedSources {
            MIDIPortDisconnectSource(inPort, src)
        }
        connectedSources.removeAll()
        for i in 0..<MIDIGetNumberOfSources() {
            let src = MIDIGetSource(i)
            if MIDIPortConnectSource(inPort, src, nil) == 0 {
                connectedSources.append(src)
            }
        }
    }

    static func destinations() -> [MidiDestination] {
        (0..<MIDIGetNumberOfDestinations()).map { i in
            let ref = MIDIGetDestination(i)
            return MidiDestination(id: uniqueID(ref), name: displayName(ref), ref: ref)
        }
    }

    static func displayName(_ obj: MIDIObjectRef) -> String {
        var cf: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(obj, kMIDIPropertyDisplayName, &cf) == 0, let s = cf?.takeRetainedValue() {
            return s as String
        }
        return "Port sans nom"
    }

    static func uniqueID(_ obj: MIDIObjectRef) -> Int32 {
        var value: Int32 = 0
        MIDIObjectGetIntegerProperty(obj, kMIDIPropertyUniqueID, &value)
        return value
    }

    /// Envoie un message temps reel (clock 0xF8, start 0xFA, stop 0xFC) horodate.
    /// host = 0 signifie "tout de suite". CoreMIDI se charge de l'emettre a l'instant exact.
    func sendRealtime(_ status: UInt8, to dest: MIDIEndpointRef, at host: UInt64) {
        let packet = MIDIEventListInit(sendBuffer, ._1_0)
        var word: UInt32 = 0x1000_0000 | (UInt32(status) << 16)
        _ = MIDIEventListAdd(sendBuffer, MemoryLayout<MIDIEventList>.size, packet, MIDITimeStamp(host), 1, &word)
        MIDISendEventList(outPort, dest, sendBuffer)
    }
}
