import XCTest
@testable import DealDesk

/// 1.6 (CONTRACT_V5 section 4 + the round 14 minors): the flight estimate with its basis, the disembark-day rule,
/// drive ports, the soft budget, ages on the sailing date, scenic ports in Visits, and list rows that show the trip
/// cost range instead of one figure.
final class V6Tests: XCTestCase {
    // MARK: Flights (CONTRACT_V5 section 4)

    func testTheFlightEstimateSaysWhatItIs() throws {
        let sheet = try XCTUnwrap(Samples.sheetFly)
        let travel = try XCTUnwrap(sheet.travel)
        XCTAssertEqual(travel.modeValue, .fly)
        XCTAssertEqual(travel.route, "ORD–IAH")
        XCTAssertEqual(travel.flight?.isReady, true)
        XCTAssertEqual(travel.flightBasis, "recent fare seen Nov 24, ORD–IAH, per person, economy")
        XCTAssertTrue(travel.returnAssumed, "a date-level fare is priced on the rule")
        XCTAssertEqual(travel.returnAfter, "1 PM")
        XCTAssertEqual(travel.datesText(rule: true), "Out Sat Sep 4 · home Sat Sep 11, after 1 PM")
        XCTAssertEqual(travel.datesText(rule: false), "Out Sat Sep 4 · home Sat Sep 11")
        XCTAssertEqual(travel.disembarkNote(flightsOn: true), travel.note, "the server's own note wins")

        // The flights line in the trip cost: an estimate with its basis, never a quote.
        let flights = try XCTUnwrap(sheet.lines.first { $0.key == "flights" })
        XCTAssertEqual(flights.amountText, "$1,290")
        XCTAssertEqual(sheet.tag(for: flights), "estimate · not a quote")
        let detail = try XCTUnwrap(sheet.detail(for: flights))
        XCTAssertTrue(detail.hasPrefix("recent fare seen Nov 24, ORD–IAH, per person, economy"), detail)
        XCTAssertTrue(detail.contains("about $430 × 3, round trip"), detail)
        XCTAssertTrue(detail.contains("return after 1 PM assumed"), detail)
        // Every other line keeps its own words.
        let fare = try XCTUnwrap(sheet.lines.first { $0.key == "fare" })
        XCTAssertEqual(sheet.detail(for: fare), fare.detail)
        XCTAssertEqual(sheet.tag(for: fare), "read · Example agency")
        // The trip cost counts the flight (and the hotel night) when it is known.
        XCTAssertEqual(sheet.total?.headline, "$5,156 – $6,560")
        XCTAssertEqual(sheet.tripCost.range, "$5,156–6,560")
    }

    func testTheDisembarkRuleIsNeverEarlierThanOnePM() throws {
        func travel(_ fields: [String: JSONValue]) throws -> SheetTravel {
            var base: [String: JSONValue] = ["mode": .string("fly"), "fromAirport": .string("ORD"),
                                             "toAirport": .string("MIA"), "departDate": .string("2027-03-06"),
                                             "returnDate": .string("2027-03-13")]
            for (key, value) in fields { base[key] = value }
            return try XCTUnwrap(JSONValue.object(base).decode(SheetTravel.self))
        }
        XCTAssertEqual(try travel([:]).returnAfter, "1 PM", "the line-agnostic default")
        XCTAssertEqual(try travel(["returnNotBefore": .string("12:00")]).returnAfter, "1 PM", "a line may not make it earlier")
        XCTAssertEqual(try travel(["returnNotBefore": .string("14:30")]).returnAfter, "2:30 PM", "a line may make it later")
        XCTAssertEqual(try travel(["returnNotBefore": .string("7am")]).returnAfter, "1 PM", "nonsense is ignored")

        // No server note: the app says the rule itself, only while flight estimates are on.
        let quiet = try travel(["flight": .object(["state": .string("pending")])])
        XCTAssertNil(quiet.disembarkNote(flightsOn: false))
        XCTAssertEqual(quiet.disembarkNote(flightsOn: true),
                       "Flights home on the day the ship docks should leave at 1 PM or later.")
        let dated = try travel(["flight": .object(["state": .string("ready"), "pp": .int(352), "total": .int(1056),
                                                   "foundAt": .string("2026-11-25")])])
        XCTAssertTrue(dated.returnAssumed)
        XCTAssertTrue(dated.disembarkNote(flightsOn: true)?.hasPrefix("Return after 1 PM assumed") ?? false)
        let timed = try travel(["flight": .object(["state": .string("ready"), "pp": .int(352), "returnTime": .string("15:40")])])
        XCTAssertFalse(timed.returnAssumed, "a fare with a flight time is not assumed")
        // A drive or home sailing has no flight rule.
        XCTAssertNil(try travel(["mode": .string("drive")]).disembarkNote(flightsOn: true))
    }

