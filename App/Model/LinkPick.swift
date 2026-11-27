import Foundation

/// "Add from a link" (CONTRACT_V3 section 4): reads a pasted or shared sailing link, and any page title that came
/// with it, on the phone only. Nothing is fetched. It fills what it can recognise; Jim confirms the rest.
///
/// Recognised: AllAboardDeals' `/cruise-lines/<line>/<ship>/<yyyy-mm-dd>-<id>`, `sailDate` / `shipCode` /
/// `packageCode` query parameters, "7-night" in a path or title, "Dec 19, 2027" or "2027-12-19" in a title, a
/// ship name the catalog knows, and a cruise line's own website.
struct LinkPick: Equatable {
    var link: String?
    var host: String?
    var line: String?
    var ship: String?
    var sailDate: String?
    var nights: Int?

    var foundSailing: Bool { ship != nil || sailDate != nil || nights != nil }

    /// "Icon of the Seas · Dec 19, 2027 · 7 nights"
    var summary: String {
        var parts: [String] = []
        if let ship { parts.append(ship) } else if let line { parts.append(line) }
        if let day = Fmt.day(sailDate) { parts.append(Fmt.fullDay(day)) }
        if let nights { parts.append(Fmt.nights(nights)) }
        return parts.joined(separator: " · ")
    }

    static func read(_ text: String, catalog: Catalog = CatalogIndex.current) -> LinkPick? {
        let input = text.trimmed
        guard !input.isEmpty else { return nil }
        var pick = LinkPick()
        var rest = input
        if let url = firstURL(in: input) {
            pick.host = url.host?.lowercased()
            pick.link = TrackPick.validLink(url.absoluteString)
            rest = input.replacingOccurrences(of: url.absoluteString, with: " ")
            readURL(url, into: &pick, catalog)
        }
        readText(rest, into: &pick, catalog)
        guard pick.foundSailing || pick.line != nil || pick.link != nil else { return nil }
        return pick
    }

    // MARK: The link

