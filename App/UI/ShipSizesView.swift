import SwiftUI
import UIKit

// MARK: - Photo cache

/// Ship photos, fetched once from the deal server with the app token and kept in memory and in Caches.
@MainActor
final class ShipPhotoCache {
    static let shared = ShipPhotoCache()

    private var images: [String: UIImage] = [:]
    private var loading: [String: Task<UIImage?, Never>] = [:]

    func image(for photo: ShipPhoto, store: Store) async -> UIImage? {
        if let hit = images[photo.key] { return hit }
        if let running = loading[photo.key] { return await running.value }
        let file = ShipPhotoCache.fileURL(photo)
        let task = Task<UIImage?, Never> { @MainActor in
            if let file, let data = try? Data(contentsOf: file), let image = UIImage(data: data) { return image }
            guard let data = await store.shipPhotoData(photo), let image = UIImage(data: data) else { return nil }
            if let file { try? data.write(to: file, options: .atomic) }
            return image
        }
        loading[photo.key] = task
        let image = await task.value
        loading[photo.key] = nil
        if let image { images[photo.key] = image }
        return image
    }

    private static func fileURL(_ photo: ShipPhoto) -> URL? {
        guard let base = try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true) else { return nil }
        let folder = base.appendingPathComponent("ShipPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = Slug.plain(photo.key.replacingOccurrences(of: "|", with: "-"))
        guard !name.isEmpty else { return nil }
        return folder.appendingPathComponent("\(name).jpg")
    }
}

/// One cropped side-on photo at a given width. Until it loads (or when it can't), a plain bar of the same length.
struct ShipPhotoImage: View {
    let photo: ShipPhoto?
    let width: CGFloat
    var label: String = "Ship"
    @EnvironmentObject private var store: Store
    @State private var image: UIImage?
    @State private var tried = false

    private var barHeight: CGFloat {
        let aspect = photo?.aspect ?? 6.5
        return max(width / CGFloat(max(aspect, 1)), 6)
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: max(width, 1))
            } else {
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(width: max(width, 1), height: barHeight)
                    .overlay(alignment: .leading) {
                        if photo != nil && !tried {
                            ProgressView()
                                .controlSize(.mini)
                                .padding(.leading, 6)
                        } else if photo == nil && width > 120 {
                            Text("no free side-on photo found")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 6)
                                .lineLimit(1)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(label))
        .task(id: photo?.key ?? "none") {
            guard let photo else {
                tried = true
                return
            }
            image = await ShipPhotoCache.shared.image(for: photo, store: store)
            tried = true
        }
    }
}

// MARK: - What gets drawn

/// One row of the size board: a class (every ship named), the length it is drawn at, and its photo.
struct ShipSizeEntry: Identifiable, Hashable {
    let group: ShipClassGroup
    let photo: ShipPhoto?
    let lengthFt: Double?
    /// The ship whose length the row is drawn at (the one in the photo when it is of this class).
    let drawn: String?

    var id: String { group.id }

    static func make(_ group: ShipClassGroup, manifest: ShipPhotoManifest) -> ShipSizeEntry {
        let photo = manifest.photo(for: group)
        let inPhoto = photo?.shipInPhoto?.trimmed
        let drawnShip = group.ships.first { ship in
            guard let inPhoto, let name = ship.name else { return false }
            return Slug.ship(name) == Slug.ship(inPhoto)
        } ?? group.ships.max { ($0.lengthFt ?? 0) < ($1.lengthFt ?? 0) }
        let length = photo?.lengthFt ?? drawnShip?.lengthFt ?? group.lengthFt
        return ShipSizeEntry(group: group, photo: photo, lengthFt: length, drawn: drawnShip?.name ?? inPhoto)
    }

    /// "1,198 ft · 3.3 football fields · 5,610 guests"
    var figure: String {
        guard let lengthFt else { return "length not published yet" }
        var text = ShipScale.lengthText(lengthFt)
        if let guests = group.passengers {
            text += " · \(Fmt.usd(guests).replacingOccurrences(of: "$", with: "")) guests"
        }
        return text
    }
}

// MARK: - The Ship sizes screen (mirrors the web page)

/// Every class of every line, drawn to one scale from real side-on photos (Wikimedia Commons, cropped bow to stern
/// at the waterline), so widths are true lengths. The ship Jim sailed last is pinned on top as the yardstick;
/// a feet ruler with football-field marks runs above. Each class names every one of its ships.
struct ShipSizesView: View {
    @EnvironmentObject private var store: Store
    @State private var manifest = ShipPhotoManifest()
    @State private var loaded = false
    @State private var lines: Set<String> = []
    @State private var shown: ShipRef?

    private var lineOptions: [String] {
        store.catalog.lineNames.filter { !store.catalog.classGroups(line: $0).isEmpty }
    }

    private var entries: [ShipSizeEntry] {
        let wanted = lines.isEmpty ? Set(lineOptions) : lines
        return store.catalog.allClassGroups
            .filter { wanted.contains($0.line) }
            .map { ShipSizeEntry.make($0, manifest: manifest) }
            .sorted { ($0.lengthFt ?? 0, $1.group.name) > ($1.lengthFt ?? 0, $0.group.name) }
    }

