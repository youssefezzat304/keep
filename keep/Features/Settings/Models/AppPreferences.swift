import Foundation
import Observation
import SwiftUI

enum AppAppearance: String, Codable, CaseIterable, Identifiable {
    case light, dark, system
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var colorScheme: ColorScheme? {
        switch self { case .light: .light; case .dark: .dark; case .system: nil }
    }
}

enum WallpaperSource: String, Codable, CaseIterable, Identifiable {
    case cozy, folder, audius
    var id: String { rawValue }
    var title: String {
        switch self { case .cozy: "Cozy corner"; case .folder: "My folder"; case .audius: "Audius artwork" }
    }
}

enum WallpaperOrder: String, Codable, CaseIterable, Identifiable {
    case sequential, shuffle
    var id: String { rawValue }
    var title: String { self == .sequential ? "In order" : "Shuffle" }
}

enum MusicGlassStyle: String, Codable, CaseIterable, Identifiable {
    case frosted, liquid
    var id: String { rawValue }
    var title: String { self == .frosted ? "Frosted" : "Liquid Glass" }
}

struct SettingsArchive: Codable, Equatable {
    var appearance: AppAppearance = .light
    var wallpaperSource: WallpaperSource = .cozy
    var folderBookmark: Data?
    var folderName: String?
    var wallpaperOrder: WallpaperOrder = .sequential
    var rotationSeconds: Int = 60
    var automaticallyRotate = true
    var loopWallpapers = true
    var glassStyle: MusicGlassStyle = .frosted
    var glassiness: Double = 0.45
    var channels: [MusicChannel] = []
    var selectedChannelID: String?

    static let rotationIntervals = [30, 60, 300, 900]

    var isValid: Bool {
        glassiness.isFinite && (0...1).contains(glassiness)
        && Self.rotationIntervals.contains(rotationSeconds)
        && (folderBookmark == nil) == (folderName == nil)
        && channels.allSatisfy(\.isValid)
        && Set(channels.map(\.id)).count == channels.count
        && (selectedChannelID == nil || channels.contains { $0.id == selectedChannelID })
    }
}

struct SettingsPersistence {
    let defaults: UserDefaults
    let key: String
    init(defaults: UserDefaults = .standard, key: String = "keep.preferences.v1") {
        self.defaults = defaults
        self.key = key
    }
    func load() throws -> SettingsArchive {
        guard defaults.object(forKey: key) != nil else { return SettingsArchive() }
        guard let data = defaults.data(forKey: key) else { throw CocoaError(.coderReadCorrupt) }
        let archive = try JSONDecoder().decode(SettingsArchive.self, from: data)
        guard archive.isValid else { throw CocoaError(.coderReadCorrupt) }
        return archive
    }
    func save(_ archive: SettingsArchive) throws {
        guard archive.isValid else { throw CocoaError(.coderInvalidValue) }
        defaults.set(try JSONEncoder().encode(archive), forKey: key)
    }
}

/// A separate app-owned archive; appearance/music settings never touch recording or task data.
@Observable
final class AppPreferences {
    private(set) var snapshot = SettingsArchive()
    private(set) var persistenceError: String?
    private(set) var canEdit = true
    @ObservationIgnored private let persistence: SettingsPersistence?

    init(persistence: SettingsPersistence? = nil) {
        self.persistence = persistence
        reload()
    }

    var appearance: AppAppearance {
        get { snapshot.appearance }
        set { update { $0.appearance = newValue } }
    }
    var wallpaperSource: WallpaperSource {
        get { snapshot.wallpaperSource }
        set { update { $0.wallpaperSource = newValue } }
    }
    var wallpaperOrder: WallpaperOrder {
        get { snapshot.wallpaperOrder }
        set { update { $0.wallpaperOrder = newValue } }
    }
    var rotationSeconds: Int {
        get { snapshot.rotationSeconds }
        set { update { $0.rotationSeconds = newValue } }
    }
    var automaticallyRotate: Bool {
        get { snapshot.automaticallyRotate }
        set { update { $0.automaticallyRotate = newValue } }
    }
    var loopWallpapers: Bool {
        get { snapshot.loopWallpapers }
        set { update { $0.loopWallpapers = newValue } }
    }
    var glassStyle: MusicGlassStyle {
        get { snapshot.glassStyle }
        set { update { $0.glassStyle = newValue } }
    }
    var glassiness: Double {
        get { snapshot.glassiness }
        set { update { $0.glassiness = newValue.isFinite ? min(1, max(0, newValue)) : 0.45 } }
    }
    var selectedChannel: MusicChannel? { snapshot.channels.first { $0.id == snapshot.selectedChannelID } }

    func saveChannel(_ channel: MusicChannel) {
        update { archive in
            if let index = archive.channels.firstIndex(where: { $0.id == channel.id }) { archive.channels[index] = channel }
            else { archive.channels.append(channel) }
        }
    }
    func removeChannel(_ channel: MusicChannel) {
        update {
            $0.channels.removeAll { $0.id == channel.id }
            if $0.selectedChannelID == channel.id { $0.selectedChannelID = nil }
        }
    }
    func selectChannel(_ channel: MusicChannel?) { update { $0.selectedChannelID = channel?.id } }
    func setFolder(bookmark: Data, name: String) {
        update { $0.folderBookmark = bookmark; $0.folderName = name; $0.wallpaperSource = .folder }
    }
    func clearFolder() {
        update {
            $0.folderBookmark = nil; $0.folderName = nil
            if $0.wallpaperSource == .folder { $0.wallpaperSource = .cozy }
        }
    }

    func retryPersistence() {
        if canEdit { persist() } else { reload() }
    }
    private func update(_ mutation: (inout SettingsArchive) -> Void) {
        guard canEdit else { return }
        var copy = snapshot
        mutation(&copy)
        guard copy.isValid else { return }
        snapshot = copy
        persist()
    }
    private func reload() {
        do {
            snapshot = try persistence?.load() ?? SettingsArchive()
            canEdit = true; persistenceError = nil
        } catch {
            canEdit = false
            persistenceError = "Saved settings couldn’t be opened. Retry to keep your preferences safe."
        }
    }
    private func persist() {
        do { try persistence?.save(snapshot); persistenceError = nil }
        catch { persistenceError = "Settings couldn’t be saved. Retry to save your changes." }
    }
}
