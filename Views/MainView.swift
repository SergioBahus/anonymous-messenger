import SwiftUI

// MARK: - PreferenceKeys

private struct BottomMaxYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// msg.id -> minY (в координатах ScrollView)
private struct VisibleMsgMinYKey: PreferenceKey {
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

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

    // UI
    @State private var isShowingAddContact: Bool = false
    @State private var isShowingSettings: Bool = false
    @State private var addContactError: String?

    // Per-chat state
    @State private var topMessageByContact: [UUID: UUID] = [:]     // contact.id -> msg.id (top visible)
    @State private var unreadByContact: [UUID: Int] = [:]          // contact.id -> unread count
    @State private var atBottomByContact: [UUID: Bool] = [:]       // contact.id -> isAtBottom

    // Current chat runtime tracking (to save position correctly)
    @State private var currentTopVisibleMessageId: UUID? = nil
    @State private var scrollViewportHeight: CGFloat = 0
    
    @State private var pickedFileURL: URL?

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

        // bindings to per-contact state
        let unread = Binding<Int>(
            get: { unreadByContact[contact.id] ?? 0 },
            set: { unreadByContact[contact.id] = $0 }
        )

        let isAtBottom = Binding<Bool>(
            get: { atBottomByContact[contact.id] ?? true },
            set: { atBottomByContact[contact.id] = $0 }
        )

        return VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {

                    GeometryReader { outerGeo in
                        ScrollView {
                            LazyVStack(spacing: 10) {
                                ForEach(Array(chatMessages.enumerated()), id: \.element.id) { i, msg in
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
                                    .id(msg.id)
                                    // фиксируем позицию каждого сообщения относительно верха ScrollView
                                    .background(
                                        Group {
                                            if i % 6 == 0 {
                                                GeometryReader { geo in
                                                    Color.clear.preference(
                                                        key: VisibleMsgMinYKey.self,
                                                        value: [msg.id: geo.frame(in: .named("CHAT_SCROLL")).minY]
                                                    )
                                                }
                                            } else {
                                                Color.clear
                                            }
                                        }
                                    )
                                }

                                // якорь низа + определение "мы внизу?"
                                Color.clear
                                    .frame(height: 1)
                                    .id("BOTTOM")
                                    .background(
                                        GeometryReader { geo in
                                            Color.clear.preference(
                                                key: BottomMaxYKey.self,
                                                value: geo.frame(in: .named("CHAT_SCROLL")).maxY
                                            )
                                        }
                                    )
                            }
                            .padding()
                        }
                        .coordinateSpace(name: "CHAT_SCROLL")

                        // сохраняем высоту видимой области (для определения "внизу")
                        .onAppear {
                            scrollViewportHeight = outerGeo.size.height

                            DispatchQueue.main.async {
                                if let savedTop = topMessageByContact[contact.id] {
                                    // ✅ вернуться туда же, где был
                                    proxy.scrollTo(savedTop, anchor: .top)
                                } else {
                                    // ✅ первый вход в чат — показать последние
                                    proxy.scrollTo("BOTTOM", anchor: .bottom)
                                    unread.wrappedValue = 0
                                    isAtBottom.wrappedValue = true
                                }
                            }
                        }
                        .onChange(of: outerGeo.size.height) { _, newH in
                            scrollViewportHeight = newH
                        }

                        // определяем top visible msg.id (чтобы восстановить позицию)
                        .onPreferenceChange(VisibleMsgMinYKey.self) { dict in
                            // берем сообщение, которое ближе всего к верхней границе (minY >= 0)
                            let candidates = dict
                                .filter { $0.value >= 0 }
                                .sorted { $0.value < $1.value }

                            if let top = candidates.first?.key {
                                currentTopVisibleMessageId = top
                            }
                        }

                        // определяем "мы внизу?"
                        .onPreferenceChange(BottomMaxYKey.self) { bottomMaxY in
                            let threshold: CGFloat = 24
                            let atBottomNow = bottomMaxY <= (scrollViewportHeight + threshold)

                            if atBottomNow && !isAtBottom.wrappedValue {
                                unread.wrappedValue = 0
                            }
                            isAtBottom.wrappedValue = atBottomNow
                        }
                    }

                    // кнопка “New messages”
                    if !isAtBottom.wrappedValue && unread.wrappedValue > 0 {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("BOTTOM", anchor: .bottom)
                            }
                            unread.wrappedValue = 0
                            isAtBottom.wrappedValue = true
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

                // новые сообщения:
                // - если мы внизу → автоскролл
                // - если не внизу → НЕ скроллим, увеличиваем unread только для входящих
                .onChange(of: chatMessages.count) { oldValue, newValue in
                    guard newValue > oldValue else { return }
                    guard let last = chatMessages.last else { return }

                    let outgoing = (last.senderSessionId == mySessionId)

                    if isAtBottom.wrappedValue {
                        DispatchQueue.main.async {
                            withAnimation(.easeOut(duration: 0.2)) {
                                proxy.scrollTo("BOTTOM", anchor: .bottom)
                            }
                            unread.wrappedValue = 0
                        }
                    } else {
                        if !outgoing {
                            unread.wrappedValue += 1
                        }
                    }
                }

                // при уходе из чата — запоминаем позицию
                .onDisappear {
                    if let topId = currentTopVisibleMessageId {
                        topMessageByContact[contact.id] = topId
                    }
                }
            }

