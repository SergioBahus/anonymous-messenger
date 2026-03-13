import Foundation

final class LocalTransport: Transport {
    var onReceive: ((Envelope) -> Void)?

    func start() {}
    func stop() {}

    func send(_ envelope: Envelope, attachmentURL: URL?) {
        // Эмулируем доставку с небольшой задержкой
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.onReceive?(envelope)
        }
    }
}
