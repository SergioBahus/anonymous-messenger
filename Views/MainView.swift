import SwiftUI
import AppKit

// MARK: - MainView

struct MainView: View {
    let mySessionId: String
    let myProfileName: String
    let onSwitchAccount: () -> Void

    init(mySessionId: String, myProfileName: String, onSwitchAccount: @escaping () -> Void) {
        self.mySessionId = mySessionId
        self.myProfileName = myProfileName
        self.onSwitchAccount = onSwitchAccount
        self.transport = FileTransport(mySessionId: mySessionId)
        self._appData = State(initialValue: StorageService.shared.load(for: mySessionId))
    }

    // Data
    @State private var appData: AppData
    @State private var selectedContactId: UUID?

    // Compose
    @State private var draft: String = ""
    @State private var inputHeight: CGFloat = 34
    @State private var inputPinnedToMax: Bool = false
    @State private var selectedAttachmentURL: URL?

    // UI
    @State private var isShowingAddContact: Bool = false
    @State private var isShowingSettings: Bool = false
    @State private var addContactError: String?

    // Per-chat state
    @State private var scrollOffsetByContact: [UUID: CGFloat] = [:]
    @State private var scrollToBottomTickByContact: [UUID: Int] = [:]
    @State private var scrollToOffsetTickByContact: [UUID: Int] = [:]
    @State private var jumpTargetOffsetByContact: [UUID: CGFloat] = [:]
    @State private var firstUnreadOffsetByContact: [UUID: CGFloat] = [:]
    @State private var contentHeightByContact: [UUID: CGFloat] = [:]
    @State private var viewportHeightByContact: [UUID: CGFloat] = [:]
    @State private var unreadByContact: [UUID: Int] = [:]
    @State private var atBottomByContact: [UUID: Bool] = [:]
    
    private let transport: FileTransport

    var body: some View {
        NavigationSplitView {
            contactsList
        } detail: {
            detailView
        }
        .onAppear {
            if selectedContactId == nil {
                selectedContactId = appData.contacts.first?.id
            }
            transport.onReceive = { envelope in
                handleIncoming(envelope)
            }
            transport.start()
        }
        .sheet(isPresented: $isShowingAddContact) {
            AddContactView { sessionId in
                addContact(sessionId: sessionId)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                myProfileName: myProfileName,
                mySessionId: mySessionId,
                onSwitchAccount: {
                    isShowingSettings = false
                    onSwitchAccount()
                }
            )
        }
        .alert("Cannot add contact", isPresented: Binding(
            get: { addContactError != nil },
            set: { if !$0 { addContactError = nil } }
        )) {
            Button("OK", role: .cancel) { addContactError = nil }
        } message: {
            Text(addContactError ?? "")
        }
    }

    // MARK: - Left pane

