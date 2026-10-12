import SwiftUI
import AuthenticationServices
import BuddyCheckAPI

@MainActor @Observable private final class SignInBrowser: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var webSession: ASWebAuthenticationSession?
    var isActive: Bool { webSession != nil }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    func authorize(_ account: ConnectedAccount) async throws {
        let attempt = try account.beginAuthorization(rememberSession: true)
        do {
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                let session = ASWebAuthenticationSession(url: attempt.authorizationURL, callbackURLScheme: attempt.configuration.redirectURI.scheme) { url, error in
                    Task { @MainActor in
                        self.webSession = nil
                        if let url { continuation.resume(returning: url) }
                        else { continuation.resume(throwing: error ?? ClientError.invalidCallback) }
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = true
                webSession = session
                if !session.start() { webSession = nil; continuation.resume(throwing: ClientError.invalidCallback) }
            }
            try await account.finishAuthorization(callback: callback)
        } catch {
            try? account.cancelAuthorization()
            throw error
        }
    }
    func cancel() { webSession?.cancel() }
}

struct PostConnectionRoot<LocalContent: View>: View {
    @Binding var showLocalReminder: Bool
    @ViewBuilder let localContent: (@escaping () -> Void, (() -> Void)?) -> LocalContent
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("connected.issuer") private var issuer = Bundle.main.object(forInfoDictionaryKey: "BuddyChecksPostIssuer") as? String ?? ""
    @AppStorage("connected.clientID") private var clientID = Bundle.main.object(forInfoDictionaryKey: "BuddyChecksPostClientID") as? String ?? ""
    @State private var account: ConnectedAccount?
    @State private var browser = SignInBrowser()
    @State private var initialized = false
    @State private var connectionRequested = false
    @State private var showSettings = false
    @State private var busy = false
    @State private var error: String?
    @State private var confirmSignOut = false
    @State private var status: String?
    private let callback = URL(string: "org.wipost165.buddychecks:/oauth/callback")!
    private var usesPost: Bool { connectionRequested || account != nil || (!issuer.isEmpty && !clientID.isEmpty) }

