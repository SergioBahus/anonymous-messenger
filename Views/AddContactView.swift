import SwiftUI

struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var sessionId = ""

    let onAdd: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("Add Contact")
                .font(.title3)
                .bold()

            TextField("Account ID (Session ID)", text: $sessionId)
                .textFieldStyle(.roundedBorder)
                .frame(width: 520)

            HStack {
                Button("Cancel") { dismiss() }

                Button("Add") {
                    let sid = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard sid.count >= 20 else { return }
                    onAdd(sid)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 620)
    }
}