    func testAnUnknownFlightIsNotShownNeverInvented() throws {
        let raw = JSONValue.object(["sheet": .object([
            "lines": .array([
                .object(["key": .string("fare"), "label": .string("Cruise fare"), "amount": .int(2000), "basis": .string("read")]),
                .object(["key": .string("flights"), "label": .string("Flights"), "amount": .null, "basis": .string("not_shown"),
                         "detail": .string("looking up a flight estimate"), "counted": .bool(false)]),
            ]),
            "total": .object(["firm": .int(2000), "low": .int(2000), "high": .int(2000), "complete": .bool(false),
                              "notShown": .array([.string("Flights")])]),
            "travel": .object(["mode": .string("fly"), "fromAirport": .string("ORD"), "toAirport": .string("MIA"),
                               "flight": .object(["state": .string("ready"), "pp": .null])]),
        ])])
        let sheet = try XCTUnwrap(DealSheet.from(raw))
        XCTAssertEqual(sheet.travel?.flight?.isReady, false, "ready without a figure is not an estimate")
        XCTAssertNil(sheet.travel?.flightBasis)
        let flights = try XCTUnwrap(sheet.lines.first { $0.key == "flights" })
        XCTAssertEqual(flights.amountText, "not shown")
        XCTAssertEqual(sheet.detail(for: flights), "looking up a flight estimate")
        XCTAssertEqual(sheet.tag(for: flights), "not shown")
    }

    func testFlightBasisFallsBackToTheServersWordsThenTheAge() throws {
        func basis(_ flight: [String: JSONValue]) -> String? {
            var f = flight
            f["state"] = .string("ready")
            f["pp"] = .int(400)
            return JSONValue.object(["mode": .string("fly"), "fromAirport": .string("ORD"), "toAirport": .string("MIA"),
                                     "flight": .object(f)]).decode(SheetTravel.self)?.flightBasis
        }
        XCTAssertEqual(basis(["basis": .string("recent fare seen 2026-11-25, ORD–MIA, per person, economy")]),
                       "recent fare seen 2026-11-25, ORD–MIA, per person, economy")
        XCTAssertEqual(basis(["ageDays": .int(3)]), "recent fare seen 3 days ago, ORD–MIA, per person, economy")
        XCTAssertEqual(basis([:]), "recent fare seen, ORD–MIA, per person, economy")
    }

    func testClockWords() {
        XCTAssertEqual(ClockWords.words("13:00"), "1 PM")
        XCTAssertEqual(ClockWords.words("12:00"), "12 PM")
        XCTAssertEqual(ClockWords.words("00:30"), "12:30 AM")
        XCTAssertEqual(ClockWords.words("09:05"), "9:05 AM")
        XCTAssertNil(ClockWords.words("25:00"))
        XCTAssertNil(ClockWords.words("1pm"))
    }

