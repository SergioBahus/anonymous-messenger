import Foundation

final class FileTransport: Transport {
    var onReceive: ((Envelope) -> Void)?

    private let mySessionId: String
    private var timer: Timer?

    init(mySessionId: String) {
        self.mySessionId = mySessionId
    }

    func start() {
        ensureInboxDir()

        // Поллинг. Для локального теста ок.
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in
            self?.drainInbox()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func send(_ envelope: Envelope) {
        do {
            let dir = inboxDir(for: envelope.receiverSessionId)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let fileName = "\(Int(envelope.timestamp.timeIntervalSince1970 * 1000))_\(envelope.id.uuidString).json"
            let fileURL = dir.appendingPathComponent(fileName)

            let data = try JSONEncoder().encode(envelope)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("FileTransport send error:", error)
        }
    }

    // MARK: - Inbox handling

    private func drainInbox() {
        let dir = inboxDir(for: mySessionId)

        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        // Сортируем, чтобы приходило по порядку создания
        let sorted = items.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da < db
        }

        for url in sorted where url.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: url)
                let env = try JSONDecoder().decode(Envelope.self, from: data)

                // только то, что реально адресовано мне
                guard env.receiverSessionId == mySessionId else {
                    try? FileManager.default.removeItem(at: url)
                    continue
                }

                onReceive?(env)

                // важно: удаляем файл, чтобы не перечитывать
                try? FileManager.default.removeItem(at: url)
            } catch {
                // если файл битый — удалим, чтобы не стопориться
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func ensureInboxDir() {
        let dir = inboxDir(for: mySessionId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    private func inboxDir(for sessionId: String) -> URL {
        let base = baseRelayDir()
        return base.appendingPathComponent(sessionId, isDirectory: true)
    }

    private func baseRelayDir() -> URL {
        let fm = FileManager.default
        let folder = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appFolder = folder.appendingPathComponent("Messenger", isDirectory: true)
        let relay = appFolder.appendingPathComponent("relay", isDirectory: true)

        if !fm.fileExists(atPath: relay.path) {
            try? fm.createDirectory(at: relay, withIntermediateDirectories: true)
        }
        return relay
    }
}
