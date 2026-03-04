import SwiftUI

struct ContentView: View {
    @State private var profile: Profile?

    var body: some View {
        Group {
            if let profile {
                MainView(
                    mySessionId: profile.sessionId,
                    myProfileName: profile.name,
                    onSwitchAccount: {
                        self.profile = nil
                    }
                )
            } else {
                ProfilePickerView(selectedProfile: $profile)
            }
        }
    }
}
