import Foundation

final class StorageService {
    static let shared = StorageService()
    private init() {}

    // MARK: - Public API

    func load(for sessionId: String) -> AppData {
        let url = fileURL(for: sessionId)

        guard let data = try? Data(contentsOf: url) else {
            return AppData(contacts: [], messages: [])
        }

        do {
            return try JSONDecoder().decode(AppData.self, from: data)
        } catch {
            return AppData(contacts: [], messages: [])
        }
    }

    func save(_ appData: AppData, for sessionId: String) {
        let url = fileURL(for: sessionId)

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(appData)
            try data.write(to: url, options: [.atomic])
        } catch {
            print("Save error:", error)
        }
    }

    // MARK: - Paths

    private func fileURL(for sessionId: String) -> URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let messengerFolder = base.appendingPathComponent("Messenger", isDirectory: true)
        let profilesFolder = messengerFolder.appendingPathComponent("profiles", isDirectory: true)
        let profileFolder = profilesFolder.appendingPathComponent(sessionId, isDirectory: true)

        if !fm.fileExists(atPath: profileFolder.path) {
            try? fm.createDirectory(at: profileFolder, withIntermediateDirectories: true)
        }

        return profileFolder.appendingPathComponent("messenger_data.json")
    }
}
