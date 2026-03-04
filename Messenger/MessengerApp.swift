import SwiftUI

@main
struct MessengerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 780, height: 600) // ← вот здесь меняем
    }
}
