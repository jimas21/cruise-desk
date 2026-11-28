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

    /// "Drinks, Wi-Fi · cabin budget"
    private var tripCostSummary: String {
        let kinds = (store.trip?.buyKinds ?? []).map { AddonKind.title($0) }
        let basis = store.trip?.budgetBasis == "trip" ? "whole-trip budget" : "cabin budget"
        return kinds.isEmpty ? "nothing extra · \(basis)" : "\(ListText.join(kinds)) · \(basis)"
    }

    var body: some View {
        Form {
            Section {
                TextField(Self.addressPrompt, text: $address)
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
                InfoRow(label: "Deal server", value: levelText)
                NavigationLink {
                    LinesView()
                } label: {
                    ValueLabel(label: "My Lines", value: store.isV3 ? (store.trip?.linesSummary ?? CruiseLine.royal)
                                                                   : "coming soon")
                }
                if store.has(.sheet) {
                    NavigationLink {
                        TripCostSettingsView()
                    } label: {
                        ValueLabel(label: "Trip cost", value: tripCostSummary)
                    }
                }
                if store.catalog.isV5 {
                    NavigationLink {
                        ShipSizesView()
                    } label: {
                        Text("Ship sizes")
                    }
                }
            } header: {
                Text("Lines and tracking")
            } footer: {
                Text(store.isV3
                     ? "Opening the app asks the deal server for a fresh look at the sources that allow it, at most every 5 minutes."
                     : "Any cruise line, tracking and per-line coverage switch on by themselves once the deal server's next update lands.")
            }

            bookingSection

            Section {
                InfoRow(label: "Deals on this phone", value: String(store.cachedDealCount))
                if store.isV3 {
                    InfoRow(label: "Tracked sailings", value: String(store.tracked.count))
                }
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
                InfoRow(label: "Version", value: AppVersion.display)
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

    private static let addressPrompt: String = "Server address, https://…"

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

    private var levelText: String {
        switch store.level {
        case .v3: return store.v4Features.isEmpty ? "Lines and tracking on" : "Lines, tracking, booking and search on"
        case .v2: return "Tracking coming soon"
        case .unknown: return "Checking…"
        }
    }

    /// v4 (CONTRACT_V4 section 1.7): where the Book button goes. It is always the sailing's own line; with best
    /// value, the cheapest known agency for that cabin is also listed under it.
    @ViewBuilder
    private var bookingSection: some View {
        if store.has(.booking) {
            Section {
                Picker("Book through", selection: bookingBinding) {
                    ForEach(BookingPreference.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .disabled(store.trip == nil)
            } header: {
                Text("Booking")
            } footer: {
                Text(store.trip == nil
                     ? "Save My Trip first; this setting lives with it."
                     : BookingPreference(raw: store.trip?.bookingPreference).detail + " The Book button opens Safari, so your own sign-in on the line's site applies.")
            }
        }
    }

    private var bookingBinding: Binding<BookingPreference> {
        Binding(get: { BookingPreference(raw: store.trip?.bookingPreference) },
                set: { store.setBookingPreference($0) })
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