            Divider()

            // --- Composer (input bar) ---
            let minH: CGFloat = 36          // 1 строка (можешь подстроить 34–40)
            let maxH: CGFloat = 200         // ~10 строк (если хочешь чуть меньше/больше — подстрой)
            let clampedH = min(max(inputHeight, minH), maxH)

            HStack(spacing: 10) {

                ZStack {
                    // рамка/фон одного "поля"
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.primary.opacity(0.06))

                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.primary.opacity(0.18))

                    // Editor
                    GrowingTextEditor(
                        text: $draft,
                        height: $inputHeight,
                        pinnedToMax: $inputPinnedToMax,
                        maxLines: 10,
                        leadingAccessoryWidth: 26,
                        trailingAccessoryWidth: 40,
                        onEnterSend: {
                            sendMessage(to: contact)
                        }
                    )
                    .padding(.leading, 6)     // общий внутренний паддинг поля
                    .overlay(alignment: .trailing) {
                        Color.clear.frame(width: 40)
                    }
                    .padding(.vertical, 6)

                    // Иконки внутри поля (слева/справа)
                    HStack {
                        Button {
                            pickAttachment()
                        } label: {
                            Image(systemName: "paperclip")
                                .font(.system(size: 16))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .padding(.leading, 12)

                        Spacer()

                        Button {
                            sendMessage(to: contact)
                        } label: {
                            Image(systemName: "paperplane.fill")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(isDraftEmpty ? .secondary : .accentColor)
                        }
                        .buttonStyle(.plain)
                        .disabled(isDraftEmpty)
                        .padding(.trailing, 12)
                    }
                }
                // ВАЖНО: высоту задаём контейнеру, а не только editor-у
                .frame(maxWidth: .infinity)
                .frame(height: clampedH)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }
    
    private var isDraftEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Data helpers

    private func messages(with contact: Contact) -> [ChatMessage] {
        appData.messages
            .filter {
                ($0.senderSessionId == mySessionId && $0.receiverSessionId == contact.sessionId) ||
                ($0.senderSessionId == contact.sessionId && $0.receiverSessionId == mySessionId)
            }
            
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
        inputPinnedToMax = false
        inputHeight = 34

        transport.send(env)
    }
    
    private func pickAttachment() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK {
            pickedFileURL = panel.url
            // пока просто храним; позже добавим отправку/превью
            print("Picked attachment:", pickedFileURL?.path ?? "nil")
        }
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
