import CoreAudio
import Foundation
import OSLog

nonisolated struct AudioOutputRoute: Equatable, Sendable {
    let device: AudioObjectID
    var source: UInt32?
    var jackConnected: UInt32?
    var alive: UInt32?
}

nonisolated protocol AudioOutputObserving: AnyObject, Sendable {
    func start(changed: @escaping @Sendable () -> Void)
    func stop()
}

/// Core Audio reads and listeners stay on a serial queue; no route or volume is changed.
nonisolated final class AudioOutputMonitor: AudioOutputObserving, @unchecked Sendable {
    private struct Listener {
        let object: AudioObjectID
        var address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }
    private let queue = DispatchQueue(label: "com.youssef.keep.audio-output")
    private var listeners: [Listener] = []
    private var route: AudioOutputRoute?
    private var changed: (@Sendable () -> Void)?
    private let logger = Logger(subsystem: "com.youssef.keep", category: "Audio output")

    func start(changed: @escaping @Sendable () -> Void) {
        queue.async { [self] in
            removeListeners()
            self.changed = changed
            route = Self.readRoute()
            listen(object: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice,
                   scope: kAudioObjectPropertyScopeGlobal)
            listenToDevice()
            refresh()
        }
    }
    func stop() {
        queue.async { [self] in removeListeners(); route = nil; changed = nil }
    }
    private func listenToDevice() {
        guard let route, route.device != kAudioObjectUnknown else { return }
        for selector in [kAudioDevicePropertyDataSource, kAudioDevicePropertyJackIsConnected] {
            listen(object: route.device, selector: selector, scope: kAudioDevicePropertyScopeOutput)
        }
        listen(object: route.device, selector: kAudioDevicePropertyDeviceIsAlive, scope: kAudioObjectPropertyScopeGlobal)
    }
    private func listen(object: AudioObjectID, selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope) {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(object, &address) else { return }
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.refresh() }
        let status = AudioObjectAddPropertyListenerBlock(object, &address, queue, block)
        if status == noErr { listeners.append(Listener(object: object, address: address, block: block)) }
        else { logger.error("Output listener registration failed (\(status))") }
    }
    private func refresh() {
        guard let old = route, changed != nil else { return }
        let next = Self.readRoute()
        guard old != next else { return }
        route = next
        if old.device != next.device {
            removeListeners(keepingSystem: true)
            listenToDevice()
        }
        changed?()
    }
    private func removeListeners(keepingSystem: Bool = false) {
        for var listener in listeners where !keepingSystem || listener.object != kAudioObjectSystemObject {
            let status = AudioObjectRemovePropertyListenerBlock(listener.object, &listener.address, queue, listener.block)
            if status != noErr { logger.error("Output listener removal failed (\(status))") }
        }
        if keepingSystem { listeners.removeAll { $0.object != kAudioObjectSystemObject } }
        else { listeners.removeAll() }
    }
    static func readRoute() -> AudioOutputRoute {
        let device = read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice,
                          kAudioObjectPropertyScopeGlobal) ?? AudioObjectID(kAudioObjectUnknown)
        return AudioOutputRoute(device: device,
            source: read(device, kAudioDevicePropertyDataSource, kAudioDevicePropertyScopeOutput),
            jackConnected: read(device, kAudioDevicePropertyJackIsConnected, kAudioDevicePropertyScopeOutput),
            alive: read(device, kAudioDevicePropertyDeviceIsAlive, kAudioObjectPropertyScopeGlobal))
    }
    private static func read(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope) -> UInt32? {
        guard object != kAudioObjectUnknown else { return nil }
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectHasProperty(object, &address) else { return nil }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
    deinit {
        for var listener in listeners {
            let status = AudioObjectRemovePropertyListenerBlock(listener.object, &listener.address, queue, listener.block)
            if status != noErr { logger.error("Output listener removal failed (\(status))") }
        }
    }
}
