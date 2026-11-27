import XCTest
@testable import DealDesk

/// A deal exactly as dealdesk-api stores it (DESIGN.md "deals"), with every field filled.
private let serverDeal = """
{"id": "icon-2028-10-15-7n", "version": 3, "updatedAt": "2026-11-27T10:21:00Z", "data": {
  "kind": "fits", "ship": "Icon of the Seas", "shipClass": "icon", "sailDate": "2028-10-15", "nights": 7,
  "port": "Galveston", "roundTrip": true, "region": "Western Caribbean", "cabin": "balcony",
  "cabinName": "Ocean View Balcony", "oceanViewConfirmed": null, "pricePP": 1138, "priceIncludesTaxes": true,
  "usualPP": 1520, "previousPP": 1187, "lowestSeenPP": 1138, "perNightPP": 163, "totalFor3": 2580,
  "totalAssumes": "3rd guest sails free", "score": 70, "scoreLabel": "Great",
  "why": "Lowest Icon balcony we've seen — $163/night vs $216", "breaks": null, "flight": "~3h nonstop",
  "perks": ["Free 3rd guest", "BOGO60"], "bookBy": "2026-11-29", "bookByWhat": "Black Friday $300 off",
  "link": "https://example.com/sailing", "linkLabel": "Example",
  "sources": [{"name": "Example", "url": "https://example.com/a", "pricePP": 1138, "includesTaxes": true},
              {"name": "Other", "url": "https://example.com/b", "pricePP": null, "includesTaxes": null}],
  "ports": ["Roatán", "Cozumel"], "nearby": null, "scoreHow": "+40 below median", "notes": null,
  "offers": null, "endsAt": null, "postedAt": "2026-11-27T10:21:00Z", "changedAt": "2026-11-27T10:21:00Z",
  "someFutureField": {"nested": [1, 2.5, "x"]}
}}
"""

final class FormatTests: XCTestCase {
    func testMoney() {
        XCTAssertEqual(Fmt.usd(2580), "$2,580")
        XCTAssertEqual(Fmt.usd(163), "$163")
        XCTAssertEqual(Fmt.usd(12450), "$12,450")
    }

    func testDateRanges() throws {
        XCTAssertEqual(Fmt.range(from: try XCTUnwrap(Fmt.day("2028-10-15")), nights: 7), "Oct 15–22, 2028")
        XCTAssertEqual(Fmt.range(from: try XCTUnwrap(Fmt.day("2028-10-29")), nights: 7), "Oct 29 – Nov 5, 2028")
        XCTAssertEqual(Fmt.range(from: try XCTUnwrap(Fmt.day("2027-12-28")), nights: 7), "Dec 28, 2027 – Jan 4, 2028")
        XCTAssertEqual(Fmt.nights(1), "1 night")
        XCTAssertEqual(Fmt.nights(6), "6 nights")
        XCTAssertNil(Fmt.day("soon"))
    }

    func testCountdown() {
        let day: TimeInterval = 86400
        XCTAssertEqual(Fmt.countdown(Date()), "last day")
        XCTAssertEqual(Fmt.countdown(Date().addingTimeInterval(day)), "1 day left")
        XCTAssertEqual(Fmt.countdown(Date().addingTimeInterval(2 * day)), "2 days left")
        XCTAssertEqual(Fmt.countdown(Date().addingTimeInterval(-2 * day)), "ended")
        XCTAssertEqual(Fmt.weekday(Fmt.day("2026-11-29")!), "Sun Nov 29")
    }

    func testTimestamps() {
        XCTAssertNotNil(Fmt.timestamp("2026-11-27T10:21:00Z"))
        XCTAssertNotNil(Fmt.timestamp("2026-11-27T10:21:00.123Z"))
        XCTAssertNil(Fmt.timestamp("yesterday"))
        let stamp = Fmt.stamp(Date(timeIntervalSince1970: 0))
        XCTAssertEqual(stamp, "1970-01-01T00:00:00Z")
    }

