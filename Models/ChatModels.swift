import Foundation

// Контакт = Session ID другого человека + локальный алиас (опционально)
struct Contact: Identifiable, Codable, Hashable {
    let id: UUID
    var sessionId: String
    var username: String   // локально у тебя, не “регистрация”
}

enum DeliveryStatus: String, Codable {
    case queued
    case sent
    case delivered
    case failed
}

// То, что хранится в истории (уже как для сети)
struct ChatMessage: Identifiable, Codable, Hashable {
    let id: UUID
    var senderSessionId: String
    var receiverSessionId: String
    var timestamp: Date

    var body: String

    var attachmentFileName: String?
    var attachmentStoredName: String?
    var attachmentLocalPath: String?

    var status: DeliveryStatus
}

// Конверт (то, что “летит” через Transport)
struct Envelope: Identifiable, Codable, Hashable {
    let id: UUID
    let senderSessionId: String
    let receiverSessionId: String
    let timestamp: Date

    let payload: String

    // файл
    let attachmentFileName: String?
    let attachmentStoredName: String?
}

struct AppData: Codable {
    var contacts: [Contact]
    var messages: [ChatMessage]
}
