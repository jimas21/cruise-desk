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
        let router = Router()
        let callDeal = try XCTUnwrap(store.deal("sample-call"))

        let screens: [(name: String, view: AnyView, dark: Bool)] = [
            ("01-deals", AnyView(RootView()), true),
            ("02-deals-large-text", AnyView(RootView().environment(\.dynamicTypeSize, .accessibility2)), false),
            ("03-detail-fits", AnyView(NavigationStack { DealDetailView(dealId: "sample-fits") }), true),
            ("04-detail-answered", AnyView(NavigationStack { DealDetailView(dealId: "sample-drop") }), false),
            ("05-detail-sale", AnyView(NavigationStack { DealDetailView(dealId: "sample-sale") }), false),
            ("06-answer-pass", AnyView(AnswerSheet(deal: callDeal, verdict: .pass, existing: nil)), true),
            ("07-reviewed", AnyView(ReviewedView()), false),
            ("08-save", AnyView(SaveView()), true),
            ("09-play", AnyView(NavigationStack { PlayDetailView(playId: "sample-live") }), false),
            ("10-rules", AnyView(RulesView()), true),
            ("11-status", AnyView(StatusSheet()), false),
            ("12-settings", AnyView(NavigationStack { SettingsView() }), false),
        ]

        for screen in screens {
            let styles: [UIUserInterfaceStyle] = screen.dark ? [.light, .dark] : [.light]
            for style in styles {
                let view = screen.view
                    .environmentObject(store)
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
