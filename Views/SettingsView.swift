import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    let myProfileName: String
    let mySessionId: String
    let onSwitchAccount: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack {
                Text("Settings")
                    .font(.title2)
                    .bold()

                Spacer()

                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Account: \(myProfileName)")

                    Text("ID")
                        .foregroundStyle(.secondary)

                    Text(mySessionId)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)

                    HStack(spacing: 12) {

                        Button("Copy ID") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(mySessionId, forType: .string)
                        }

                        Button("Switch Account") {
                            dismiss()
                            onSwitchAccount()
                        }
                    }
                    .padding(.top, 6)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer()
        }
        .padding(24)
        .frame(width: 520, height: 340)
    }
}
