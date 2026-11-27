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
        let store = Store.preview()
        let empty = Store(previewDocs: [:])
        let router = Router()
        let callDeal = try XCTUnwrap(store.deal("sample-call"))

        let oasisBalcony = DealFilters(shipClasses: ["oasis", "icon"], cabinTypes: ["balcony"])
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
            ("12-my-trip", AnyView(TripEditor(start: Samples.trip)), true, store),
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