    func testDriveSheetCountsNoFlight() throws {
        let sheet = try XCTUnwrap(Samples.sheetDrive)
        XCTAssertEqual(sheet.travel?.modeValue, .drive)
        XCTAssertNil(sheet.lines.first { $0.key == "flights" })
        XCTAssertNil(sheet.travel?.disembarkNote(flightsOn: true))
        XCTAssertNil(sheet.travel?.flightBasis)
    }

    // MARK: The soft budget (Jim: "flexible but less is better")

    func testBudgetLinesSayHowFarOverAndNeverHide() {
        let over = SheetBudget(budgetTotal: 3000, basis: "trip", low: 3640, high: 4950, state: "over", overBy: 640)
        XCTAssertEqual(over.line, "$640 over your $3,000 target · whole trip $3,640 – $4,950")
        XCTAssertEqual(over.shortNote, "$640 over your $3,000 target")
        XCTAssertTrue(over.isOver)

        // An older server without overBy: worked out from the low end.
        let olderOver = SheetBudget(budgetTotal: 3000, basis: "cabin", low: 3300, high: 4950, state: "over")
        XCTAssertEqual(olderOver.line, "$300 over your $3,000 target · cabin only $3,300 – $4,950")

        let straddles = SheetBudget(budgetTotal: 3000, basis: "trip", low: 2700, high: 3400, state: "within_tradeoff")
        XCTAssertEqual(straddles.line, "Up to $400 over your $3,000 target · whole trip $2,700 – $3,400")
        XCTAssertFalse(straddles.isOver)

        let under = SheetBudget(budgetTotal: 3000, basis: "trip", low: 2100, high: 2800, state: "under", complete: true)
        XCTAssertEqual(under.line, "Within your $3,000 target · whole trip $2,100 – $2,800")
        XCTAssertNil(under.shortNote)

        // Under only for what is known: never "within" on an incomplete total.
        let soFar = SheetBudget(budgetTotal: 3000, basis: "trip", low: 2100, high: 2800, state: "under_so_far",
                                complete: false)
        XCTAssertEqual(soFar.line, "Under your $3,000 target so far · whole trip $2,100 – $2,800, before what isn't shown")
        let soFarOld = SheetBudget(budgetTotal: 3000, basis: "trip", low: 2100, high: 2800, state: "under", complete: false)
        XCTAssertTrue(soFarOld.underSoFar)

        let unknown = SheetBudget(budgetTotal: 3000, basis: "trip", low: nil, high: nil, state: "unknown")
        XCTAssertEqual(unknown.line, "Your $3,000 target · the whole-trip cost isn't known yet")
        XCTAssertNil(SheetBudget(budgetTotal: nil, basis: "trip", low: 100, high: 200, state: "unknown").line)

        for budget in [over, olderOver, straddles, under, soFar, unknown] {
            let line = budget.line ?? ""
            XCTAssertFalse(line.contains("budget"), "a soft target, never a budget wall: \(line)")
        }
    }

    // MARK: Ages on the sailing date

    func testThePartyUsesAgesOnTheSailingNeverTodaysAge() throws {
        let sheet = try XCTUnwrap(Samples.sheetFly)
        XCTAssertEqual(sheet.partyText, "for 2 adults + 1 child (age 8 on the sailing)")
        let today = SheetParty(adults: 2, children: 1, childAges: [9], agesOnSailing: nil, guests: 3)
        XCTAssertNil(today.agesText, "the stored age is today's, never shown for a future sailing")
        let two = SheetParty(adults: 2, children: 2, agesOnSailing: [10, 7], guests: 4)
        XCTAssertEqual(two.agesText, "ages 10 and 7 on the sailing")
    }

    // MARK: Visits offers scenic ports

