import SwiftUI
import UIKit
import UserNotifications

/// Recovery: paste a server address or app token (kept in the Keychain), test it, turn alerts on.
struct SettingsView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var address = ""
    @State private var token = ""
    @State private var result: String?
    @State private var testing = false
    @State private var alerts: UNAuthorizationStatus = .notDetermined

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                TextField("https://deals.example.org", text: $address)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField(Connection.isConfigured ? "Paste a new app token" : "Paste the app token", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Deal server")
            } footer: {
                Text(sourceNote)
            }

            Section {
                Button {
                    save()
                } label: {
                    HStack {
                        Text("Save and test")
                        Spacer()
                        if testing { ProgressView() }
                    }
                }
                .disabled(testing || !canSave)
                Button("Test connection") {
                    test()
                }
                .disabled(testing)
                if Connection.isCustom {
                    Button("Use the built-in settings", role: .destructive) {
                        Connection.clearCustom()
                        address = Connection.baseURL
                        token = ""
                        store.connectionChanged()
                        test()
                    }
                }
                if let result {
                    Text(result)
                        .font(.footnote)
                        .foregroundStyle(result == "Connected." ? Palette.fits : Palette.call)
                }
            }

            Section {
                InfoRow(label: "Alerts", value: alertsText)
                if alerts == .notDetermined {
                    Button("Turn on alerts") {
                        Task {
                            await Push.requestIfNeeded()
                            alerts = await Push.authorizationStatus()
                        }
                    }
                } else if alerts == .denied {
                    Button("Open iPhone Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                if let problem = store.pushProblem {
                    Text(problem).font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text("A tap on an alert opens that deal.")
            }

            Section {
                InfoRow(label: "Deals on this phone", value: String(store.cachedDealCount))
                if store.pendingCount > 0 {
                    InfoRow(label: "Waiting to send", value: String(store.pendingCount))
                }
                Button("Reload everything") {
                    store.reloadEverything()
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Deals are saved on this phone so the app opens instantly and works offline. Answers made offline are sent when you're back online.")
            }

            Section {
                InfoRow(label: "Version", value: version)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .task {
            address = Connection.baseURL
            alerts = await Push.authorizationStatus()
        }
    }

    private var canSave: Bool {
        let typed = address.trimmed
        let addressChanged = !typed.isEmpty && typed != Connection.baseURL
        return addressChanged || !token.trimmed.isEmpty
    }

    private var sourceNote: String {
        if !Connection.isConfigured { return "Not set up. Paste the server address and the app token." }
        if Connection.isCustom { return "Using the address or token you pasted. They stay on this phone, in the Keychain." }
        return "Using the address and token built into this version of the app."
    }

    private var alertsText: String {
        switch alerts {
        case .authorized, .provisional, .ephemeral: return "On"
        case .denied: return "Off"
        case .notDetermined: return "Not asked yet"
        @unknown default: return "Unknown"
        }
    }

    private func save() {
        let typed = address.trimmed
        if !typed.isEmpty, Connection.normalized(typed) == nil {
            result = "That address doesn't look right. It should start with https://"
            return
        }
        Connection.saveCustom(baseURL: typed, token: token)
        token = ""
        address = Connection.baseURL
        store.connectionChanged()
        test()
    }

    private func test() {
        testing = true
        result = nil
        Task {
            result = await store.testConnection()
            testing = false
        }
    }
}

#Preview("Settings") {
    NavigationStack {
        SettingsView()
    }
    .environmentObject(Store.preview())
}
