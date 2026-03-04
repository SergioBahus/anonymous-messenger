import Foundation

final class ProfileService {
    static let shared = ProfileService()
    private init() {}

    private let fileName = "profiles.json"

    private var fileURL: URL {
        let fm = FileManager.default
        let folder = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = folder.appendingPathComponent("Messenger", isDirectory: true)

        if !fm.fileExists(atPath: appFolder.path) {
            try? fm.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }

        return appFolder.appendingPathComponent(fileName)
    }

    func load() -> ProfilesData {
        guard let data = try? Data(contentsOf: fileURL) else {
            return ProfilesData(profiles: [], activeProfileId: nil)
        }

        do {
            return try JSONDecoder().decode(ProfilesData.self, from: data)
        } catch {
            return ProfilesData(profiles: [], activeProfileId: nil)
        }
    }

    func save(_ profilesData: ProfilesData) {
        do {
            let enc = JSONEncoder()
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(profilesData)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("Profiles save error:", error)
        }
    }

    @discardableResult
    func createProfile(name: String) -> Profile {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        precondition(!trimmed.isEmpty, "Profile name must not be empty")

        let newProfile = Profile(
            id: UUID(),
            name: trimmed,
            sessionId: IdentityService.shared.createNewSessionId()
        )

        var data = load()
        data.profiles.append(newProfile)
        data.activeProfileId = newProfile.id
        save(data)

        return newProfile
    }

    func setActive(_ id: UUID) {
        var data = load()
        data.activeProfileId = id
        save(data)
    }

    func activeProfile() -> Profile? {
        let data = load()
        guard let id = data.activeProfileId else { return nil }
        return data.profiles.first { $0.id == id }
    }

    /// Для локального режима: если Session ID принадлежит профилю на этом устройстве,
    /// возвращаем его username.
    func usernameForSessionId(_ sessionId: String) -> String? {
        let sid = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else { return nil }
        let data = load()
        return data.profiles.first { $0.sessionId == sid }?.name
    }
}
