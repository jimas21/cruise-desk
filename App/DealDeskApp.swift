import SwiftUI

@main
struct DealDeskApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = Store.shared
    @StateObject private var router = Router.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(router)
                .tint(Palette.accent)
                .onOpenURL { url in
                    router.handle(url: url)
                }
        }
    }
}

/// Five tabs: Deals (the inbox), Tracking, Reviewed, Save, Rules.
struct RootView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var router: Router
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $router.tab) {
            DealsView()
                .tabItem { Label("Deals", systemImage: "ferry") }
                .badge(store.unansweredCount)
                .tag(AppTab.deals)
            TrackingView()
                .tabItem { Label("Tracking", systemImage: "binoculars") }
                .tag(AppTab.tracking)
            ReviewedView()
                .tabItem { Label("Reviewed", systemImage: "checkmark.circle") }
                .tag(AppTab.reviewed)
            SaveView()
                .tabItem { Label("Save", systemImage: "tag") }
                .tag(AppTab.save)
            RulesView()
                .tabItem { Label("Rules", systemImage: "slider.horizontal.3") }
                .tag(AppTab.rules)
        }
        .task {
            await store.refresh(reason: .open)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: store.foregrounded()
            case .background: store.backgrounded()
            default: break
            }
        }
        .sheet(item: $router.trackSeed) { seed in
            TrackBuilder(seed: seed)
        }
        .alert("Heads up", isPresented: noticeShown) {
            Button("OK", role: .cancel) { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
    }

    private var noticeShown: Binding<Bool> {
        Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
    }
}

#Preview("App") {
    RootView()
        .environmentObject(Store.preview())
        .environmentObject(Router())
}