    static func firstURL(in text: String) -> URL? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(location: 0, length: (text as NSString).length)
        for match in detector.matches(in: text, options: [], range: range) {
            if let url = match.url, let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" {
                return url
            }
        }
        return nil
    }

    private static func readURL(_ url: URL, into pick: inout LinkPick, _ catalog: Catalog) {
        if let host = url.host, let line = CruiseLine.fromHost(host) { pick.line = line }

        // AllAboardDeals: /cruise-lines/<line>/<ship>/<yyyy-mm-dd>-<id>
        let parts = url.pathComponents.filter { $0 != "/" }
        if let index = parts.firstIndex(of: "cruise-lines"), parts.count > index + 1 {
            if let line = CruiseLine.canonical(parts[index + 1], catalog: catalog) { pick.line = line }
            if parts.count > index + 2 {
                let shipSlug = parts[index + 2]
                if shipSlug != "sitemap.xml" {
                    pick.ship = catalog.ship(line: pick.line, named: shipSlug)?.name ?? Words.title(fromSlug: shipSlug)
                }
            }
            if parts.count > index + 3, let day = isoDay(String(parts[index + 3].prefix(10))) { pick.sailDate = day }
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for item in items {
            guard let value = item.value?.trimmed, !value.isEmpty else { continue }
            switch item.name.lowercased() {
            case "saildate", "sail_date", "departuredate", "departure_date", "startdate", "date":
                if pick.sailDate == nil { pick.sailDate = anyDay(value) }
            case "shipcode", "ship_code":
                if pick.ship == nil, pick.line == nil || pick.line == CruiseLine.royal,
                   let name = royalShipCodes[value.uppercased()] {
                    pick.ship = name
                    pick.line = CruiseLine.royal
                }
            case "packagecode", "package_code":
                if pick.nights == nil, let n = firstInt(#"^[A-Za-z]{2}(\d{2})"#, in: value), (1...30).contains(n) {
                    pick.nights = n
                }
            case "nights", "duration", "length":
                if pick.nights == nil, let n = Int(value), (1...30).contains(n) { pick.nights = n }
            default:
                break
            }
        }
        if pick.nights == nil, let n = firstInt(#"(\d{1,2})-night"#, in: url.path.lowercased()), (1...30).contains(n) {
            pick.nights = n
        }
    }

    // MARK: The title or share text

    private static func readText(_ text: String, into pick: inout LinkPick, _ catalog: Catalog) {
        let words = text.trimmed
        guard !words.isEmpty else { return }
        if pick.nights == nil, let n = firstInt(#"(?i)\b(\d{1,2})[\s-]*nights?\b"#, in: words), (1...30).contains(n) {
            pick.nights = n
        }
        if pick.sailDate == nil { pick.sailDate = dayInText(words) }
        if pick.ship == nil {
            // The longest ship name the catalog knows that appears in the text, on the link's line first.
            let lines = pick.line.map { [$0] } ?? catalog.lineNames
            var best: (ship: String, line: String)?
            for line in lines {
                for ship in catalog.ships(for: line) {
                    guard let name = ship.name, !name.isEmpty, words.localizedCaseInsensitiveContains(name) else { continue }
                    if best == nil || name.count > (best?.ship.count ?? 0) { best = (ship: name, line: line) }
                }
            }
            if let best {
                pick.ship = best.ship
                if pick.line == nil { pick.line = best.line }
            }
        }
        if pick.line == nil {
            pick.line = catalog.lineNames.first { name in
                name != CruiseLine.other && words.localizedCaseInsensitiveContains(name)
            }
        }
    }

    // MARK: Helpers

    /// "2027-12-19", if it is a real calendar day.
    private static func isoDay(_ text: String) -> String? {
        guard text.count == 10, let day = Fmt.day(text) else { return nil }
        return Fmt.isoDay(day)
    }

    /// 2027-12-19, 20271219 or 12/19/2027.
    private static func anyDay(_ text: String) -> String? {
        if let day = isoDay(String(text.prefix(10))) { return day }
        let digits = text.filter { $0.isNumber }
        if digits.count == 8, text.count == 8 {
            let s = Array(digits)
            return isoDay("\(String(s[0..<4]))-\(String(s[4..<6]))-\(String(s[6..<8]))")
        }
        let parts = text.split(separator: "/")
        if parts.count == 3, let m = Int(parts[0]), let d = Int(parts[1]), let y = Int(parts[2]), y > 2000 {
            return isoDay(String(format: "%04d-%02d-%02d", y, m, d))
        }
        return nil
    }

    private static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// "Dec 19, 2027", "December 19 2027" or "2027-12-19" anywhere in the text.
    private static func dayInText(_ text: String) -> String? {
        if let match = firstMatch(#"\b(20\d{2})-(\d{2})-(\d{2})\b"#, in: text), match.count == 4,
           let day = isoDay("\(match[1])-\(match[2])-\(match[3])") {
            return day
        }
        let pattern = #"(?i)\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\.?\s+(\d{1,2}),?\s+(20\d{2})\b"#
        guard let match = firstMatch(pattern, in: text), match.count == 4,
              let monthIndex = months.firstIndex(of: match[1].lowercased()),
              let d = Int(match[2]), let y = Int(match[3]) else { return nil }
        return isoDay(String(format: "%04d-%02d-%02d", y, monthIndex + 1, d))
    }

    private static func firstInt(_ pattern: String, in text: String) -> Int? {
        guard let match = firstMatch(pattern, in: text), match.count > 1 else { return nil }
        return Int(match[1])
    }

    /// The whole match, then each group (empty for a group that did not take part).
    private static func firstMatch(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let result = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        return (0..<result.numberOfRanges).map { i -> String in
            let r = result.range(at: i)
            return r.location == NSNotFound ? "" : ns.substring(with: r)
        }
    }

    /// Royal Caribbean's two-letter ship codes, as its own links carry them (`shipCode=IC`).
    static let royalShipCodes: [String: String] = [
        "IC": "Icon of the Seas", "OA": "Oasis of the Seas", "AL": "Allure of the Seas", "HM": "Harmony of the Seas",
        "SY": "Symphony of the Seas", "WN": "Wonder of the Seas", "UT": "Utopia of the Seas",
        "QN": "Quantum of the Seas", "AN": "Anthem of the Seas", "OV": "Ovation of the Seas",
        "SP": "Spectrum of the Seas", "OY": "Odyssey of the Seas", "FR": "Freedom of the Seas",
        "LB": "Liberty of the Seas", "ID": "Independence of the Seas", "VY": "Voyager of the Seas",
        "EX": "Explorer of the Seas", "AD": "Adventure of the Seas", "NV": "Navigator of the Seas",
        "MA": "Mariner of the Seas", "RD": "Radiance of the Seas", "BR": "Brilliance of the Seas",
        "SE": "Serenade of the Seas", "JW": "Jewel of the Seas", "GR": "Grandeur of the Seas",
        "EN": "Enchantment of the Seas", "VI": "Vision of the Seas", "RH": "Rhapsody of the Seas",
    ]
}