    private var yardstick: (entry: ShipSizeEntry, ship: String, trip: PastTrip?)? {
        guard let ref = store.yardstick, let group = store.catalog.classGroup(line: ref.line, ship: ref.name) else {
            return nil
        }
        let entry = ShipSizeEntry.make(group, manifest: manifest)
        guard entry.lengthFt != nil else { return nil }
        return (entry, ref.name, store.trips.first)
    }

    var body: some View {
        GeometryReader { proxy in
            let drawWidth = max(proxy.size.width - 32 - 24, 200)
            let all = entries
            let maxLen = max(all.compactMap { $0.lengthFt }.max() ?? 0, yardstick?.entry.lengthFt ?? 0, 400)
            let k = drawWidth / CGFloat(maxLen)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    intro
                    ChipPicker(options: lineOptions.map { ReasonOption(id: $0, title: $0) }, selection: $lines)
                    Text(lines.isEmpty ? "Every line shown. Pick lines to narrow it." : "Showing \(ListText.join(lineOptions.filter { lines.contains($0) })).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !loaded {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Fetching the ship photos…").foregroundStyle(.secondary)
                        }
                    } else if manifest.isEmpty && all.allSatisfy({ $0.lengthFt == nil }) {
                        IllustratedEmpty(title: "Ship photos are on their way",
                                         message: "The deal server doesn't hold the side-on photos and lengths yet. They show here, drawn to scale, as soon as it does.")
                    } else {
                        ShipRuler(maxFeet: maxLen, pointsPerFoot: k, width: drawWidth)
                            .frame(height: 40)
                            .padding(.horizontal, 12)
                            .accessibilityHidden(true)
                        if let mine = yardstick {
                            sizeRow(mine.entry, k: k, mine: mine.ship, trip: mine.trip)
                        }
                        ForEach(tiers(all), id: \.title) { tier in
                            VStack(alignment: .leading, spacing: 14) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tier.title)
                                        .font(.title3.weight(.bold))
                                    Text(tier.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isHeader)
                                ForEach(tier.rows) { entry in
                                    sizeRow(entry, k: k, mine: nil, trip: nil)
                                }
                            }
                            .padding(.top, 6)
                        }
                        credits(all)
                    }
                }
                .padding(16)
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Ship sizes")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            manifest = await store.shipPhotos()
            loaded = true
        }
        .sheet(item: $shown) { ref in
            ShipSheet(ref: ref)
        }
    }

    private var intro: some View {
        Text("Real side-on photos of every class, cropped bow to stern at the waterline and drawn to one scale, so widths are true lengths. Tap a ship's name to open it.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private struct Tier {
        let title: String
        let subtitle: String
        let rows: [ShipSizeEntry]
    }

    private func tiers(_ all: [ShipSizeEntry]) -> [Tier] {
        var out: [Tier] = []
        for size in ShipSize.allCases.reversed() {
            let rows = all.filter { $0.group.tier == size && $0.lengthFt != nil }
            guard !rows.isEmpty else { continue }
            out.append(Tier(title: size.title, subtitle: "\(size.tonnage) · \(rows.count == 1 ? "1 class" : "\(rows.count) classes")",
                            rows: rows))
        }
        let unknown = all.filter { $0.lengthFt == nil || $0.group.tier == nil }
        if !unknown.isEmpty {
            out.append(Tier(title: "Size not published yet",
                            subtitle: unknown.count == 1 ? "1 class" : "\(unknown.count) classes", rows: unknown))
        }
        return out
    }

    @ViewBuilder
    private func sizeRow(_ entry: ShipSizeEntry, k: CGFloat, mine: String?, trip: PastTrip?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if mine != nil {
                Text("YOUR YARDSTICK")
                    .font(.caption2.weight(.bold))
                    .tracking(0.6)
                    .foregroundStyle(Palette.highlight)
            }
            Text(mine ?? entry.group.title)
                .font(.headline)
            if mine != nil {
                Text([entry.group.line, entry.group.title, trip.flatMap { t in t.sailDay.map { "you sailed her \(Fmt.shortDay($0))" } }]
                    .compactMap { $0 }.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text(entry.group.line)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                ClassShipsLine(group: entry.group, current: entry.drawn) { ref in shown = ref }
            }
            Text(entry.figure)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            if let length = entry.lengthFt {
                ShipPhotoImage(photo: entry.photo, width: CGFloat(length) * k,
                               label: "\(entry.photo?.shipInPhoto ?? entry.group.title), side view, drawn \(Int(length)) feet long")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(mine != nil ? Palette.highlight.opacity(0.12) : Palette.card))
    }

    @ViewBuilder
    private func credits(_ all: [ShipSizeEntry]) -> some View {
        let used = all.compactMap { $0.photo }.sorted { $0.key < $1.key }
        if !used.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Photo credits (Wikimedia Commons)")
                    .font(.footnote.weight(.semibold))
                Text("Each photo is cropped at the bow, the stern and the waterline, then sized to the ship's length, so lengths compare exactly; heights follow the photo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ForEach(used) { photo in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(photo.line) · \(photo.className): \(photo.credit)")
                            .font(.caption)
                        if let link = photo.commonsLink {
                            Link("Source", destination: link)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 10)
        }
    }
}

