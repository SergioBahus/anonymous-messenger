import Foundation

// Локальный транспорт: доставляет “сообщение” самому приложению.
// Это нужно, чтобы обкатать UI/архитектуру.
// Потом заменим на WebSocketTransport.
final class LocalTransport: Transport {
    var onReceive: ((Envelope) -> Void)?

    func start() {}
    func stop() {}

    func send(_ envelope: Envelope) {
        // Эмулируем доставку с небольшой задержкой
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.onReceive?(envelope)
        }
    }
}