    var body: some View {
        Group {
            if !initialized {
                ProgressView("Opening Buddy Checks")
            } else if showLocalReminder || !usesPost {
                localContent({ showSettings = true }, usesPost ? { showLocalReminder = false } : nil)
            } else if let account, let session = account.session {
                ConnectedMainView(account: account, session: session) { showSettings = true }
                    .id(session.sessionId)
            } else {
                NavigationStack { recoveryHome.toolbar { settingsButton } }
            }
        }
        .overlay {
            if scenePhase != .active && usesPost {
                Palette.navy.ignoresSafeArea().overlay(Text("Buddy Checks").font(.title).foregroundStyle(.white))
            }
        }
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                settings
                    .toolbar { ToolbarItem(placement: .topBarLeading) {
                        Button("Done") { browser.cancel(); showSettings = false }.tint(Palette.navy)
                    } }
            }
            .overlay {
                if scenePhase != .active && usesPost {
                    Palette.navy.ignoresSafeArea().overlay(Text("Buddy Checks").font(.title).foregroundStyle(.white))
                }
            }
            .alert("Couldn't finish that action", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) { error = nil }
            } message: { Text(error ?? "Try again.") }
            .confirmationDialog("Sign out of the Post?", isPresented: $confirmSignOut, titleVisibility: .visible) {
                Button("Sign out and remove unfinished work", role: .destructive) { Task { await signOut() } }
            } message: { Text("Unsent drafts, pending submissions and this account's phone alerts will be removed from this iPhone. Checks already accepted by the Post will remain there.") }
        }
        .task { await initialize() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background && !browser.isActive { account?.lock() }
            if phase == .active && !browser.isActive && !busy && account != nil {
                Task {
                    if account?.session == nil { await restore() }
                    else { await account?.reminders?.refresh() }
                }
            }
        }
        .onChange(of: ReminderInbox.shared.link) { _, link in
            if link?.namespace.hasPrefix("connected.") == true {
                showLocalReminder = false; showSettings = false; connectionRequested = true
            }
        }
        .alert("Couldn't finish that action", isPresented: Binding(get: { error != nil && !showSettings }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) { error = nil }
        } message: { Text(error ?? "Try again.") }
    }

    private var settingsButton: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Account and Post settings", systemImage: "person.crop.circle") { showSettings = true }
        }
    }
    private var recoveryHome: some View {
        Page {
            SectionTitle(account?.needsSignIn == true || account == nil ? "Sign in to your Post" : "Reconnect to your Post")
            Text("Connect to your Post to continue.")
            Button("Sign in") { showSettings = true }.buttonStyle(ActionStyle()).disabled(busy)
            if account != nil {
                Button(busy ? "Connecting…" : "Retry connection") { Task { await restore() } }
                    .buttonStyle(ActionStyle(primary: false)).disabled(busy)
            }
            if let status { Text(status) }
        }.navigationTitle("Buddy Checks")
    }
    private var settings: some View {
        Page {
            if let session = account?.session {
                WorkingSurface {
                    SectionTitle("Profile")
                    Text(session.user.name)
                }
                WorkingSurface {
                    SectionTitle("Post")
                    Text(session.installation.name)
                    Text(session.installation.issuer).font(.footnote).textSelection(.enabled)
                }
            } else {
                SectionTitle(account?.needsSignIn == true ? "Sign in to your Post" : "Connect your Post")
                if account?.hasStoredAccount == true {
                    Text("Sign in with the same account to continue your unfinished work.")
                }
                if ReminderInbox.shared.link?.namespace.hasPrefix("connected.") == true {
                    Text("Sign in to open your follow-up reminder.")
                }
                WorkingSurface {
                    Text("Post website").font(.headline)
                    TextField("https://members.example.org", text: $issuer).keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Post website").frame(minHeight: 48)
                    Text("App ID supplied by your Post").font(.headline)
                    TextField("Public app ID", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel("Public app ID").frame(minHeight: 48)
                }.disabled(account?.hasStoredAccount == true || busy)
                Button(busy ? "Connecting…" : "Sign in") { Task { await signIn() } }
                    .buttonStyle(ActionStyle()).disabled(busy || issuer.isEmpty || clientID.isEmpty)
                    .accessibilityIdentifier("post-sign-in")
                DisclosureGroup("Post setup details") {
                    Text("The Post must enable mobile access and supply its registered public app ID. Register this callback for this build:")
                    Text(callback.absoluteString).textSelection(.enabled).font(.footnote)
                }
            }
            if account?.hasStoredAccount == true {
                Button("Sign out", role: .destructive) { confirmSignOut = true }
                    .frame(minHeight: 48).foregroundStyle(Palette.red).disabled(busy)
            }
            if account?.reminderRemovalUnconfirmed == true {
                Text("A phone alert may remain. Reopen the app to retry removing it.")
            }
            if let status { Text(status) }
        }.navigationTitle("Account and Post")
    }

    private func initialize() async {
        guard !initialized else { return }
        defer { initialized = true }
        #if DEBUG && !targetEnvironment(simulator)
        do {
            if let testAccount = try await PhysicalPhoneFixture.accountIfEnabled() {
                account = testAccount; connectionRequested = true; return
            }
        } catch { self.error = safeMessage(error); connectionRequested = true; return }
        #endif
        #if DEBUG
        if ProcessInfo.processInfo.environment["BUDDY_CHECKS_CONNECTED_FIXTURE"] == "1" || SyntheticConnectedFixture.reminderTestingEnabled {
            connectionRequested = true
            do { account = try await SyntheticConnectedFixture.account() }
            catch { self.error = safeMessage(error) }
            return
        }
        #endif
        if !issuer.isEmpty && !clientID.isEmpty { await restore() }
        if ReminderInbox.shared.link?.namespace.hasPrefix("connected.") == true { connectionRequested = true }
    }
    private func makeAccount() throws -> ConnectedAccount {
        guard let origin = URL(string: issuer.trimmingCharacters(in: .whitespacesAndNewlines)) else { throw ClientError.invalidConfiguration }
        let configuration = try ConnectionConfiguration(issuer: origin, clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines), redirectURI: callback)
        let vault = DeviceKeychain()
        let journal = EncryptedJournal(directory: URL.applicationSupportDirectory.appendingPathComponent("BuddyChecks/Connected", isDirectory: true), vault: vault)
        let client: BuddyCheckClient
        #if DEBUG && targetEnvironment(simulator) && BUDDY_CHECKS_PRIVATE_INTEGRATION
        let testEnvironment = ProcessInfo.processInfo.environment
        let activeDiagnostics = ["BUDDY_CHECKS_LIVE_REVOKE_EDITOR", "BUDDY_CHECKS_LIVE_DROP_ACCEPTED_RESPONSE", "BUDDY_CHECKS_LIVE_STALE_CORRECTION", "BUDDY_CHECKS_LIVE_AUTHORITY_OBSERVE", "BUDDY_CHECKS_LIVE_REMINDER_OBSERVE", "BUDDY_CHECKS_LIVE_DROP_RENEWAL"]
            .filter { testEnvironment[$0] == "1" }
        guard activeDiagnostics.count <= 1 else { throw ClientError.invalidConfiguration }
        if testEnvironment["BUDDY_CHECKS_LIVE_DROP_RENEWAL"] == "1" {
            client = BuddyCheckClient(configuration: configuration, transport: try LiveRenewalLossTransport(configuration: configuration))
        } else if testEnvironment["BUDDY_CHECKS_LIVE_AUTHORITY_OBSERVE"] == "1" {
            client = BuddyCheckClient(configuration: configuration, transport: try LiveAuthorityObservationTransport(configuration: configuration))
        } else if testEnvironment["BUDDY_CHECKS_LIVE_STALE_CORRECTION"] == "1" {
            client = BuddyCheckClient(configuration: configuration, transport: try LiveStaleCorrectionTransport(configuration: configuration))
        } else if testEnvironment["BUDDY_CHECKS_LIVE_REVOKE_EDITOR"] == "1" {
            client = BuddyCheckClient(configuration: configuration, transport: try LiveEditorRevocationTransport(configuration: configuration))
        } else if testEnvironment["BUDDY_CHECKS_LIVE_DROP_ACCEPTED_RESPONSE"] == "1" {
            client = BuddyCheckClient(configuration: configuration, transport: try LiveResponseLossTransport(configuration: configuration))
        } else { client = BuddyCheckClient(configuration: configuration) }
        #else
        client = BuddyCheckClient(configuration: configuration)
        #endif
        #if DEBUG && targetEnvironment(simulator) && BUDDY_CHECKS_PRIVATE_INTEGRATION
        if testEnvironment["BUDDY_CHECKS_LIVE_REMINDER_OBSERVE"] == "1" {
            return ConnectedAccount(client: client, vault: vault, persistence: journal,
                                    reminderScheduler: try LiveReminderObservationScheduler.factory(configuration: configuration))
        }
        #endif
        return ConnectedAccount(client: client, vault: vault, persistence: journal,
                                reminderScheduler: { SystemReminderScheduler(namespace: $0) })
    }
    private func restore() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { if account == nil { account = try makeAccount() }; try await account?.restore() }
        catch { self.error = safeMessage(error) }
    }
    private func signIn() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            if account?.hasStoredAccount != true { account = try makeAccount() }
            if let account { try await browser.authorize(account) }
            connectionRequested = true; showLocalReminder = false; showSettings = false
        } catch let failure as ASWebAuthenticationSessionError where failure.code == .canceledLogin {
            status = "Sign-in cancelled."
        } catch { self.error = safeMessage(error) }
    }
    private func signOut() async {
        busy = true; defer { busy = false }
        do {
            let revoked = try await account?.signOut() ?? true
            status = revoked ? "Signed out." : "Signed out on this iPhone. The Post could not confirm session revocation. You can end mobile sessions from your Post account."
            if account?.reminderRemovalUnconfirmed == true {
                status = (status ?? "") + " A phone alert may remain. Reopen the app to retry removing it."
            }
            ReminderInbox.shared.link = nil
            account = nil; connectionRequested = true
        } catch { self.error = safeMessage(error) }
    }
}

func safeMessage(_ error: Error) -> String {
    (error as? ClientError)?.errorDescription ?? "The action could not finish. Your previous work is retained. Try again."
}
