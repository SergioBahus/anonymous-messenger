import Foundation

struct Profile: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var sessionId: String
}

struct ProfilesData: Codable {
    var profiles: [Profile]
    var activeProfileId: UUID?
}
