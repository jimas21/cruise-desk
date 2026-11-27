import SwiftUI
import UIKit
import XCTest
@testable import DealDesk

/// Renders every screen with the sample data, light and dark, to PNGs for review. Runs only when the compile
/// check sets TEST_RUNNER_SNAPSHOT_DIR (the files are uploaded as the run's "screenshots" artifact).
@MainActor
final class SnapshotTests: XCTestCase {
    func testScreens() async throws {
        guard let dir = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], !dir.isEmpty else {
            throw XCTSkip("Set TEST_RUNNER_SNAPSHOT_DIR to write screenshots.")
        }
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        // The v2 store first: the last store made sets the catalog the screens read, and that should be v3's.
        let older = Store(previewDocs: Samples.docs, level: .v2)
        let store = Store.preview()
        let empty = Store(previewDocs: [:])
        // v4 last: its catalog is a superset of v3's.
        let v4 = Store.previewV4()
        let router = Router()
        let callDeal = try XCTUnwrap(store.deal("sample-call"))
        let iconPlan = try XCTUnwrap(v4.plan("plan-sample-icon"))
        let aquaTrip = try XCTUnwrap(v4.pastTrip("trip-sample-aqua"))
        let costaMaya = try XCTUnwrap(v4.ports?.port("costa-maya"))

        let oasisBalcony = DealFilters(shipClasses: ["oasis", "icon"], cabinTypes: ["balcony"])
        let celebrityLarge = DealFilters(lines: ["Celebrity"], sizes: ["large"])
        var nextStar = TrackPick()
        nextStar.ship = "Star of the Seas"
        nextStar.sailDate = Fmt.day("2027-06-26")
        nextStar.port = "Port Canaveral"
        nextStar.cabinName = "Ocean View Balcony"
        func detail(_ id: String, _ focus: DetailFocus? = nil) -> AnyView {
            AnyView(NavigationStack { DealDetailView(dealId: id, focus: focus) })
        }

