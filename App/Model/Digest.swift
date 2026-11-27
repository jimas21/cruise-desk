import Foundation

// MARK: - Newsletter digest (CONTRACT_V4 section 2)

/// What an item is about. A kind this version does not know reads as news.
enum DigestKind: String, CaseIterable {
    case deal, sale, news
    case priceDrop = "price_drop"
    case newSailing = "new_sailing"

    init(raw: String?) {
        self = DigestKind(rawValue: raw?.trimmed ?? "") ?? .news
    }

    var title: String {
        switch self {
        case .deal: return "Deal"
        case .sale: return "Sale"
        case .news: return "News"
        case .priceDrop: return "Price drop"
        case .newSailing: return "New sailing"
        }
    }

    var symbol: String {
        switch self {
        case .deal: return "tag"
        case .sale: return "percent"
        case .news: return "newspaper"
        case .priceDrop: return "arrow.down.circle"
        case .newSailing: return "sparkles"
        }
    }
}

struct DigestSource: Codable, Hashable {
    var name: String?
    var inboxId: String?
    var receivedAt: String?
}

struct DigestItem: Codable, Hashable, Identifiable {
    var id: String
    var kind: String?
    var headline: String?
    var summary: String?
    var link: String?
    var sources: [DigestSource]?
    var line: String?
    var ship: String?
    var sailDate: String?
    var nights: Int?
    var saleName: String?
    var pricePP: Int?
    var priceIncludesTaxes: Bool?
    var endsAt: String?
    var matchesTrip: Bool?
    var dealId: String?
    var trackedId: String?
    var firstSeenAt: String?
    var lastSeenAt: String?
    var booking: BookingInfo?

    enum CodingKeys: String, CodingKey {
        case id, kind, headline, summary, link, sources, line, ship, sailDate, nights, saleName, pricePP
        case priceIncludesTaxes, endsAt, matchesTrip, dealId, trackedId, firstSeenAt, lastSeenAt, booking
    }

    var kindValue: DigestKind { DigestKind(raw: kind) }
    var title: String {
        let text = headline?.trimmed ?? ""
        return text.isEmpty ? kindValue.title : text
    }
    var url: URL? { Fmt.webURL(link) }
    var fitsTrip: Bool { matchesTrip == true }

    /// "Vacations To Go", "Cruise Fever": who mentioned it, newest first.
    var sourceNames: [String] {
        var out: [String] = []
        for source in sources ?? [] {
            let name = source.name?.trimmed ?? ""
            if !name.isEmpty && !out.contains(name) { out.append(name) }
        }
        return out
    }

    /// "Icon of the Seas · Aug 15, 2027 · $1,154 pp · ends Dec 1"
    var factsLine: String {
        var parts: [String] = []
        if let ship = ship?.trimmed, !ship.isEmpty { parts.append(ship) }
        if let day = Fmt.day(sailDate) { parts.append(Fmt.fullDay(day)) }
        if let pp = pricePP, pp > 0 {
            parts.append(priceIncludesTaxes == true ? "\(Fmt.usd(pp)) pp · taxes in" : "\(Fmt.usd(pp)) pp")
        }
        if let ends = Fmt.day(endsAt) { parts.append("ends \(Fmt.deadline(ends))") }
        return parts.joined(separator: " · ")
    }
}

extension DigestItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(String.self, .id) ?? ""
        kind = c.lenient(String.self, .kind)
        headline = c.lenient(String.self, .headline)
        summary = c.lenient(String.self, .summary)
        link = c.lenient(String.self, .link)
        sources = c.lenient([DigestSource].self, .sources)
        line = c.lenient(String.self, .line)
        ship = c.lenient(String.self, .ship)
        sailDate = c.lenient(String.self, .sailDate)
        nights = c.lenient(Int.self, .nights)
        saleName = c.lenient(String.self, .saleName)
        pricePP = c.lenient(Int.self, .pricePP)
        priceIncludesTaxes = c.lenient(Bool.self, .priceIncludesTaxes)
        endsAt = c.lenient(String.self, .endsAt)
        matchesTrip = c.lenient(Bool.self, .matchesTrip)
        dealId = c.lenient(String.self, .dealId)
        trackedId = c.lenient(String.self, .trackedId)
        firstSeenAt = c.lenient(String.self, .firstSeenAt)
        lastSeenAt = c.lenient(String.self, .lastSeenAt)
        booking = c.lenient(BookingInfo.self, .booking).flatMap { $0.link == nil ? nil : $0 }
    }
}

/// One day's digest. Each day starts from the day before's live items, so ids carry over and "new" means new.
struct DigestDoc: Hashable {
    let id: String
    var date: String?
    var items: [DigestItem]
    var emailsRead: Int?
    var senders: [String]
    var updatedAt: String?

    init?(raw: RawDoc) {
        let data = raw.data
        guard case .object = data else { return nil }
        id = raw.id
        date = data.field("date")?.stringValue
        var list: [DigestItem] = []
        if case .array(let entries)? = data.field("items") {
            for entry in entries {
                // One odd item never hides the rest.
                if let item = entry.decode(DigestItem.self), !item.id.isEmpty, item.url != nil { list.append(item) }
            }
        }
        items = list
        emailsRead = data.field("emailsRead")?.intValue
        senders = data.field("senders")?.stringList ?? []
        updatedAt = data.field("updatedAt")?.stringValue
    }

    init(id: String, items: [DigestItem], emailsRead: Int?, senders: [String], updatedAt: String?) {
        self.id = id
        self.date = id
        self.items = items
        self.emailsRead = emailsRead
        self.senders = senders
        self.updatedAt = updatedAt
    }

    /// The newest day's doc (ids are dates, so they sort).
    static func latest(_ docs: [DigestDoc]) -> DigestDoc? {
        docs.max { ($0.date ?? $0.id, $0.id) < ($1.date ?? $1.id, $1.id) }
    }
}

/// The item ids this phone has already shown, so the card can say "N new". Kept on the phone only.
enum DigestSeen {
    private static let key = "digest.seen"
    private static let limit = 400

    static func load() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: key) ?? [])
    }

    static func save(_ ids: Set<String>, newest: [String]) {
        // Keep the current items first, then whatever else fits.
        var ordered = newest.filter { ids.contains($0) }
        for id in ids.sorted() where !ordered.contains(id) { ordered.append(id) }
        UserDefaults.standard.set(Array(ordered.prefix(limit)), forKey: key)
    }

    static func newCount(_ items: [DigestItem], seen: Set<String>) -> Int {
        items.filter { !seen.contains($0.id) }.count
    }
}