    private var contactsList: some View {
        List(selection: $selectedContactId) {
            ForEach(appData.contacts) { contact in
                Text(contact.username)
                    .tag(contact.id)
            }
        }
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu {
                    Button("Settings") { isShowingSettings = true }
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingAddContact = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
    }

    // MARK: - Right pane

    private var detailView: some View {
        Group {
            if let contact = selectedContact {
                chatView(for: contact)
                    .id(contact.id)
                    .navigationTitle(contact.username)
            } else {
                Text("Select a contact")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var selectedContact: Contact? {
        guard let id = selectedContactId else { return nil }
        return appData.contacts.first { $0.id == id }
    }

    // MARK: - Chat UI

    private func chatView(for contact: Contact) -> some View {
        let chatMessages = messages(with: contact)

        let unread = Binding<Int>(
            get: { unreadByContact[contact.id] ?? 0 },
            set: { unreadByContact[contact.id] = $0 }
        )

        let isAtBottom = Binding<Bool>(
            get: { atBottomByContact[contact.id] ?? true },
            set: { atBottomByContact[contact.id] = $0 }
        )

        let scrollOffset = Binding<CGFloat>(
            get: { scrollOffsetByContact[contact.id] ?? 0 },
            set: { scrollOffsetByContact[contact.id] = $0 }
        )

        let contentHeight = Binding<CGFloat>(
            get: { contentHeightByContact[contact.id] ?? 0 },
            set: { newValue in
                DispatchQueue.main.async {
                    contentHeightByContact[contact.id] = newValue
                }
            }
        )

        let viewportHeight = Binding<CGFloat>(
            get: { viewportHeightByContact[contact.id] ?? 0 },
            set: { newValue in
                DispatchQueue.main.async {
                    viewportHeightByContact[contact.id] = newValue
                }
            }
        )

        return VStack(spacing: 0) {
            ZStack(alignment: .bottomTrailing) {
                PreciseScrollView(
                    offsetY: scrollOffset,
                    isAtBottom: isAtBottom,
                    contentHeight: contentHeight,
                    viewportHeight: viewportHeight,
                    restoreID: contact.id,
                    scrollToBottomTick: scrollToBottomTickByContact[contact.id] ?? 0,
                    scrollToOffsetTick: scrollToOffsetTickByContact[contact.id] ?? 0,
                    targetOffsetY: jumpTargetOffsetByContact[contact.id] ?? 0
                ) {
                    LazyVStack(spacing: 10) {
                        ForEach(chatMessages) { msg in
                            let outgoing = (msg.senderSessionId == mySessionId)

                            HStack {
                                if outgoing { Spacer(minLength: 40) }

                                Text(msg.body)
                                    .foregroundStyle(outgoing ? Color.white : Color.primary)
                                    .padding(10)
                                    .background(outgoing ? Color.blue : Color.gray.opacity(0.18))
                                    .cornerRadius(12)
                                    .frame(maxWidth: 520, alignment: outgoing ? .trailing : .leading)

                                if !outgoing { Spacer(minLength: 40) }
                            }
                        }
                    }
                    .padding()
                }
                .onAppear {
                    if scrollToBottomTickByContact[contact.id] == nil {
                        scrollToBottomTickByContact[contact.id] = 0
                    }

                    if scrollToOffsetTickByContact[contact.id] == nil {
                        scrollToOffsetTickByContact[contact.id] = 0
                    }

                    if scrollOffsetByContact[contact.id] == nil {
                        DispatchQueue.main.async {
                            scrollToBottomTickByContact[contact.id, default: 0] += 1
                            unread.wrappedValue = 0
                            isAtBottom.wrappedValue = true
                            firstUnreadOffsetByContact[contact.id] = nil
                        }
                    }
                }

                if !isAtBottom.wrappedValue && unread.wrappedValue > 0 {
                    Button {
                        if let firstUnreadOffset = firstUnreadOffsetByContact[contact.id] {
                            jumpTargetOffsetByContact[contact.id] = firstUnreadOffset
                            scrollToOffsetTickByContact[contact.id, default: 0] += 1
                        } else {
                            scrollToBottomTickByContact[contact.id, default: 0] += 1
                        }

                        unread.wrappedValue = 0
                        firstUnreadOffsetByContact[contact.id] = nil
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down")
                            Text("New messages (\(unread.wrappedValue))")
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.trailing, 16)
                    .padding(.bottom, 12)
                }
            }
            .onChange(of: chatMessages.count) { oldValue, newValue in
                guard newValue > oldValue else { return }
                guard let last = chatMessages.last else { return }

                let outgoing = (last.senderSessionId == mySessionId)

                if outgoing {
                    DispatchQueue.main.async {
                        scrollToBottomTickByContact[contact.id, default: 0] += 1
                        unread.wrappedValue = 0
                        firstUnreadOffsetByContact[contact.id] = nil
                    }
                } else if isAtBottom.wrappedValue {
                    DispatchQueue.main.async {
                        scrollToBottomTickByContact[contact.id, default: 0] += 1
                        unread.wrappedValue = 0
                        firstUnreadOffsetByContact[contact.id] = nil
                    }
                } else {
                    if unread.wrappedValue == 0 {
                        let contentHeight = contentHeightByContact[contact.id] ?? 0
                        let viewportHeight = viewportHeightByContact[contact.id] ?? 0
                        let oldBottomOffset = max(0, contentHeight - viewportHeight)

                        let revealPadding: CGFloat = 80
                        firstUnreadOffsetByContact[contact.id] = oldBottomOffset + revealPadding
                    }

                    unread.wrappedValue += 1
                }
            }
            .onChange(of: isAtBottom.wrappedValue) { _, atBottomNow in
                if atBottomNow {
                    unread.wrappedValue = 0
                    firstUnreadOffsetByContact[contact.id] = nil
                }
            }

            Divider()

            VStack(spacing: 8) {
                if let attachment = selectedAttachmentURL {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.fill")
                            .foregroundStyle(.secondary)

                        Text(attachment.lastPathComponent)
                            .font(.system(size: 13))
                            .lineLimit(1)

                        Spacer()

                        Button {
                            selectedAttachmentURL = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.primary.opacity(0.06))
                    )
                }

                HStack(alignment: .bottom, spacing: 8) {
                    Button {
                        attachFile()
                    } label: {
                        Image(systemName: "paperclip")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    GrowingTextEditor(
                        text: $draft,
                        height: $inputHeight,
                        pinnedToMax: $inputPinnedToMax,
                        maxLines: 10,
                        onEnterSend: {
                            sendMessage(to: contact)
                        }
                    )
                    .frame(height: inputHeight)

                    Button {
                        sendMessage(to: contact)
                    } label: {
                        Image(systemName: "paperplane.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(canSendMessage ? Color.blue : Color.gray.opacity(0.45))
                            .scaleEffect(canSendMessage ? 1.0 : 0.96)
                            .animation(.easeInOut(duration: 0.15), value: canSendMessage)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canSendMessage)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.primary.opacity(0.14))
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
    }
    private var canSendMessage: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    // MARK: - Data helpers

    private func messages(with contact: Contact) -> [ChatMessage] {
        appData.messages
            .filter {
                ($0.senderSessionId == mySessionId && $0.receiverSessionId == contact.sessionId) ||
                ($0.senderSessionId == contact.sessionId && $0.receiverSessionId == mySessionId)
            }
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func addContact(sessionId: String) {
        let sid = sessionId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sid.isEmpty else { return }

        if sid == mySessionId {
            addContactError = "You can’t add your own account ID."
            return
        }

        if appData.contacts.contains(where: { $0.sessionId == sid }) {
            addContactError = "This contact is already added."
            return
        }

        guard let username = ProfileService.shared.usernameForSessionId(sid) else {
            addContactError = "This account ID is not known on this device yet. (Network sync will be added later.)"
            return
        }

        let new = Contact(id: UUID(), sessionId: sid, username: username)
        appData.contacts.append(new)
        StorageService.shared.save(appData, for: mySessionId)
        selectedContactId = new.id
    }
    
    private func attachFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            selectedAttachmentURL = panel.url
        }
    }

    private func sendMessage(to contact: Contact) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        let env = Envelope(
            id: UUID(),
            senderSessionId: mySessionId,
            receiverSessionId: contact.sessionId,
            timestamp: Date(),
            payload: text
        )

        let outgoing = ChatMessage(
            id: env.id,
            senderSessionId: env.senderSessionId,
            receiverSessionId: env.receiverSessionId,
            timestamp: env.timestamp,
            body: text,
            status: .sent
        )

        appData.messages.append(outgoing)
        StorageService.shared.save(appData, for: mySessionId)

        draft = ""
        selectedAttachmentURL = nil
        inputPinnedToMax = false
        inputHeight = 34

        transport.send(env)
    }

    private func handleIncoming(_ envelope: Envelope) {
        guard envelope.receiverSessionId == mySessionId else { return }

        // авто-добавление контакта, если известен username на этом устройстве
        if !appData.contacts.contains(where: { $0.sessionId == envelope.senderSessionId }) {
            if let username = ProfileService.shared.usernameForSessionId(envelope.senderSessionId) {
                let newContact = Contact(id: UUID(), sessionId: envelope.senderSessionId, username: username)
                appData.contacts.append(newContact)
                StorageService.shared.save(appData, for: mySessionId)

                if selectedContactId == nil {
                    selectedContactId = newContact.id
                }
            }
        }

        let incoming = ChatMessage(
            id: envelope.id,
            senderSessionId: envelope.senderSessionId,
            receiverSessionId: envelope.receiverSessionId,
            timestamp: envelope.timestamp,
            body: envelope.payload,
            status: .delivered
        )

        appData.messages.append(incoming)
        StorageService.shared.save(appData, for: mySessionId)
    }
}
