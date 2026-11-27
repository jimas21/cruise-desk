import XCTest
@testable import DealDesk

// MARK: - v4 (DESIGN_V4.md, CONTRACT_V4.md)

private func decode(_ json: String) throws -> RawDoc {
    try JSONDecoder().decode(RawDoc.self, from: Data(json.utf8))
}

private func deal(_ json: String) throws -> Deal {
    try XCTUnwrap(Deal(raw: decode(json)))
}

@MainActor
final class CatalogV4Tests: XCTestCase {
    func testFeaturesTurnOnOnlyWhenListedOnAV4Server() throws {
        let json = #"""
        {"apiVersion": 4, "features": ["booking", "digest", "search", "plans", "trips", "later"], "catalogVersion": 2,
         "lines": [{"name": "Royal Caribbean", "slug": "royal-caribbean",
                    "booking": {"label": "Book on Royal Caribbean", "short": "Royal", "home": "https://www.royalcaribbean.com/cruises",
                                "tiers": [{"tier": "sailing", "verified": true}, {"tier": "exact", "verified": true}]},
                    "ships": [{"name": "Icon of the Seas", "slug": "icon-of-the-seas", "class": "Icon", "classSlug": "icon",
                               "size": "mega", "gt": 248663, "code": "IC", "passengers": 5610, "maidenYear": 2024}]},
                   {"name": "MSC", "slug": "msc", "booking": "odd", "ships": []}],
         "somethingNew": {"x": 1}}
        """#
        let catalog = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8))
        XCTAssertTrue(catalog.isV3, "a v4 server still turns v3 on")
        for feature in V4Feature.allCases { XCTAssertTrue(catalog.has(feature), feature.rawValue) }
        let royal = try XCTUnwrap(catalog.line("Royal Caribbean"))
        XCTAssertEqual(royal.booking?.label, "Book on Royal Caribbean")
        XCTAssertEqual(royal.booking?.tiers?.count, 2)
        XCTAssertEqual(royal.ships?.first?.code, "IC")
        XCTAssertEqual(royal.ships?.first?.passengers, 5610)
        XCTAssertNil(catalog.line("MSC")?.booking, "an odd booking spec is dropped, the line stays")

        var three = catalog
        three.apiVersion = 3
        XCTAssertFalse(three.has(.search), "features count only from apiVersion 4")
        var some = catalog
        some.features = ["booking"]
        XCTAssertTrue(some.has(.booking))
        XCTAssertFalse(some.has(.trips), "each feature turns on only when it is listed")
    }

    func testTheStoreFollowsTheFeatureList() {
        let v3 = Store(previewDocs: Samples.docs)
        XCTAssertTrue(v3.isV3)
        XCTAssertTrue(v3.v4Features.isEmpty, "the v3 sample server lists nothing")
        XCTAssertEqual(v3.savePlan(PlanDraft()), .comingSoon)
        XCTAssertEqual(v3.logTrip(TripDraft()), .comingSoon)
        XCTAssertTrue(v3.digestItems.isEmpty)
        let v4 = Store.previewV4()
        XCTAssertEqual(v4.v4Features, Set(V4Feature.allCases))
        XCTAssertFalse(v4.digestItems.isEmpty)
    }
}

@MainActor
final class BookingTests: XCTestCase {
    private let catalog = Samples.catalogV4

    func testABookingIsReadOnItsOwnAndNeverHidesTheDeal() throws {
        let good = try deal(#"""
        {"id": "icon-2027-09-05-6n", "version": 3, "data": {"kind": "fits", "ship": "Icon of the Seas", "sailDate": "2027-09-05", "nights": 6,
         "link": "https://www.royalcaribbean.com/cruises?search=ship:IC%7CstartDate:2027-09-05~2027-09-05", "linkLabel": "Book on Royal Caribbean",
         "booking": {"url": "https://www.royalcaribbean.com/cruises?search=ship:IC%7CstartDate:2027-09-05~2027-09-05", "tier": "sailing",
                     "label": "Book on Royal Caribbean", "note": "opens Royal's search for Icon · Sep 5, 2027", "verified": true,
                     "codes": ["shipCode", "sailDate"], "builtAt": "2026-11-27T20:00:00Z", "extra": 1},
         "bookAlternatives": [{"agency": "Costco Travel", "url": "https://example.com/c", "pricePP": 1276, "taxesIncluded": true, "cabinClass": "balcony",
                               "perks": ["$250 Shop Card"], "whyBetter": "same fare + $250 Costco Shop Card"},
                              {"agency": "Quiet agency", "url": "https://example.com/q", "pricePP": 1200, "whyBetter": ""}],
         "planIds": ["plan-1"]}}
        """#)
        XCTAssertEqual(good.booking?.tierValue, .sailing)
        XCTAssertEqual(good.alternatives.count, 1, "an agency with no stated reason never shows")
        XCTAssertEqual(good.alternatives.first?.rowTitle, "Or Costco Travel · same fare + $250 Costco Shop Card")

        let odd = try deal(#"{"id": "x-1", "version": 1, "data": {"kind": "fits", "ship": "Icon of the Seas", "booking": "not an object", "bookAlternatives": 7}}"#)
        XCTAssertNil(odd.booking)
        XCTAssertTrue(odd.alternatives.isEmpty)
        XCTAssertEqual(odd.title, "Icon of the Seas", "an odd booking never hides the deal")
    }

    func testThePrimaryButtonIsAlwaysTheLinesOwnSite() {
        let choice = BookChoice.make(line: "Royal Caribbean", ship: "Icon of the Seas", booking: Samples.bookingIcon,
                                     link: "https://example.com/agency", linkLabel: "Example agency",
                                     sources: [DealSource(name: "Example agency", url: "https://example.com/a", pricePP: 1300, includesTaxes: nil),
                                               DealSource(name: "Costco", url: "https://example.com/c", pricePP: 1276, includesTaxes: true)],
                                     pricePP: 1276, alternatives: [Samples.costcoAlternative], v4: true, catalog: catalog)
        XCTAssertEqual(choice.primary?.title, "Book on Royal Caribbean")
        XCTAssertEqual(choice.primary?.url.host, "www.royalcaribbean.com")
        XCTAssertEqual(choice.note, "opens Royal's search for Icon · Sep 5, 2027", "a sailing-tier link says what it opens")
        XCTAssertEqual(choice.seenOn?.name, "Costco", "Seen on is the source whose price equals the deal's")
        XCTAssertEqual(choice.alternatives.count, 1)

        let exact = BookChoice.make(line: "Celebrity", ship: "Celebrity Beyond", booking: Samples.bookingBeyond, link: nil,
                                    linkLabel: nil, sources: [], pricePP: nil, alternatives: [], v4: true, catalog: catalog)
        XCTAssertEqual(exact.primary?.title, "Book on Celebrity")
        XCTAssertNil(exact.note, "an exact link needs no note")

        var odd = Samples.bookingIcon
        odd.tier = "galaxy"
        odd.note = nil
        let unknown = BookChoice.make(line: "Royal Caribbean", ship: nil, booking: odd, link: nil, linkLabel: nil, sources: [],
                                      pricePP: nil, alternatives: [], v4: true, catalog: catalog)
        XCTAssertNotNil(unknown.note, "an unknown tier is shown as non-exact")
    }

    func testEveryLineFallsBackToItsOwnHomeNeverAnAgency() {
        for line in ["Norwegian", "Carnival", "Princess", "MSC", "Celebrity", "Royal Caribbean"] {
            let choice = BookChoice.make(line: line, ship: "Some Ship", booking: nil, link: "https://example.com/agency",
                                         linkLabel: "Agency", sources: [], pricePP: nil, alternatives: [], v4: true,
                                         catalog: catalog)
            XCTAssertEqual(choice.primary?.title, "Book on \(line)", line)
            XCTAssertNotEqual(choice.primary?.url.host, "example.com", "never the agency for \(line)")
            XCTAssertTrue(choice.note?.contains("find Some Ship there") == true, line)
        }
        let other = BookChoice.make(line: "Other", ship: "Mystery", booking: nil, link: "https://example.com/a", linkLabel: nil,
                                    sources: [DealSource(name: "Gangwaze", url: "https://example.com/g", pricePP: nil, includesTaxes: nil)],
                                    pricePP: nil, alternatives: [], v4: true, catalog: catalog)
        XCTAssertNil(other.primary)
        XCTAssertEqual(other.note, "no booking link for Other yet")
        XCTAssertEqual(other.seenOn?.name, "Gangwaze", "the source page is still there, as a small link")
    }

    func testAV3ServerKeepsTheDealsOwnLink() {
        let old = BookChoice.make(line: "Royal Caribbean", ship: "Icon of the Seas", booking: Samples.bookingIcon,
                                  link: "https://example.com/agency", linkLabel: "Example agency", sources: [], pricePP: nil,
                                  alternatives: [Samples.costcoAlternative], v4: false, catalog: catalog)
        XCTAssertEqual(old.primary?.title, "Open deal")
        XCTAssertEqual(old.primary?.url.host, "example.com")
        XCTAssertTrue(old.alternatives.isEmpty, "no v4 extras without the feature")

        let normalised = BookChoice.make(line: "Royal Caribbean", ship: nil, booking: nil,
                                         link: "https://www.royalcaribbean.com/cruises", linkLabel: "Book on Royal Caribbean",
                                         sources: [], pricePP: nil, alternatives: [], v4: false, catalog: catalog)
        XCTAssertEqual(normalised.primary?.title, "Book on Royal Caribbean", "the server's normalised label reads as is")

        let sale = BookChoice.make(line: "Royal Caribbean", ship: nil, booking: nil, link: "https://example.com/sale",
                                   linkLabel: "Sale page", sources: [], pricePP: nil, alternatives: [], v4: true,
                                   isSale: true, catalog: catalog)
        XCTAssertEqual(sale.primary?.title, "See the sale", "a sale keeps its own page")
    }

    func testAtMostThreeAlternativesAndOnlyWithAReason() {
        let many = (1...5).map { n in
            BookAlternative(agency: "Agency \(n)", url: "https://example.com/\(n)", pricePP: 1000, taxesIncluded: nil,
                            cabinClass: "balcony", perks: nil, whyBetter: n == 2 ? nil : "$\(n * 50) pp less")
        }
        let choice = BookChoice.make(line: "Royal Caribbean", ship: nil, booking: Samples.bookingIcon, link: nil, linkLabel: nil,
                                     sources: [], pricePP: nil, alternatives: many, v4: true, catalog: catalog)
        XCTAssertEqual(choice.alternatives.count, 3)
        XCTAssertFalse(choice.alternatives.contains { $0.name == "Agency 2" })
        XCTAssertTrue(choice.alternatives.allSatisfy { !$0.reason.isEmpty })
    }

    func testTrackedAndSearchRowsBookOnTheLine() throws {
        let store = Store.previewV4()
        let star = try XCTUnwrap(store.trackedSailing("trk-sample-star"))
        XCTAssertEqual(store.bookChoice(for: star).primary?.title, "Book on Royal Caribbean")
        let row = try XCTUnwrap(Samples.searchResult.rows.first)
        XCTAssertEqual(store.bookChoice(for: row).primary?.url.host, "www.royalcaribbean.com")
        let fits = try XCTUnwrap(store.deal("sample-fits"))
        XCTAssertEqual(store.bookChoice(for: fits).alternatives.first?.name, "Costco Travel")
        let older = Store(previewDocs: Samples.docsV4)
        XCTAssertTrue(older.bookChoice(for: star).isEmpty, "a v3 tracked sailing keeps its own buttons")
    }
}

@MainActor
final class PreferenceV4Tests: XCTestCase {
    func testV4KnobsGoOnlyWhenTheirFeatureIsListed() throws {
        let raw = try decode(#"{"id": "trip", "version": 4, "data": {"nightsMin": 5, "nightsMax": 8, "bookingPreference": "best-value", "portRecencyMonths": 3, "portRecencyFadeMonths": 9, "usePortRatings": false}}"#)
        let prefs = try XCTUnwrap(raw.data.decode(TripPrefs.self))
        XCTAssertEqual(prefs.bookingPreference, "best-value")
        XCTAssertEqual(prefs.recencyMonths, 3)
        XCTAssertEqual(prefs.fadeMonths, 9)
        XCTAssertFalse(prefs.usesPortRatings)

        let plain = prefs.fields(v3: true)
        for key in ["bookingPreference", "portRecencyMonths", "portRecencyFadeMonths", "usePortRatings"] {
            XCTAssertNil(plain[key], "\(key) is never sent without its feature (a PATCH leaves it intact)")
        }
        let booking = prefs.fields(v3: true, v4: [.booking])
        XCTAssertEqual(booking["bookingPreference"], .string("best-value"))
        XCTAssertNil(booking["portRecencyMonths"])
        let trips = prefs.fields(v3: true, v4: [.trips])
        XCTAssertEqual(trips["portRecencyMonths"], .int(3))
        XCTAssertEqual(trips["usePortRatings"], .bool(false))
        XCTAssertNil(TripPrefs().fields(v3: true, v4: Set(V4Feature.allCases))["bookingPreference"], "absent stays absent")

        var odd = prefs
        odd.portRecencyMonths = 10
        odd.portRecencyFadeMonths = 4
        XCTAssertEqual(odd.cleaned().portRecencyFadeMonths, 10, "the fade is never shorter than the recency window")
        XCTAssertEqual(BookingPreference(raw: nil), .line, "absent means the line")
    }

    func testBookingPreferenceChangesOnlyThatField() {
        let store = Store.previewV4()
        let before = store.pendingCount
        XCTAssertTrue(store.setBookingPreference(.bestValue))
        XCTAssertEqual(store.trip?.bookingPreference, "best-value")
        XCTAssertEqual(store.pendingCount, before + 1)
        XCTAssertTrue(store.savePortKnobs(recencyMonths: 4, fadeMonths: 2, useRatings: true))
        XCTAssertEqual(store.trip?.portRecencyMonths, 4)
        XCTAssertEqual(store.trip?.portRecencyFadeMonths, 4)
        XCTAssertEqual(store.pendingCount, before + 1, "both changes ride on the same queued PATCH")
    }
}

@MainActor
final class DigestTests: XCTestCase {
    func testTheNewestDayAndLenientItems() throws {
        let old = try decode(#"{"id": "2026-11-25", "version": 1, "data": {"date": "2026-11-25", "items": [], "updatedAt": "2026-11-25T10:00:00Z"}}"#)
        let new = try decode(#"""
        {"id": "2026-11-27", "version": 2, "data": {"date": "2026-11-27", "emailsRead": 12, "senders": ["Cruise Fever"],
         "items": [{"id": "s-royal-caribbean-icon-of-the-seas-2027-09-05", "kind": "price_drop", "headline": "Icon drops", "link": "https://example.com/1",
                    "sources": [{"name": "Cruise Fever", "inboxId": "a"}, {"name": "Cruise Fever", "inboxId": "b"}, {"name": "VTG", "inboxId": "c"}],
                    "matchesTrip": true, "booking": {"url": "https://www.royalcaribbean.com/cruises", "tier": "line", "label": "Book on Royal Caribbean"}},
                   {"id": "h-1", "kind": "brand_new_kind", "headline": "Something", "link": "https://example.com/2"},
                   {"id": "bad", "kind": "news", "headline": "No link"},
                   7],
         "updatedAt": "2026-11-27T10:00:00Z"}}
        """#)
        let docs = [old, new].compactMap { DigestDoc(raw: $0) }
        let latest = try XCTUnwrap(DigestDoc.latest(docs))
        XCTAssertEqual(latest.id, "2026-11-27")
        XCTAssertEqual(latest.items.count, 2, "an item with no link, or not an object, is skipped; the rest stay")
        XCTAssertEqual(latest.items[0].sourceNames, ["Cruise Fever", "VTG"])
        XCTAssertTrue(latest.items[0].fitsTrip)
        XCTAssertEqual(latest.items[0].kindValue, .priceDrop)
        XCTAssertEqual(latest.items[1].kindValue, .news, "an unknown kind shows as news")
        XCTAssertEqual(DigestSeen.newCount(latest.items, seen: ["h-1"]), 1)
    }

    func testTheCardCountsNewAndSeeingClearsIt() {
        let store = Store.previewV4()
        XCTAssertEqual(store.digestNewCount, Samples.digestItems.count)
        store.markDigestSeen()
        XCTAssertEqual(store.digestNewCount, 0)
        XCTAssertNotNil(store.bookChoice(for: Samples.digestItems[0]), "an item naming a sailing books on the line")
        XCTAssertNil(store.bookChoice(for: Samples.digestItems[1]), "a sale names no sailing")
    }
}

@MainActor
final class SearchTests: XCTestCase {
    func testTheQueryStringIsExactlyWhatTheServerTakes() {
        var q = SearchQuery()
        XCTAssertEqual(q.queryItems().map { $0.name }, ["sort", "limit"])
        q.lines = ["royal caribbean", "Celebrity", "Other"]
        q.ships = ["Icon of the Seas"]
        q.sizes = ["mega", "huge"]
        q.ports = ["Galveston", " "]
        q.dateFrom = "2027-11-30"
        q.dateTo = "2027-08-01"
        q.months = [9, 13, 9, 10]
        q.nightsMin = 8
        q.nightsMax = 6
        q.cabin = "balcony"
        q.maxPP = 1300
        q.dealTypes = ["new_low", "sale", "fits_trip"]
        q.sort = "price"
        let items = Dictionary(q.queryItems(offset: 50, limit: 500).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(items["line"], "Royal Caribbean,Celebrity", "names are canonical; Other is never a search line")
        XCTAssertEqual(items["size"], "mega")
        XCTAssertEqual(items["port"], "Galveston")
        XCTAssertEqual(items["from"], "2027-08-01")
        XCTAssertEqual(items["to"], "2027-11-30")
        XCTAssertEqual(items["months"], "9,10")
        XCTAssertEqual(items["nights"], "6-8")
        XCTAssertEqual(items["cabin"], "balcony")
        XCTAssertEqual(items["maxPP"], "1300")
        XCTAssertEqual(items["dealType"], "new_low,fits_trip", "a sale is not one sailing")
        XCTAssertEqual(items["sort"], "price")
        XCTAssertEqual(items["offset"], "50")
        XCTAssertEqual(items["limit"], "100", "never more than the server's 100")

        var one = SearchQuery()
        one.nightsMin = 7
        one.nightsMax = 7
        XCTAssertEqual(one.nightsParam, "7")
    }

    func testResultsDecodeLenientlyRowByRow() throws {
        let json = #"""
        {"rows": [{"sailingId": "icon-of-the-seas-2027-09-05-6n", "line": "Royal Caribbean", "ship": "icon-of-the-seas", "shipName": "Icon of the Seas",
                   "sailDate": "2027-09-05", "nights": 6, "cabin": "balcony", "pricePP": 1154, "dealTypes": ["new_low", "under_typical"], "pctUnderTypical": 22,
                   "fit": {"adj": -9, "reasons": ["Costa Maya 3/10"]}, "unknown": ["region"], "coverage": "tracking_live",
                   "booking": {"url": "https://www.royalcaribbean.com/x", "tier": "sailing", "label": "Book on Royal Caribbean"}, "brandNew": true},
                  {"sailingId": "x", "pricePP": "lots"},
                  "junk"],
         "total": 2, "nextOffset": null, "notes": ["no data for MSC yet"], "coverage": [], "generatedAt": "2026-11-27T20:00:00Z"}
        """#
        let result = try JSONDecoder().decode(SearchResult.self, from: Data(json.utf8))
        XCTAssertEqual(result.rows.count, 2)
        let row = result.rows[0]
        XCTAssertEqual(row.shipTitle, "Icon of the Seas")
        XCTAssertEqual(row.typeChips, ["New low", "22% under typical"])
        XCTAssertEqual(row.fit?.adj, -9)
        XCTAssertEqual(row.unknownNote, "region unknown")
        XCTAssertNotNil(row.booking)
        XCTAssertNil(result.rows[1].pricePP, "an odd price reads as unknown, never a made-up number")
        XCTAssertNil(result.nextOffset)
        XCTAssertEqual(result.notes, ["no data for MSC yet"])

        let pick = row.trackPick(cabin: nil)
        XCTAssertEqual(pick.ship, "Icon of the Seas")
        XCTAssertEqual(pick.cabin, .balcony)
        XCTAssertNil(pick.problem)
    }
}

@MainActor
final class PlanTests: XCTestCase {
    func testAPlanSavesItsPickFieldsOnly() throws {
        var draft = PlanDraft()
        XCTAssertNotNil(draft.problem)
        draft.name = "  Icon fall 2027 "
        draft.query.lines = ["Royal Caribbean"]
        draft.query.cabin = "balcony"
        let create = draft.fields(isNew: true, stamp: "2026-11-27T20:00:00Z")
        XCTAssertEqual(create["name"], .string("Icon fall 2027"))
        XCTAssertEqual(create["watch"], .bool(true))
        XCTAssertEqual(create["createdAt"], .string("2026-11-27T20:00:00Z"))
        XCTAssertNil(create["dateFrom"], "a create leaves out what is empty")
        for key in ["matches", "bestPP", "bestSailingId", "brainNote", "checkedAt", "promotedAt"] {
            XCTAssertNil(create[key], "\(key) belongs to the brain or to Promote")
        }
        let edit = draft.fields(isNew: false)
        XCTAssertEqual(edit["dateFrom"], .null, "an edit clears what was cleared")
        XCTAssertNil(edit["createdAt"])
    }

    func testPlansShowAtOnceAndNamesAreUnique() throws {
        let store = Store.previewV4()
        let before = store.plans.count
        var draft = PlanDraft()
        draft.name = "Celebrity spring"
        draft.query.lines = ["Celebrity"]
        guard case .saved(let id) = store.savePlan(draft) else { return XCTFail("not saved") }
        let local = try XCTUnwrap(store.plan(id))
        XCTAssertTrue(local.isLocal)
        XCTAssertEqual(store.plans.count, before + 1)
        var same = PlanDraft()
        same.name = "celebrity SPRING"
        XCTAssertEqual(store.savePlan(same), .already(id), "names are unique, ignoring case")

        draft.note = "with the kids"
        XCTAssertEqual(store.savePlan(draft, editing: local), .saved(id))
        XCTAssertEqual(store.plan(id)?.data.note, "with the kids", "an unsent plan takes the change")
        XCTAssertNotNil(store.plan(id)?.data.createdAt)

        store.deletePlan(try XCTUnwrap(store.plan(id)))
        XCTAssertNil(store.plan(id))
        XCTAssertEqual(store.plans.count, before)
    }

    func testPromoteCopiesWhatMyTripHasAndSaysWhatItLeaves() throws {
        let store = Store.previewV4()
        let plan = try XCTUnwrap(store.plan("plan-sample-icon"))
        let start = try XCTUnwrap(store.trip)
        let promoted = PlanPromotion.apply(plan, to: start)
        XCTAssertEqual(promoted.lines, ["Royal Caribbean"])
        XCTAssertEqual(promoted.dateFrom, "2027-08-01")
        XCTAssertEqual(promoted.dateTo, "2027-11-30")
        XCTAssertEqual(promoted.nightsMin, 6)
        XCTAssertEqual(promoted.nightsMax, 8)
        XCTAssertEqual(promoted.cabinTypes, ["balcony"])
        XCTAssertEqual(promoted.budgetTotal, start.budgetTotal, "a budget per person is not My Trip's total")
        XCTAssertEqual(promoted.portsPreferred, start.portsPreferred, "ports are not copied")
        XCTAssertEqual(PlanPromotion.notCopied(plan), ["ships", "ports", "budget per person"])

        let before = store.pendingCount
        store.promote(plan)
        XCTAssertEqual(store.trip?.dateFrom, "2027-08-01")
        XCTAssertNotNil(store.plan(plan.id)?.data.promotedAt)
        XCTAssertEqual(store.pendingCount, before + 2, "My Trip and the plan's promotedAt")
    }
}

@MainActor
final class PortFitTests: XCTestCase {
    func testPortKeysMatchTheServer() {
        XCTAssertEqual(PortKey.key("Roatán (Coxen Hole)"), "roatan")
        XCTAssertEqual(PortKey.key("Coxen Hole"), "roatan")
        XCTAssertEqual(PortKey.key("Mahogany Bay, Honduras"), "roatan")
        XCTAssertEqual(PortKey.key("Perfect Day at CocoCay"), "cococay")
        XCTAssertEqual(PortKey.key("St. Thomas"), "st-thomas")
        XCTAssertEqual(PortKey.key("Cozumel"), "cozumel")
        XCTAssertNil(PortKey.key("  "))
    }

    func testFitIsASoftSumWithPlainReasons() throws {
        let summary = Samples.portsSummary
        let fit = try XCTUnwrap(PortFit.of(stops: ["Cozumel", "Roatán", "Costa Maya", "At sea", "Cozumel"],
                                           embark: "Galveston", returnPort: "Galveston", summary: summary))
        XCTAssertEqual(fit.adj, -15, "-18 is clamped to ±15")
        XCTAssertEqual(fit.reasons.first, "Costa Maya 3/10", "the biggest nudge first")
        XCTAssertTrue(fit.reasons.contains("Cozumel 4 wk ago"))
        XCTAssertFalse(fit.reasons.contains { $0.hasPrefix("Roatan") }, "a port whose nudges cancel out says nothing")
        XCTAssertTrue(fit.phrases.contains("you were in Cozumel 4 weeks ago"))

        XCTAssertNil(PortFit.of(stops: ["Miami"], embark: "Miami", returnPort: nil, summary: summary),
                     "the port it leaves from never counts")
        XCTAssertNil(PortFit.of(stops: [], embark: nil, returnPort: nil, summary: summary))
        XCTAssertNil(PortFit.of(stops: ["Nassau"], embark: nil, returnPort: nil, summary: summary), "no claim without a visit or rating")
        XCTAssertEqual(PortFit.ago(3), "3 d ago")
        XCTAssertEqual(PortFit.ago(90), "3 mo ago")
    }

    func testFitNeverHidesOrOutranksAQualifyingDeal() throws {
        let store = Store.previewV4()
        let plain = Store(previewDocs: Samples.docs)
        XCTAssertTrue(store.fitOrdering)
        let filters = DealFilters()
        for bucket in [DealBucket.best, .trip] {
            XCTAssertEqual(Set(store.bucket(bucket, filters: filters, sort: .score).map { $0.id }),
                           Set(plain.bucket(bucket, filters: filters, sort: .score).map { $0.id }),
                           "the same deals, with or without fit")
        }
        let ordered = store.bucket(.best, filters: filters, sort: .score)
        let minPct = store.trip?.minPctUnder ?? 15
        let qualifies = ordered.map { !DealType.of($0, fits: false, minPctUnder: minPct).isDisjoint(with: DealOrder.priceKinds) }
        if let firstMiss = qualifies.firstIndex(of: false) {
            XCTAssertFalse(qualifies[firstMiss...].contains(true), "a price-qualifying deal is never below one that isn't")
        }
        let icon = try XCTUnwrap(store.deal("sample-fits"))
        XCTAssertEqual(store.portFit(icon)?.adj, -15)
        XCTAssertNil(plain.portFit(icon), "no fit before My trips is on")
    }
}

@MainActor
final class TripLogTests: XCTestCase {
    func testATripSavesAndNeverDuplicates() throws {
        let store = Store.previewV4()
        var draft = TripDraft()
        draft.line = "Norwegian"
        draft.ship = "Norwegian Aqua"
        XCTAssertEqual(store.logTrip(draft), .invalid("Pick the sail date."))
        draft.sailDate = Fmt.adding(days: 30, to: Date())
        XCTAssertEqual(store.logTrip(draft), .invalid("A future sailing belongs in Tracking."))
        draft.sailDate = Fmt.day(Samples.tripAqua.sailDate)
        XCTAssertEqual(store.logTrip(draft), .already("trip-sample-aqua"))

        draft.sailDate = Fmt.day(Samples.isoDay(daysFromNow: -200))
        draft.ports = [TripDraft.Port(name: "Cozumel", rating: 12), TripDraft.Port(name: " ", rating: 5)]
        let fields = draft.fields(isNew: true, stamp: "2026-11-27T20:00:00Z")
        XCTAssertEqual(fields["addedVia"], .string("manual"))
        guard case .array(let ports)? = fields["ports"] else { return XCTFail("no ports") }
        XCTAssertEqual(ports.count, 1, "a blank port is dropped")
        XCTAssertEqual(ports.first?.field("rating"), .int(10), "ratings stay 1-10")
        XCTAssertNil(draft.fields(isNew: false)["addedAt"], "an edit never sends addedVia or addedAt")

        guard case .saved(let id) = store.logTrip(draft) else { return XCTFail("not saved") }
        XCTAssertTrue(try XCTUnwrap(store.pastTrip(id)).isLocal)
        store.deleteTrip(try XCTUnwrap(store.pastTrip(id)))
        XCTAssertNil(store.pastTrip(id))
    }

    func testThePrefillShowsOnlyPortStops() {
        XCTAssertEqual(Samples.prefill.ports, ["Roatan (Coxen Hole)", "Harvest Caye", "Costa Maya", "Cozumel"])
        XCTAssertTrue(Samples.prefill.found)
        XCTAssertFalse(TripPrefill(embarkPort: nil, nights: nil, stops: [], source: nil).found)
    }
}