/// Feet along the top, football fields (360 ft) below.
struct ShipRuler: View {
    let maxFeet: Double
    let pointsPerFoot: CGFloat
    let width: CGFloat

    var body: some View {
        Canvas { context, size in
            let k = pointsPerFoot
            let end = CGFloat(maxFeet) * k
            var base = Path()
            base.move(to: CGPoint(x: 0, y: 20))
            base.addLine(to: CGPoint(x: min(end, size.width), y: 20))
            context.stroke(base, with: .color(.secondary), lineWidth: 1)
            let step: Double = maxFeet > 900 ? 200 : 100
            var feet: Double = 0
            while feet <= maxFeet {
                let x = CGFloat(feet) * k
                let major = feet.truncatingRemainder(dividingBy: step) == 0
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: major ? 12 : 16))
                tick.addLine(to: CGPoint(x: x, y: 20))
                context.stroke(tick, with: .color(.secondary), lineWidth: 1)
                if major {
                    let label = feet == 0 ? "0 ft" : Fmt.usd(Int(feet)).replacingOccurrences(of: "$", with: "")
                    context.draw(Text(label).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary),
                                 at: CGPoint(x: x, y: 5), anchor: feet == 0 ? .leading : .center)
                }
                feet += step / 2
            }
            var field = 1
            while Double(field) * ShipScale.fieldFeet <= maxFeet {
                let x = CGFloat(Double(field) * ShipScale.fieldFeet) * k
                var tick = Path()
                tick.move(to: CGPoint(x: x, y: 22))
                tick.addLine(to: CGPoint(x: x, y: 28))
                context.stroke(tick, with: .color(Palette.accent), lineWidth: 1.5)
                context.draw(Text(field == 1 ? "1 field" : "\(field) fields").font(.system(size: 10)).foregroundStyle(Palette.accent),
                             at: CGPoint(x: x, y: 35), anchor: .center)
                field += 1
            }
        }
        .frame(width: width)
    }
}

// MARK: - The small to-scale strip on a deal, a tracked sailing and a sheet

/// This ship's class photo beside the ship Jim sailed last, at one scale. A host adds it only when
/// `ShipScaleStrip.available` says there is a photo and a length to draw.
struct ShipScaleStrip: View {
    let line: String
    let ship: String
    @EnvironmentObject private var store: Store

    struct Item: Identifiable {
        let title: String
        let entry: ShipSizeEntry
        var id: String { title }
    }

    @MainActor
    static func items(_ store: Store, line: String, ship: String) -> [Item] {
        guard let manifest = store.shipManifest, !manifest.isEmpty,
              let group = store.catalog.classGroup(line: line, ship: ship) else { return [] }
        let mine = ShipSizeEntry.make(group, manifest: manifest)
        guard mine.lengthFt != nil, mine.photo != nil else { return [] }
        var out = [Item(title: ship, entry: mine)]
        if let ref = store.yardstick, let other = store.catalog.classGroup(line: ref.line, ship: ref.name),
           other.id != group.id {
            let entry = ShipSizeEntry.make(other, manifest: manifest)
            if entry.lengthFt != nil { out.append(Item(title: "\(ref.name) (you sailed her)", entry: entry)) }
        }
        return out
    }

    @MainActor
    static func available(_ store: Store, line: String, ship: String?) -> Bool {
        guard let ship, !ship.trimmed.isEmpty else { return false }
        return !items(store, line: line, ship: ship).isEmpty
    }

    var body: some View {
        let list = ShipScaleStrip.items(store, line: line, ship: ship)
        if !list.isEmpty {
            let maxLen = list.compactMap { $0.entry.lengthFt }.max() ?? 1
            VStack(alignment: .leading, spacing: 8) {
                Text("To scale")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(list) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(item.title) · \(item.entry.lengthFt.map { ShipScale.lengthText($0) } ?? "")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        StripPhoto(photo: item.entry.photo, fraction: (item.entry.lengthFt ?? 0) / maxLen,
                                   label: "\(item.title), side view")
                    }
                }
                if let photo = list.first?.entry.photo {
                    Text("Photo: \(photo.credit) · Wikimedia Commons")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                NavigationLink {
                    ShipSizesView()
                } label: {
                    Text("Compare every class")
                        .font(.footnote.weight(.semibold))
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// A strip photo sized as a fraction of the container's width.
private struct StripPhoto: View {
    let photo: ShipPhoto?
    let fraction: Double
    let label: String

    var body: some View {
        // The frame is as tall as the photo drawn at `fraction` of the row's width.
        GeometryReader { proxy in
            ShipPhotoImage(photo: photo, width: proxy.size.width * CGFloat(min(max(fraction, 0.05), 1)), label: label)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .aspectRatio(CGFloat(photo?.aspect ?? 6.5) / CGFloat(min(max(fraction, 0.05), 1)), contentMode: .fit)
    }
}
