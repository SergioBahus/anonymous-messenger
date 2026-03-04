import Foundation

protocol Transport {
    var onReceive: ((Envelope) -> Void)? { get set }
    func start()
    func stop()
    func send(_ envelope: Envelope)
}
