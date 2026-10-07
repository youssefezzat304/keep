import AppKit
import CoreServices

/// Serial, off-main-actor Apple events using playback and read-only library access.
/// No scripts, credentials, catalog writes, or system output-volume changes.
actor AppleMusicController: AppleMusicControlling {
    private var artworkID: String?
    private var cachedArtwork: Data?
    private var artworkAttempt = Date.distantPast
    private var artworkAttempts = 0

    /// Probe the actual scoped read events. Only an explicit request may prompt.
    func access(requestPermission: Bool) async -> AppleMusicAccess {
        do {
            try Task.checkCancellation()
            _ = try sendRaw(eventClass: "core", eventID: "getd", object: property("pPlS"),
                requestPermission: requestPermission)
            try Task.checkCancellation()
            _ = try sendRaw(eventClass: "core", eventID: "cnte", object: libraryObject(),
                parameters: ["kocl": NSAppleEventDescriptor(typeCode: code("cTrk"))], requestPermission: requestPermission)
            return .allowed
        } catch let error as EventFailure {
            return error.code == -1744 ? .notRequested : error.code == -1743 ? .denied : .failed
        } catch { return .failed }
    }
    func perform(_ command: AppleMusicCommand) async throws -> AppleMusicSnapshot {
        try Task.checkCancellation()
        switch command {
        case .play: _ = try send(eventClass: "hook", eventID: "Play", timeout: 30)
        case .pause:
            _ = try send(eventClass: "hook", eventID: "Paus", timeout: 5)
            return AppleMusicSnapshot(state: .paused, title: nil, artist: nil)
        case .next: _ = try send(eventClass: "hook", eventID: "Next")
        case .previous: _ = try send(eventClass: "hook", eventID: "Prev")
        case .playItem(let item): _ = try send(eventClass: "hook", eventID: "Play", object: itemObject(item), timeout: 30)
        case .seek(let seconds):
            guard seconds.isFinite, seconds >= 0 else { throw MusicFailure.appleMusicConnection }
            _ = try send(eventClass: "core", eventID: "setd", object: property("pPos"), value: NSAppleEventDescriptor(double: seconds))
        case .shuffle(let enabled):
            _ = try send(eventClass: "core", eventID: "setd", object: property("pShE"), value: NSAppleEventDescriptor(boolean: enabled))
        case .repeatMode(let mode):
            let value = mode == .off ? "kRpO" : mode == .one ? "kRp1" : "kAll"
            _ = try send(eventClass: "core", eventID: "setd", object: property("pRpt"), value: NSAppleEventDescriptor(enumCode: code(value)))
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
        let id = try get(property("pPIS", container: track)).stringValue
        let duration = try get(property("pDur", container: track)).doubleValue
        let position = try get(property("pPos")).doubleValue
        let shuffled = try get(property("pShE")).booleanValue
        let repeatCode = try get(property("pRpt")).enumCodeValue
        if artworkID != id {
            artworkID = id
            cachedArtwork = nil
            artworkAttempt = .distantPast
            artworkAttempts = 0
        }
        // A cloud track can begin playing before Music has loaded its cover.
        if cachedArtwork == nil, Date().timeIntervalSince(artworkAttempt) >= (artworkAttempts < 3 ? 2 : 15) {
            artworkAttempt = Date()
            artworkAttempts += 1
            do {
                if try count("cArt", in: track) > 0 {
                    let artwork = try element("cArt", container: track, selector: NSAppleEventDescriptor(int32: 1))
                    let data = try get(property("pRaw", container: artwork)).data
                    if !data.isEmpty, data.count <= 12 * 1024 * 1024 { cachedArtwork = data }
                }
            } catch {
                // Retry delayed artwork without interrupting audio or repeatedly logging.
                if artworkAttempts == 1 { NSLog("Keep: Music artwork unavailable (%@)", String(describing: error)) }
            }
        }
        return AppleMusicSnapshot(state: state, title: title, artist: artist, trackID: id, artwork: cachedArtwork,
            position: position.isFinite ? max(0, position) : 0, duration: duration.isFinite ? max(0, duration) : 0,
            shuffled: shuffled, repeatMode: repeatCode == code("kRp1") ? .one : repeatCode == code("kAll") ? .all : .off)
    }

    func library(_ request: AppleMusicLibraryRequest) async throws -> AppleMusicLibraryPage {
        try Task.checkCancellation()
        guard request.offset >= 0, request.offset <= 1_000_000 else { throw MusicFailure.appleMusicConnection }
        let query = String(request.query.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        let library = try libraryObject()
        let container = try request.playlist.map(itemObject) ?? library
        let kind = request.playlist == nil ? request.kind : .songs
        let type = kind == .songs ? "cTrk" : "cUsP"
        let source = kind == .songs ? container : try sourceObject()
        let references: NSAppleEventDescriptor
        let total: Int
        var start = request.offset
        if !query.isEmpty {
            // Music's search command rejects read-only sandbox access. Read metadata
            // instead; return only a page of matches and never request library writes.
            guard try count(type, in: source) > 0 else { return AppleMusicLibraryPage(items: [], hasMore: false) }
            let all = try allElements(type, container: source)
            let names = try get(property("pnam", container: all))
            try Task.checkCancellation()
            let ids = try get(property("ID  ", container: all))
            let artists = kind == .songs ? try get(property("pArt", container: all)) : nil
            try Task.checkCancellation()
            let albums = kind == .songs ? try get(property("pAlb", container: all)) : nil
            var matches: [AppleMusicItem] = []
            var matched = 0
            for index in 0..<names.numberOfItems {
                try Task.checkCancellation()
                guard let title = names.atIndex(index + 1)?.stringValue,
                      let id = ids.atIndex(index + 1)?.int32Value else { throw MusicFailure.appleMusicConnection }
                let artist = artists?.atIndex(index + 1)?.stringValue ?? ""
                let album = albums?.atIndex(index + 1)?.stringValue ?? ""
                guard [title, artist, album].contains(where: { $0.localizedStandardContains(query) }) else { continue }
                if matched >= start {
                    if matches.count == AppleMusicLibraryRequest.pageSize {
                        return AppleMusicLibraryPage(items: matches, hasMore: true)
                    }
                    matches.append(AppleMusicItem(nativeID: id, kind: kind, title: title,
                        artist: kind == .songs ? artist : "Playlist", playlistID: kind == .songs ? request.playlist?.nativeID : nil))
                }
                matched += 1
            }
            return AppleMusicLibraryPage(items: matches, hasMore: false)
        } else {
            total = try count(type, in: source)
            guard start < total else { return AppleMusicLibraryPage(items: [], hasMore: false) }
            if kind == .playlists {
                // Music supports indexed playlist properties but rejects getting a playlist range.
                let list = NSAppleEventDescriptor.list()
                for index in start..<min(total, start + AppleMusicLibraryRequest.pageSize) {
                    list.insert(try element(type, container: source, selector: NSAppleEventDescriptor(int32: Int32(index + 1))), at: list.numberOfItems + 1)
                }
                references = list
            } else {
                let range = NSAppleEventDescriptor.record()
                range.setDescriptor(try element(type, container: source, selector: NSAppleEventDescriptor(int32: Int32(start + 1))), forKeyword: code("star"))
                range.setDescriptor(try element(type, container: source, selector: NSAppleEventDescriptor(int32: Int32(min(total, start + AppleMusicLibraryRequest.pageSize)))), forKeyword: code("stop"))
                guard let selector = range.coerce(toDescriptorType: code("rang")) else { throw MusicFailure.appleMusicConnection }
                references = try get(element(type, container: source, form: "rang", selector: selector))
            }
            start = 0
        }
        var items: [AppleMusicItem] = []
        for index in start..<min(references.numberOfItems, start + AppleMusicLibraryRequest.pageSize) {
            try Task.checkCancellation()
            guard let object = references.atIndex(index + 1),
                  let title = try get(property("pnam", container: object)).stringValue else { throw MusicFailure.appleMusicConnection }
            let id = try get(property("ID  ", container: object)).int32Value
            let artist = kind == .songs ? try get(property("pArt", container: object)).stringValue ?? "Unknown artist" : "Playlist"
            items.append(AppleMusicItem(nativeID: id, kind: kind, title: title, artist: artist,
                playlistID: kind == .songs ? request.playlist?.nativeID : nil))
        }
        return AppleMusicLibraryPage(items: items, hasMore: request.offset + AppleMusicLibraryRequest.pageSize < total)
    }

    private func count(_ type: String, in container: NSAppleEventDescriptor) throws -> Int {
        return Int(try result(send(eventClass: "core", eventID: "cnte", object: container,
            parameters: ["kocl": NSAppleEventDescriptor(typeCode: code(type))])).int32Value)
    }

    private func itemObject(_ item: AppleMusicItem) throws -> NSAppleEventDescriptor {
        let container: NSAppleEventDescriptor
        if item.kind == .songs {
            if let playlistID = item.playlistID {
                container = try element("cUsP", container: sourceObject(), form: "ID  ", selector: NSAppleEventDescriptor(int32: playlistID))
            } else { container = try libraryObject() }
        } else { container = try sourceObject() }
        return try element(item.kind == .songs ? "cTrk" : "cUsP", container: container,
            form: "ID  ", selector: NSAppleEventDescriptor(int32: item.nativeID))
    }

    private func libraryObject() throws -> NSAppleEventDescriptor {
        // Music exposes library playlists through a source, not as application-level elements.
        let source = try sourceObject()
        return try element("cLiP", container: source, selector: NSAppleEventDescriptor(int32: 1))
    }

    private func sourceObject() throws -> NSAppleEventDescriptor {
        try element("cSrc", selector: NSAppleEventDescriptor(int32: 1))
    }

    private func allElements(_ type: String, container: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        // Absolute ordinals have their own descriptor type; an enum is not an index.
        let ordinal = NSAppleEventDescriptor(enumCode: code("all "))
        let selector = NSAppleEventDescriptor(descriptorType: code("abso"), data: ordinal.data)
        guard let selector else { throw MusicFailure.appleMusicConnection }
        return try element(type, container: container, selector: selector)
    }

    private func element(_ type: String, container: NSAppleEventDescriptor = .null(),
                         form: String = "indx", selector: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(typeCode: code(type)), forKeyword: code("want"))
        record.setDescriptor(container, forKeyword: code("from"))
        record.setDescriptor(NSAppleEventDescriptor(enumCode: code(form)), forKeyword: code("form"))
        record.setDescriptor(selector, forKeyword: code("seld"))
        guard let object = record.coerce(toDescriptorType: code("obj ")) else { throw MusicFailure.appleMusicConnection }
        return object
    }

    private func result(_ reply: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        guard let result = reply.paramDescriptor(forKeyword: code("----")) else { throw MusicFailure.appleMusicConnection }
        return result
    }

    private func get(_ object: NSAppleEventDescriptor) throws -> NSAppleEventDescriptor {
        let reply = try send(eventClass: "core", eventID: "getd", object: object)
        return try result(reply)
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
                      value: NSAppleEventDescriptor? = nil, parameters: [String: NSAppleEventDescriptor] = [:],
                      timeout: TimeInterval = 10) throws -> NSAppleEventDescriptor {
        do {
            return try sendRaw(eventClass: eventClass, eventID: eventID, object: object,
                value: value, parameters: parameters, timeout: timeout, requestPermission: true)
        } catch let error as EventFailure { throw failure(for: error.code) }
    }

    private struct EventFailure: Error { let code: Int }

    private func sendRaw(eventClass: String, eventID: String, object: NSAppleEventDescriptor? = nil,
                         value: NSAppleEventDescriptor? = nil, parameters: [String: NSAppleEventDescriptor] = [:],
                         timeout: TimeInterval = 10, requestPermission: Bool) throws -> NSAppleEventDescriptor {
        let target = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Music")
        let event = NSAppleEventDescriptor(eventClass: code(eventClass), eventID: code(eventID),
            targetDescriptor: target, returnID: -1, transactionID: 0)
        if let object { event.setParam(object, forKeyword: code("----")) }
        if let value { event.setParam(value, forKeyword: code("data")) }
        for (key, value) in parameters { event.setParam(value, forKeyword: code(key)) }
        var options: NSAppleEventDescriptor.SendOptions = [.waitForReply, .canInteract]
        if !requestPermission { options.insert(.init(rawValue: UInt(kAEDoNotPromptForUserConsent))) }
        let reply: NSAppleEventDescriptor
        do { reply = try event.sendEvent(options: options, timeout: timeout) }
        catch { throw EventFailure(code: (error as NSError).code) }
        let error = reply.paramDescriptor(forKeyword: code("errn"))?.int32Value ?? 0
        if error != 0 { throw EventFailure(code: Int(error)) }
        return reply
    }

    private func failure(for code: Int) -> MusicFailure {
        NSLog("Keep: Music automation failed (%ld)", code)
        return code == -1743 || code == -1744 ? .appleMusicPermission : .appleMusicConnection
    }

    private func code(_ string: String) -> UInt32 {
        string.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
