import SwiftUI
import AuthenticationServices

// MARK: - AccountView

struct AccountView: View {
    @ObservedObject var syncManager: BackendSyncManager

    @State private var email: String = ""
    @State private var password: String = ""
    @State private var isShowingEmailForm: Bool = false
    @State private var isSignUp: Bool = false
    @State private var errorMessage: String? = nil
    @State private var isLoading: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.system(size: 40))
                        .foregroundColor(.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Account")
                            .font(.title2.bold())
                        syncStatusLine
                    }
                    Spacer()
                }
                .padding(.bottom, 4)

                if !syncManager.isConfigured {
                    unconfiguredNotice
                } else {
                    switch syncManager.authState {
                    case .signedOut:
                        signedOutView
                    case .signedIn(let userEmail):
                        signedInView(email: userEmail)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: Sync status line

    private var syncStatusLine: some View {
        HStack(spacing: 6) {
            switch syncManager.syncStatus {
            case .idle:
                Image(systemName: "circle.fill")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Not synced yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .syncing:
                ProgressView()
                    .scaleEffect(0.6)
                Text("Syncing…")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .success(let date):
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.green)
                Text("Synced \(date.relativeDescription)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .failed(let msg):
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("Sync failed: \(msg)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: Unconfigured notice

    private var unconfiguredNotice: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Backend not configured", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundColor(.orange)

            Text("Add your Supabase credentials to enable cloud sync and account features.")
                .foregroundColor(.secondary)

            Text("Set **SUPABASE_URL** and **SUPABASE_ANON_KEY** in your environment or in `supabase-config.plist`.")
                .font(.callout)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
    }

    // MARK: Signed out

    private var signedOutView: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sign in to sync your stats and achievements across devices.")
                .foregroundColor(.secondary)

            // Sign in with Apple
            signInWithAppleButton
                .frame(height: 44)
                .frame(maxWidth: 280)

            // Divider
            HStack {
                Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
                Text("or").font(.caption).foregroundColor(.secondary)
                Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3))
            }
            .frame(maxWidth: 280)

            // Email / password toggle
            if isShowingEmailForm {
                emailPasswordForm
                    .frame(maxWidth: 280)
            } else {
                Button(action: { withAnimation { isShowingEmailForm = true } }) {
                    Text("Continue with email")
                        .frame(maxWidth: 280)
                }
                .buttonStyle(.bordered)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .frame(maxWidth: 280)
            }

            Text("Your local data is never deleted when signing in or out.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var signInWithAppleButton: some View {
        SignInWithAppleButton(
            isSignUp ? .signUp : .signIn,
            onRequest: { request in
                request.requestedScopes = [.email]
            },
            onCompletion: { result in
                handleAppleSignInResult(result)
            }
        )
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
    }

    private var emailPasswordForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $isSignUp) {
                Text("Sign in").tag(false)
                Text("Create account").tag(true)
            }
            .pickerStyle(.segmented)

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)

            SecureField("Password", text: $password)
                .textFieldStyle(.roundedBorder)

            Button(action: submitEmailPassword) {
                HStack {
                    if isLoading { ProgressView().scaleEffect(0.7) }
                    Text(isSignUp ? "Create account" : "Sign in")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(email.isEmpty || password.isEmpty || isLoading)
        }
    }

    // MARK: Signed in

    private func signedInView(email: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 32))
                    .foregroundColor(.green)
                VStack(alignment: .leading) {
                    Text("Signed in")
                        .font(.headline)
                    if let email = email {
                        Text(email)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Text("Your keystrokes, clicks, and achievements are being synced to the cloud.")
                .foregroundColor(.secondary)

            Button(role: .destructive) {
                Task { await syncManager.signOut() }
            } label: {
                Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Helpers

    @Environment(\.colorScheme) private var colorScheme

    private func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let token = String(data: tokenData, encoding: .utf8)
            else {
                errorMessage = "Could not extract Apple identity token."
                return
            }
            isLoading = true
            Task {
                // BackendSyncManager handles the Supabase sign-in
                // We use a notification/state observation pattern via @Published authState
                await syncManager.completeAppleSignIn(token: token)
                isLoading = false
            }
        case .failure(let error):
            errorMessage = error.localizedDescription
        }
    }

    private func submitEmailPassword() {
        errorMessage = nil
        isLoading = true
        Task {
            do {
                if isSignUp {
                    try await syncManager.signUp(email: email, password: password)
                } else {
                    try await syncManager.signIn(email: email, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

// MARK: - Date extension

private extension Date {
    var relativeDescription: String {
        let seconds = -timeIntervalSinceNow
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        return "\(Int(seconds / 3600))h ago"
    }
}
