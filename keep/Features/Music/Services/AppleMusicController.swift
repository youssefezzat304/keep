import AppKit

/// Serial, off-main-actor Apple events. Only the Music playback scripting group is used.
/// No scripts, credentials, catalog writes, or system output-volume changes.
actor AppleMusicController: AppleMusicControlling {
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot {
        try Task.checkCancellation()
        switch command {
        case .play: _ = try send(eventClass: "hook", eventID: "Play", timeout: 30)
        case .pause:
            _ = try send(eventClass: "hook", eventID: "Paus", timeout: 5)
            return AppleMusicSnapshot(state: .paused, title: nil, artist: nil)
        case .next: _ = try send(eventClass: "hook", eventID: "Next")
        case .previous: _ = try send(eventClass: "hook", eventID: "Prev")
        case .volume(let level):
            _ = try send(eventClass: "core", eventID: "setd", object: property("pVol"),
                         value: NSAppleEventDescriptor(int32: Int32(min(100, max(0, level)))), timeout: 30)
            return AppleMusicSnapshot(state: .stopped, title: nil, artist: nil)
        case .status: break
        }
        try Task.checkCancellation()
        let stateCode = try get(property("pPlS")).enumCodeValue
        let state: AppleMusicSnapshot.State = stateCode == code("kPSP") ? .playing : stateCode == code("kPSp") ? .paused : .stopped
        // Stopped Music may have no current track. Do not ask for an absent object.
        guard state != .stopped else { return AppleMusicSnapshot(state: state, title: nil, artist: nil) }
        let track = try property("pTrk")
        let title = try get(property("pnam", container: track)).stringValue
        let artist = try get(property("pArt", container: track)).stringValue
        return AppleMusicSnapshot(state: state, title: title, artist: artist)
    }

    private func get(_ object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let reply = try send(eventClass: "core", eventID: "getd", object: object)
        guard let result = reply.paramDescriptor(forKeyword: code("----")) else { throw MusicFailure.appleMusicConnection }
        return result
    }

    private func property(_ name: String, container: NSAppleEventDescriptor = .null()) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code("prop")), forKeyword: code("want"))
        record.setDescriptor(container, forKeyword: code("from"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code("prop")), forKeyword: code("form"))
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(name)), forKeyword: code("seld"))
        guard let object = record.coerce(toDescriptorType: code("obj ")) else { throw MusicFailure.appleMusicConnection }
        return object
    }

    private func send(eventClass: String, eventID: String, object: NSAppleEventDescriptor? = nil,
                      value: NSAppleEventDescriptor? = nil, timeout: TimeInterval = 10) throws -> NSAppleEventDescriptor {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Music")
        let event = NSAppleEventDescriptor(eventClass: code(eventClass), eventID: code(eventID),
            targetDescriptor: target, returnID: -1, transactionID: 0)
        if let object { event.setParam(object, forKeyword: code("----")) }
        if let value { event.setParam(value, forKeyword: code("data")) }
        do {
            let reply = try event.sendEvent(options: [.waitForReply, .canInteract], timeout: timeout)
            let error = reply.paramDescriptor(forKeyword: code("errn"))?.int32Value ?? 0
            if error != 0 { throw failure(for: Int(error)) }
            return reply
        } catch let error as MusicFailure { throw error }
        catch { throw failure(for: (error as NSError).code) }
    }

    private func failure(for code: Int) -> MusicFailure {
        NSLog("Keep: Music automation failed (%ld)", code)
        return code == -1743 ? .appleMusicPermission : .appleMusicConnection
    }

    private func code(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