    func testVisitsOffersScenicPorts() {
        XCTAssertTrue(PortKind.visit.admits("scenic"))
        XCTAssertTrue(PortKind.visit.admits("call"))
        XCTAssertTrue(PortKind.visit.admits("both"))
        XCTAssertFalse(PortKind.visit.admits("embark"))
        XCTAssertFalse(PortKind.call.admits("scenic"), "call stays the server's call|both")
        let visits = Samples.ports(matching: "", kind: .visit).map { $0.key }
        XCTAssertTrue(visits.contains("glacier-bay"), "Glacier Bay can be picked in Visits")
        XCTAssertTrue(visits.contains("juneau"))
        XCTAssertFalse(visits.contains("seattle"), "an embark-only port is not a place a sailing visits")
        XCTAssertTrue(Samples.ports(matching: "glacier", kind: .visit).contains { $0.key == "glacier-bay" })
        XCTAssertEqual(Samples.ports(matching: "", kind: .embark).map { $0.key }, ["seattle", "vancouver", "galveston", "miami"])
    }

    // MARK: Feature gates

    func testFlightsNeedTheirFeature() {
        XCTAssertTrue(Samples.catalogV6.has(.flights))
        XCTAssertFalse(Samples.catalogV5.has(.flights))
    }
}

@MainActor
final class StoreV6Tests: XCTestCase {
    func testListRowsShowTheTripCostRangeNotOneFigure() throws {
        let store = Store.previewV6()
        XCTAssertTrue(store.has(.flights))
        let deal = try XCTUnwrap(store.deal("sample-fits"))
        XCTAssertEqual(deal.data.totalFor3, 2650, "the older single figure is still on the deal")
        XCTAssertEqual(MoneyLine.tripRange(deal), "$5,156–6,560", "the row shows the range from the sheet")
        let spoken = Speech.deal(deal)
        XCTAssertTrue(spoken.contains("trip cost $5,156 to 6,560"), spoken)
        XCTAssertFalse(spoken.contains("$2,650"), spoken)
        XCTAssertEqual(store.trackedSailing("trk-sample-star")?.sheet?.travel?.modeValue, .drive)
    }

    func testTheTripCheckNeverFailsADealOnASoftBudget() throws {
        let store = Store.previewV6()
        let deal = try XCTUnwrap(store.deal("sample-fits"))
        let trip = try XCTUnwrap(store.trip)
        XCTAssertEqual(deal.sheet?.budget?.state, "over")

        let soft = TripCheck.evaluate(deal, trip, softBudget: true)
        XCTAssertTrue(soft.fits, "over the target still fits: the budget never hides a sailing")
        XCTAssertEqual(soft.tradeoff, "$1,956 over your $3,200 target")
        XCTAssertTrue(store.fit(deal).fits, "the store uses the soft budget on a v5 server")
        XCTAssertTrue(store.bucket(.trip, filters: DealFilters(), sort: .score).contains { $0.id == "sample-fits" },
                      "For my trip keeps the over-target deal")

        // An older server keeps the old rule, so nothing changes there.
        var data = deal.data
        data.totalFor3 = 9_000
        let hard = TripCheck.evaluate(Deal(id: "t", data: data), trip)
        XCTAssertEqual(hard.reasons, ["Over $3,200"])

        XCTAssertTrue(trip.summary(softBudget: true).hasSuffix("aim for $3,200"), trip.summary(softBudget: true))
        XCTAssertTrue(trip.summary.hasSuffix("under $3,200"))
    }

    func testTheVisitsPickerFindsGlacierBay() async {
        let store = Store.previewV6()
        let ports = await store.catalogPorts(matching: "", kind: .visit)
        XCTAssertTrue(ports.contains { $0.key == "glacier-bay" })
    }

    func testTheSailingSheetCarriesTheFlightOnAFlightsServer() async throws {
        let store = Store.previewV6()
        let sheet = await store.sheet(sailingId: "any", cabin: "balcony")
        XCTAssertEqual(sheet?.travel?.flight?.isReady, true)
        let v5 = Store.previewV5()
        let older = await v5.sheet(sailingId: "any", cabin: "balcony")
        XCTAssertEqual(older?.travel?.flight?.isReady, false)
    }
}