    func testOnlyWebLinksOpen() {
        XCTAssertNotNil(Fmt.webURL("https://example.com/deal"))
        XCTAssertNil(Fmt.webURL("javascript:alert(1)"))
        XCTAssertNil(Fmt.webURL("dealdesk://deal/x"))
        XCTAssertNil(Fmt.webURL(nil))
    }
}

final class ModelTests: XCTestCase {
    func testServerDealDecodes() throws {
        let raw = try JSONDecoder().decode(RawDoc.self, from: Data(serverDeal.utf8))
        let deal = try XCTUnwrap(Deal(raw: raw))
        XCTAssertEqual(deal.id, "icon-2028-10-15-7n")
        XCTAssertEqual(deal.version, 3)
        XCTAssertEqual(deal.kind, .fits)
        XCTAssertEqual(deal.tripLine, "7 nights · Oct 15–22, 2028 · Galveston")
        XCTAssertEqual(deal.cabinTitle, "Balcony")
        XCTAssertEqual(deal.dropPP, 49)
        XCTAssertEqual(deal.data.totalFor3, 2580)
        XCTAssertEqual(deal.data.sources?.count, 2)
        XCTAssertNil(deal.data.sources?[1].pricePP)
        XCTAssertNotNil(deal.link)
    }

    func testSpeechReadsTheGlance() throws {
        let raw = try JSONDecoder().decode(RawDoc.self, from: Data(serverDeal.utf8))
        let spoken = Speech.deal(try XCTUnwrap(Deal(raw: raw)))
        XCTAssertTrue(spoken.hasPrefix("Fits your trip. Icon of the Seas."))
        XCTAssertTrue(spoken.contains("$2,580 for 3"))
        XCTAssertTrue(spoken.contains("Balcony, type not confirmed"))
        XCTAssertTrue(spoken.contains("Score 70, Great"))
    }

    func testSyncResponseDecodes() throws {
        let body = """
        {"serverTime": "2026-11-27T17:12:00Z",
         "docs": {"deals": [\(serverDeal)],
                  "meta": [{"id": "status", "version": 9, "updatedAt": "2026-11-27T17:12:00Z",
                            "data": {"lastRun": "2026-11-27T17:12:00Z", "ok": false, "sourcesWorked": ["A", "B"],
                                     "sourcesFailed": ["C"], "sailingsChecked": 203, "newItems": 0,
                                     "error": "timed out"}}],
                  "feedback": []},
         "deleted": [{"coll": "rules", "id": "old-rule", "deletedAt": "2026-11-27T17:00:00Z"}]}
        """
        let result = try JSONDecoder().decode(SyncResult.self, from: Data(body.utf8))
        XCTAssertEqual(result.serverTime, "2026-11-27T17:12:00Z")
        XCTAssertEqual(result.docs["deals"]?.count, 1)
        XCTAssertEqual(result.deleted?.first?.id, "old-rule")
        let status = try XCTUnwrap(RunStatus(raw: try XCTUnwrap(result.docs["meta"]?.first)))
        XCTAssertTrue(status.failed)
        XCTAssertEqual(status.worked, ["A", "B"])
        XCTAssertEqual(status.data.sailingsChecked, 203)
    }

    func testPlayCatchFieldMaps() throws {
        let raw = RawDoc(id: "p", data: .object(["kind": .string("now"), "title": .string("T"),
                                                 "catch": .string("Non-refundable")]), version: 1, updatedAt: nil)
        let play = try XCTUnwrap(Play(raw: raw))
        XCTAssertTrue(play.isLive)
        XCTAssertEqual(play.data.catchText, "Non-refundable")
    }
}

final class JSONValueTests: XCTestCase {
    func testPatchMergeRemovesNulls() {
        let doc: JSONValue = .object(["verdict": .string("pass"), "claudeReply": .string("ok"), "note": .string("")])
        let merged = doc.merging(["verdict": .string("later"), "claudeReply": .null])
        XCTAssertEqual(merged, .object(["verdict": .string("later"), "note": .string("")]))
    }

