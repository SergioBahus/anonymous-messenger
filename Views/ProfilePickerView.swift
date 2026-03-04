import SwiftUI

struct ProfilePickerView: View {
    @Binding var selectedProfile: Profile?

    @State private var data = ProfileService.shared.load()
    @State private var selectedId: UUID?

    @State private var isCreating = false
    @State private var newName = ""

    var body: some View {
        VStack(spacing: 14) {
            Text("Choose Account")
                .font(.title2)
                .bold()

            if data.profiles.isEmpty {
                Text("No accounts on this device yet.")
                    .foregroundStyle(.secondary)
            } else {
                List(selection: $selectedId) {
                    ForEach(data.profiles) { p in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(p.name).font(.headline)
                            Text(p.sessionId)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .tag(p.id)
                    }
                }
                .frame(width: 680, height: 260)
            }

            HStack(spacing: 10) {
                Button("Create new account") {
                    isCreating = true
                }

                Spacer()

                Button("Continue") {
                    continueWithSelected()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(data.profiles.isEmpty && !isCreating)
            }
            .frame(width: 680)

            if isCreating {
                Divider().padding(.vertical, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Create account (username required)")
                        .font(.headline)

                    HStack(spacing: 10) {
                        TextField("Username", text: $newName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 360)

                        Button("Create") {
                            createProfile()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Cancel") {
                            isCreating = false
                            newName = ""
                        }
                    }
                }
                .frame(width: 680, alignment: .leading)
            }
        }
        .padding(24)
        .frame(width: 740)
        .onAppear {
            reload()

            // подсветим активный/первый профиль
            if selectedId == nil {
                selectedId = data.activeProfileId ?? data.profiles.first?.id
            }
        }
    }

    // MARK: - Helpers

    private func reload() {
        data = ProfileService.shared.load()
    }

    private func continueWithSelected() {
        reload()
        guard let id = selectedId ?? data.activeProfileId ?? data.profiles.first?.id else { return }
        guard let profile = data.profiles.first(where: { $0.id == id }) else { return }

        ProfileService.shared.setActive(id)
        selectedProfile = profile
    }

    private func createProfile() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let created = ProfileService.shared.createProfile(name: name)
        reload()

        selectedId = created.id
        selectedProfile = created

        isCreating = false
        newName = ""
    }
}
