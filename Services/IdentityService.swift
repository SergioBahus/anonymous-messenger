import Foundation
import CryptoKit

final class IdentityService {
    static let shared = IdentityService()
    private init() {}

    // ⚠️ Это старый ключ (одна запись в Keychain на весь Mac-профиль).
    // Мы больше НЕ используем его для “профилей”, но оставим для совместимости.
    private let legacyKeychainKey = "messenger.sessionId"

    /// Старый метод: возвращает один и тот же Session ID из Keychain (для одного macOS-пользователя).
    /// Сейчас он нам НЕ нужен для профилей, но пусть останется (может пригодиться для миграции).
    func getOrCreateSessionId() -> String {
        if let data = KeychainHelper.shared.read(key: legacyKeychainKey),
           let s = String(data: data, encoding: .utf8),
           !s.isEmpty {
            return s
        }

        let newId = createNewSessionId()
        _ = KeychainHelper.shared.save(key: legacyKeychainKey, data: Data(newId.utf8))
        return newId
    }

    /// Новый метод: генерирует НОВЫЙ Session ID каждый раз.
    /// Его мы будем сохранять в profiles.json (а не в Keychain), чтобы иметь несколько профилей.
    func createNewSessionId() -> String {
        // 32 байта -> hex 64 символа
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }
}
