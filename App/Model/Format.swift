import Foundation

/// Every number and date the app shows goes through here, so money and dates read the same everywhere.
enum Fmt {
    private static let usdFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()

    /// 2580 -> "$2,580"
    static func usd(_ value: Int) -> String {
        usdFormatter.string(from: NSNumber(value: value)) ?? "$\(value)"
    }

    static func nights(_ n: Int) -> String {
        n == 1 ? "1 night" : "\(n) nights"
    }

    // MARK: Calendar dates ("YYYY-MM-DD"), parsed and shown in the phone's own time zone so they never shift.

    private static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = .current
        return c
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = format
        return f
    }

    private static let dayParser = formatter("yyyy-MM-dd")
    private static let monthDay = formatter("MMM d")
    private static let dayOnly = formatter("d")
    private static let yearOnly = formatter("yyyy")
    private static let weekdayMonthDay = formatter("EEE MMM d")
    private static let monthDayYear = formatter("MMM d, yyyy")

    static func day(_ text: String?) -> Date? {
        guard let text, text.count >= 10 else { return nil }
        return dayParser.date(from: String(text.prefix(10)))
    }

    /// "Oct 15–22, 2028", "Oct 29 – Nov 5, 2028" or "Dec 28, 2027 – Jan 4, 2028".
    static func range(from start: Date, nights: Int) -> String {
        guard nights > 0, let end = calendar.date(byAdding: .day, value: nights, to: start) else {
            return monthDayYear.string(from: start)
        }
        let c = calendar
        let sameYear = c.component(.year, from: start) == c.component(.year, from: end)
        let sameMonth = sameYear && c.component(.month, from: start) == c.component(.month, from: end)
        if sameMonth {
            return "\(monthDay.string(from: start))–\(dayOnly.string(from: end)), \(yearOnly.string(from: end))"
        }
        if sameYear {
            return "\(monthDay.string(from: start)) – \(monthDay.string(from: end)), \(yearOnly.string(from: end))"
        }
        return "\(monthDayYear.string(from: start)) – \(monthDayYear.string(from: end))"
    }

    /// "Sun Sep 5 – Sat Sep 11, 2027", or "Tue Dec 28, 2027 – Tue Jan 4, 2028" across a new year.
    static func tripDates(from start: Date, to end: Date?) -> String {
        guard let end, end > start else { return "\(weekdayMonthDay.string(from: start)), \(yearOnly.string(from: start))" }
        let c = calendar
        if c.component(.year, from: start) == c.component(.year, from: end) {
            return "\(weekdayMonthDay.string(from: start)) – \(weekdayMonthDay.string(from: end)), \(yearOnly.string(from: end))"
        }
        let first = "\(weekdayMonthDay.string(from: start)), \(yearOnly.string(from: start))"
        let last = "\(weekdayMonthDay.string(from: end)), \(yearOnly.string(from: end))"
        return "\(first) – \(last)"
    }

    static func adding(days: Int, to date: Date) -> Date? {
        calendar.date(byAdding: .day, value: days, to: date)
    }

    /// What the server stores for a calendar date: "2027-09-05".
    static func isoDay(_ date: Date) -> String {
        dayParser.string(from: date)
    }

    /// "Sep 2027" for a "2027-09" month key.
    static func monthTitle(_ key: String) -> String {
        guard let date = dayParser.date(from: key + "-01") else { return key }
        return monthYear.string(from: date)
    }

    private static let monthYear = formatter("MMM yyyy")
    private static let clockParser = formatter("HH:mm")

    /// "22:00" <-> a time of day, for quiet hours.
    static func clock(_ text: String?) -> Date? {
        guard let text, text.count == 5 else { return nil }
        return clockParser.date(from: text)
    }

    static func clockText(_ date: Date) -> String {
        clockParser.string(from: date)
    }

    /// "Sun Nov 29"
    static func weekday(_ date: Date) -> String {
        weekdayMonthDay.string(from: date)
    }

    /// "Oct 15, 2028"
    static func fullDay(_ date: Date) -> String {
        monthDayYear.string(from: date)
    }

    /// "Oct 15"
    static func shortDay(_ date: Date) -> String {
        monthDay.string(from: date)
    }

    static func daysLeft(_ date: Date) -> Int {
        let c = calendar
        return c.dateComponents([.day], from: c.startOfDay(for: Date()), to: c.startOfDay(for: date)).day ?? 0
    }

    /// "2 days left", "1 day left", "last day", "ended"
    static func countdown(_ date: Date) -> String {
        let n = daysLeft(date)
        if n < 0 { return "ended" }
        if n == 0 { return "last day" }
        if n == 1 { return "1 day left" }
        return "\(n) days left"
    }

    /// "Sun Nov 29 · 2 days left"
    static func deadline(_ date: Date) -> String {
        "\(weekday(date)) · \(countdown(date))"
    }

    // MARK: Timestamps (ISO-8601 UTC)

    private static let isoPlain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let isoFraction: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static func timestamp(_ text: String?) -> Date? {
        guard let text, !text.isEmpty else { return nil }
        return isoPlain.date(from: text) ?? isoFraction.date(from: text)
    }

    /// What the app writes: "2026-11-27T17:12:00Z".
    static func stamp(_ date: Date = Date()) -> String {
        isoPlain.string(from: date)
    }

    /// "9:12 AM" today, "Tue 9:12 AM" this week, otherwise "Nov 20".
    static func when(_ date: Date) -> String {
        let c = Calendar.current
        if c.isDateInToday(date) {
            return date.formatted(date: .omitted, time: .shortened)
        }
        if let days = c.dateComponents([.day], from: date, to: Date()).day, days < 6 {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: Links

    /// Only http(s) links are ever opened.
    static func webURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host != nil else { return nil }
        return url
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    func capped(_ limit: Int) -> String {
        count > limit ? String(prefix(limit)) : self
    }
}

/// Sentences VoiceOver reads for a row, in the same order the eye reads it.
enum Speech {
    static func deal(_ deal: Deal, fails: [String] = []) -> String {
        var parts: [String] = []
        if deal.kind == .drop || deal.kind == .sale, let kind = deal.kind { parts.append(kind.title) }
        if let shipClass = deal.shipClass, deal.kind != .sale {
            parts.append("\(deal.title), \(shipClass.title)")
        } else {
            parts.append(deal.title)
        }
        if deal.kind == .sale {
            for offer in (deal.data.offers ?? []).prefix(2) { parts.append("\(offer.label) \(offer.value)") }
            if let ends = deal.endsDay { parts.append("Ends \(Fmt.weekday(ends)), \(Fmt.countdown(ends))") }
        } else {
            if !deal.datesLine.isEmpty { parts.append(deal.datesLine.replacingOccurrences(of: " · ", with: ", ")) }
            if let route = deal.route {
                parts.append(route.replacingOccurrences(of: " → ", with: " to ").replacingOccurrences(of: " · ", with: ", "))
            }
            if let cabin = deal.cabinLabel {
                if deal.data.oceanViewConfirmed == true {
                    parts.append("\(cabin), ocean view confirmed")
                } else if deal.cabinType == .balcony {
                    parts.append("\(cabin), type not confirmed")
                } else {
                    parts.append(cabin)
                }
            }
            if let total = deal.data.totalFor3 { parts.append("\(Fmt.usd(total)) for 3") }
            if let pp = deal.data.pricePP, pp > 0 {
                parts.append("\(Fmt.usd(pp)) per person" + (deal.data.priceIncludesTaxes == true ? ", taxes in" : ""))
            }
            if let drop = deal.dropPP { parts.append("down \(Fmt.usd(drop)) per person") }
            if let under = Speech.underTypical(deal) { parts.append(under) }
        }
        if let score = deal.data.score {
            parts.append("Score \(score)" + (deal.data.scoreLabel.map { ", \($0)" } ?? ""))
        }
        if let why = deal.data.why, !why.isEmpty { parts.append("Why: \(why)") }
        if !fails.isEmpty { parts.append("Not for your trip: \(fails.joined(separator: ", "))") }
        return parts.joined(separator: ". ")
    }

    /// "Price 18 percent under typical, $1,560"
    static func underTypical(_ deal: Deal) -> String? {
        guard let pct = deal.pctUnder else { return nil }
        let typical = deal.typicalPP.map { ", \(Fmt.usd($0))" } ?? ""
        if pct > 0 { return "Price \(pct) percent under typical\(typical)" }
        if pct < 0 { return "Price \(-pct) percent over typical\(typical)" }
        return "Price at the typical price\(typical)"
    }
}

/// The running build as "X.Y.Z (N)": the version from release-please, the build number from the TestFlight run.
enum AppVersion {
    static var display: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