        let screens: [(name: String, view: AnyView, dark: Bool, store: Store)] = [
            ("01-deals-best", AnyView(RootView()), true, store),
            ("02-deals-large-text", AnyView(RootView().environment(\.dynamicTypeSize, .accessibility2)), false, store),
            ("03-deals-for-my-trip", AnyView(DealsView(bucket: .trip)), true, store),
            ("04-detail-scoop", detail("sample-fits"), true, store),
            ("05-detail-price", detail("sample-fits", .price), true, store),
            ("06-detail-cabins", detail("sample-fits", .cabins), false, store),
            ("07-detail-itinerary", detail("sample-fits", .itinerary), true, store),
            ("08-detail-history", detail("sample-fits", .history), false, store),
            ("09-detail-ask", detail("sample-fits", .ask), true, store),
            ("10-detail-v1-deal", detail("sample-call"), false, store),
            ("11-detail-sale", detail("sample-sale"), true, store),
            ("12-my-trip", AnyView(TripEditor(start: Samples.tripV3)), true, store),
            ("13-filters", AnyView(FilterSheet(filters: .constant(oasisBalcony), deals: store.inbox)), false, store),
            ("14-ask-deal-desk", AnyView(AskSheet()), true, store),
            ("15-answer-pass", AnyView(AnswerSheet(deal: callDeal, verdict: .pass, existing: nil)), false, store),
            ("16-reviewed", AnyView(ReviewedView()), true, store),
            ("17-save", AnyView(SaveView()), false, store),
            ("18-play", AnyView(NavigationStack { PlayDetailView(playId: "sample-live") }), false, store),
            ("19-rules", AnyView(RulesView()), true, store),
            ("20-status", AnyView(StatusSheet()), false, store),
            ("21-settings", AnyView(NavigationStack { SettingsView() }), false, store),
            ("22-empty-deals", AnyView(RootView()), true, empty),
            ("23-empty-for-my-trip", AnyView(DealsView(bucket: .trip)), false, empty),
            ("24-my-trip-not-set-up", AnyView(TripEditor(start: TripPrefs(), isNew: true)), false, empty),
            // v3
            ("25-tracking", AnyView(TrackingView()), true, store),
            ("26-tracked-detail", AnyView(NavigationStack { TrackedDetailView(trackedId: "trk-sample-star") }), true, store),
            ("27-tracked-filling", AnyView(NavigationStack { TrackedDetailView(trackedId: "trk-sample-beyond") }), false, store),
            ("28-track-builder", AnyView(TrackBuilder(seed: TrackSeed(pick: nextStar, text: nil))), true, store),
            ("29-track-from-link", AnyView(TrackBuilder(seed: TrackSeed(pick: nil, text: Samples.sharedLink))), false, store),
            ("30-my-lines", AnyView(NavigationStack { LinesView(selection: .constant(["Royal Caribbean", "Celebrity"])) }),
             true, store),
            ("31-filters-lines-sizes", AnyView(FilterSheet(filters: .constant(celebrityLarge), deals: store.inbox,
                                                           myLines: ["Royal Caribbean", "Celebrity"])), false, store),
            ("32-detail-other-line", detail("sample-celebrity"), false, store),
            ("33-tracking-empty", AnyView(TrackingView()), false, empty),
            ("34-tracking-coming-soon", AnyView(TrackingView()), false, older),
            ("35-my-trip-older-server", AnyView(TripEditor(start: Samples.trip)), false, older),
            // v4
            ("36-deals-book-newsletters", AnyView(RootView()), true, v4),
            ("37-deals-book-large-text", AnyView(DealsView().environment(\.dynamicTypeSize, .accessibility2)), false, v4),
            ("38-newsletters", AnyView(DigestSheet()), true, v4),
            ("39-detail-book-on-line", detail("sample-fits"), true, v4),
            ("40-detail-book-exact", detail("sample-celebrity"), false, v4),
            ("41-search", AnyView(SearchView()), true, v4),
            ("42-search-filters", AnyView(SearchFiltersSheet(query: .constant(iconPlan.query))), false, v4),
            ("43-plan-editor", AnyView(PlanEditor(target: .edit(iconPlan))), false, v4),
            ("44-tracking-book", AnyView(TrackingView(side: .tracking)), true, v4),
            ("45-tracked-book", AnyView(NavigationStack { TrackedDetailView(trackedId: "trk-sample-star") }), false, v4),
            ("46-my-trips", AnyView(TrackingView(side: .trips)), true, v4),
            ("47-trip-ratings", AnyView(PastTripEditor(target: .edit(aquaTrip))), true, v4),
            ("48-add-a-trip", AnyView(PastTripEditor(target: .new)), false, v4),
            ("49-port-detail", AnyView(PortDetailView(port: costaMaya)), false, v4),
            ("50-settings-booking", AnyView(NavigationStack { SettingsView() }), false, v4),
            ("51-search-coming-soon", AnyView(SearchView()), false, store),
            ("52-my-trips-coming-soon", AnyView(TrackingView(side: .trips)), false, store),
        ]

        for screen in screens {
            let styles: [UIUserInterfaceStyle] = screen.dark ? [.light, .dark] : [.light]
            for style in styles {
                let view = screen.view
                    .environmentObject(screen.store)
                    .environmentObject(router)
                    .tint(Palette.accent)
                let image = try await render(view, style: style)
                let file = "\(screen.name)-\(style == .dark ? "dark" : "light").png"
                let data = try XCTUnwrap(image.pngData())
                try data.write(to: URL(fileURLWithPath: dir).appendingPathComponent(file))
            }
        }
    }

    private func render<V: View>(_ view: V, style: UIUserInterfaceStyle) async throws -> UIImage {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = scene.screen.bounds
        window.overrideUserInterfaceStyle = style
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        try await Task.sleep(nanoseconds: 900_000_000)
        let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
        let image = renderer.image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        window.isHidden = true
        window.rootViewController = nil
        return image
    }
}
