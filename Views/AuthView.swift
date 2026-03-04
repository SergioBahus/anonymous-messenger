import SwiftUI

struct AuthView: View {
    @Binding var isReady: Bool
    let sessionId: String

    var body: some View {
        VStack(spacing: 14) {
            Text("Anonymous Messenger")
                .font(.title2)
                .bold()

            Text("Your Session ID")
                .foregroundStyle(.secondary)

            Text(sessionId)
                .font(.system(.footnote, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .frame(width: 520)

            HStack {
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(sessionId, forType: .string)
                }

                Button("Continue") {
                    isReady = true
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(30)
        .frame(width: 620)
    }
}
