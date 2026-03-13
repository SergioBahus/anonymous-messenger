import Foundation
import Darwin

final class FileTransport: Transport {
    var onReceive: ((Envelope) -> Void)?

    private let mySessionId: String

    private var directoryFD: Int32 = -1
    private var directorySource: DispatchSourceFileSystemObject?
    private let watcherQueue = DispatchQueue(label: "messenger.filetransport.watcher", qos: .userInitiated)

    init(mySessionId: String) {
        self.mySessionId = mySessionId
    }

    func start() {
        ensureInboxDir()
        startWatchingInbox()
        drainInbox()
    }

    func stop() {
        stopWatchingInbox()
    }

    func send(_ envelope: Envelope, attachmentURL: URL?) {
        do {
            let dir = inboxDir(for: envelope.receiverSessionId)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            if let attachmentURL,
               let storedName = envelope.attachmentStoredName {
                let attachDir = attachmentsDir(for: envelope.receiverSessionId)
                try FileManager.default.createDirectory(at: attachDir, withIntermediateDirectories: true)

                let dst = attachDir.appendingPathComponent(storedName)

                if FileManager.default.fileExists(atPath: dst.path) {
                    try FileManager.default.removeItem(at: dst)
                }

                try FileManager.default.copyItem(at: attachmentURL, to: dst)
            }

            let fileName = "\(Int(envelope.timestamp.timeIntervalSince1970 * 1000))_\(envelope.id.uuidString).json"
            let fileURL = dir.appendingPathComponent(fileName)

            let data = try JSONEncoder().encode(envelope)
            try data.write(to: fileURL, options: [.atomic])
        } catch {
            print("FileTransport send error:", error)
        }
    }

    // MARK: - Watcher

    private func startWatchingInbox() {
        stopWatchingInbox()

        let dir = inboxDir(for: mySessionId)
        directoryFD = open(dir.path, O_EVTONLY)

        guard directoryFD >= 0 else {
            print("FileTransport watcher error: failed to open inbox dir")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFD,
            eventMask: [.write, .rename, .delete, .extend, .attrib],
            queue: watcherQueue
        )

        source.setEventHandler { [weak self] in
            guard let self else { return }

            let events = source.data

            if events.contains(.delete) || events.contains(.rename) {
                self.ensureInboxDir()
                self.startWatchingInbox()
            }

            self.drainInbox()
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.directoryFD >= 0 {
                close(self.directoryFD)
                self.directoryFD = -1
            }
        }

        directorySource = source
        source.resume()
    }

    private func stopWatchingInbox() {
        directorySource?.cancel()
        directorySource = nil

        if directoryFD >= 0 {
            close(directoryFD)
            directoryFD = -1
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

        let sorted = items.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return da < db
        }

        for url in sorted where url.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: url)
                let env = try JSONDecoder().decode(Envelope.self, from: data)

                guard env.receiverSessionId == mySessionId else {
                    try? FileManager.default.removeItem(at: url)
                    continue
                }

                DispatchQueue.main.async {
                    self.onReceive?(env)
                }

                try? FileManager.default.removeItem(at: url)
            } catch {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    // MARK: - Paths

    private func ensureInboxDir() {
        let dir = inboxDir(for: mySessionId)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let attach = attachmentsDir(for: mySessionId)
        try? FileManager.default.createDirectory(at: attach, withIntermediateDirectories: true)
    }

    func inboxDir(for sessionId: String) -> URL {
        let base = baseRelayDir()
        return base.appendingPathComponent(sessionId, isDirectory: true)
    }

    func attachmentsDir(for sessionId: String) -> URL {
        inboxDir(for: sessionId).appendingPathComponent("attachments", isDirectory: true)
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