    func testIntegersStayIntegers() throws {
        let data = try JSONEncoder().encode(JSONValue.object(["pricePP": .int(1138)]))
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "{\"pricePP\":1138}")
        let back = try JSONDecoder().decode(JSONValue.self, from: Data("[1138, 2.5, true, null]".utf8))
        XCTAssertEqual(back, .array([.int(1138), .double(2.5), .bool(true), .null]))
    }

    func testValidationErrorsReadPlainly() {
        let body = Data(#"{"detail": [{"loc": ["body", "data", "why"], "msg": "at most 90 characters"}]}"#.utf8)
        XCTAssertEqual(APIClient.describe(body), "why: at most 90 characters")
        XCTAssertEqual(APIClient.describe(Data(#"{"detail": "not allowed"}"#.utf8)), "not allowed")
    }
}

@MainActor
final class StoreTests: XCTestCase {
    func testAnswerMovesDealToReviewed() throws {
        let store = Store.preview()
        let before = store.inbox.count
        let deal = try XCTUnwrap(store.deal("sample-fits"))
        store.answer(deal, verdict: .pass, reasons: ["price", "dates"], note: "Too long a flight")
        XCTAssertEqual(store.inbox.count, before - 1)
        XCTAssertEqual(store.feedback["sample-fits"]?.verdict, .pass)
        XCTAssertEqual(store.feedback["sample-fits"]?.data.reasons, ["price", "dates"])
        XCTAssertTrue(store.isPending("feedback", "sample-fits"))
        XCTAssertEqual(store.reviewed(.pass).map { $0.id }, ["sample-fits"])
    }

    func testChangingAnAnswerClearsClaudesOldReply() throws {
        let store = Store.preview()
        XCTAssertNotNil(store.feedback["sample-drop"]?.reply)
        let deal = try XCTUnwrap(store.deal("sample-drop"))
        store.answer(deal, verdict: .later, reasons: [], note: "")
        XCTAssertEqual(store.feedback["sample-drop"]?.verdict, .later)
        XCTAssertNil(store.feedback["sample-drop"]?.reply)
    }

    func testRuleLifecycle() throws {
        let store = Store.preview()
        store.addRule(text: "No 4-night sailings", unless: "", fromDeal: "sample-call")
        let rule = try XCTUnwrap(store.rules.first { $0.text == "No 4-night sailings" })
        XCTAssertEqual(rule.status, .active)
        XCTAssertEqual(rule.data.origin, "jim")
        XCTAssertEqual(rule.data.fromDeal, "sample-call")
        XCTAssertTrue(rule.id.hasPrefix("jim-"))
        store.setRule(rule, status: .paused)
        XCTAssertEqual(store.rules.first { $0.id == rule.id }?.status, .paused)
        store.deleteRule(rule)
        XCTAssertNil(store.rules.first { $0.id == rule.id })
    }

    func testPlayNote() {
        let store = Store.preview()
        store.savePlayNote(playId: "sample-standing", status: .question, note: "Does this work after final payment?")
        XCTAssertEqual(store.playNotes["sample-standing"]?.status, .question)
    }

    func testNewIdsFitTheServerPattern() {
        let id = Store.newId(prefix: "jim")
        XCTAssertTrue(Router.isValidId(id))
        XCTAssertLessThanOrEqual(id.count, 80)
    }
}

@MainActor
final class RouterTests: XCTestCase {
    func testDealLinksOpenTheDeal() {
        let router = Router()
        router.tab = .rules
        router.handle(url: URL(string: "dealdesk://deal/icon-2028-10-15-7n")!)
        XCTAssertEqual(router.tab, .deals)
        XCTAssertEqual(router.dealsPath, ["icon-2028-10-15-7n"])
    }

    func testOtherLinksAreIgnored() {
        let router = Router()
        router.handle(url: URL(string: "https://example.com/deal/x")!)
        router.handle(url: URL(string: "dealdesk://deal/Not%20An%20Id")!)
        router.handle(url: URL(string: "dealdesk://rules/x")!)
        XCTAssertEqual(router.dealsPath, [])
    }
}
