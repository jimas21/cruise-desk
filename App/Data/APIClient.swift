import Foundation

enum APIError: Error {
    case notConfigured
    /// No connection, or the server is not answering. Writes stay queued.
    case offline(String)
    /// 401: the app token was not accepted.
    case unauthorized
    case notFound
    /// 409: someone else changed the document first.
    case conflict
    /// 403/413/422: the server refused this request (role rule, size, schema); retrying cannot help.
    case rejected(String)
    case server(String)
    /// 405: this deal server has no such call (an older version).
    case unsupported
}

struct SyncResult: Decodable {
    var serverTime: String
    var docs: [String: [RawDoc]]
    var deleted: [Tombstone]?
}

struct HistoryResult: Decodable {
    var history: [PricePoint]
}

struct Tombstone: Decodable {
    var coll: String
    var id: String
    var deletedAt: String?
}

/// The dealdesk-api, exactly as DESIGN.md describes it. Never logs the token.
struct APIClient {
    let base: String
    let token: String

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    // MARK: Endpoints

    func sync(since: String?) async throws -> SyncResult {
        var query: [URLQueryItem] = []
        if let since { query.append(URLQueryItem(name: "since", value: since)) }
        let data = try await call("GET", "/v1/sync", query: query)
        do {
            return try JSONDecoder().decode(SyncResult.self, from: data)
        } catch {
            throw APIError.server("The server sent something this version of the app can't read.")
        }
    }

    /// Creates the document if absent; replacing an existing one needs its current version.
    func put(_ coll: String, _ id: String, data: [String: JSONValue], ifVersion: Int?) async throws -> RawDoc? {
        var body: [String: JSONValue] = ["data": .object(data)]
        if let ifVersion { body["ifVersion"] = .int(ifVersion) }
        let out = try await call("PUT", "/v1/\(coll)/\(id)", body: .object(body))
        return try? JSONDecoder().decode(RawDoc.self, from: out)
    }

    /// Merges fields; a `null` removes that field.
    func patch(_ coll: String, _ id: String, fields: [String: JSONValue], ifVersion: Int) async throws -> RawDoc? {
        let body: JSONValue = .object(["data": .object(fields), "ifVersion": .int(ifVersion)])
        let out = try await call("PATCH", "/v1/\(coll)/\(id)", body: body)
        return try? JSONDecoder().decode(RawDoc.self, from: out)
    }

    /// Creates a document with an id the server picks (`POST /v1/{coll}`), e.g. a tracked sailing.
    func create(_ coll: String, data: [String: JSONValue]) async throws -> RawDoc? {
        let out = try await call("POST", "/v1/\(coll)", body: .object(["data": .object(data)]))
        return try? JSONDecoder().decode(RawDoc.self, from: out)
    }

    /// v3: lines, ships, size tiers and what Deal Desk can see per line. A 404 means an older server.
    func catalog() async throws -> Catalog {
        let data = try await call("GET", "/v1/catalog")
        guard let value = try? JSONDecoder().decode(Catalog.self, from: data) else {
            throw APIError.server("The catalog came back in a shape this version can't read.")
        }
        return value
    }

    /// v3: asks for a light refresh of the sources that allow it. Always 200; `accepted` says if it was taken.
    func nudge(reason: String) async throws -> NudgeResult {
        let data = try await call("POST", "/v1/refresh", body: .object(["reason": .string(reason)]))
        return (try? JSONDecoder().decode(NudgeResult.self, from: data))
            ?? NudgeResult(accepted: nil, requestedAt: nil, nextAllowedAt: nil)
    }

    /// v3: where the last refresh stands (asked, collector picked it up, done).
    func refreshState() async throws -> RefreshState {
        let data = try await call("GET", "/v1/refresh")
        guard let value = try? JSONDecoder().decode(RefreshState.self, from: data) else {
            throw APIError.server("The refresh status came back in a shape this version can't read.")
        }
        return value
    }

    /// Sailings the fare data knows for one ship, soonest first (`GET /v1/fares/sailings`), for browse-and-pick.
    func sailings(ship: String, line: String?, limit: Int = 150) async throws -> [FareSailing] {
        var query = [URLQueryItem(name: "ship", value: ship), URLQueryItem(name: "limit", value: String(limit))]
        if let line { query.append(URLQueryItem(name: "line", value: line)) }
        let data = try await call("GET", "/v1/fares/sailings", query: query)
        return (try? JSONDecoder().decode(SailingsResult.self, from: data))?.sailings ?? []
    }

    // MARK: v4

    /// `GET /v1/search`: sailings the fare sources have seen, filtered and sorted on the server (read-only).
    func search(_ query: SearchQuery, offset: Int, limit: Int = 50) async throws -> SearchResult {
        let data = try await call("GET", "/v1/search", query: query.queryItems(offset: offset, limit: limit))
        guard let value = try? JSONDecoder().decode(SearchResult.self, from: data) else {
            throw APIError.server("The search came back in a shape this version can't read.")
        }
        return value
    }

    /// `POST /v1/link/parse`: the server reads a line's own link from its text (it never fetches it).
    func parseLink(_ url: String) async throws -> LinkParse {
        let data = try await call("POST", "/v1/link/parse", body: .object(["url": .string(url)]))
        guard let value = try? JSONDecoder().decode(LinkParse.self, from: data) else {
            throw APIError.server("The link came back in a shape this version can't read.")
        }
        return value
    }

    /// `GET /v1/trips/prefill`: the ports and nights Deal Desk already knows for a past sailing.
    func prefill(line: String, ship: String, sailDate: String) async throws -> TripPrefill {
        let query = [URLQueryItem(name: "line", value: line), URLQueryItem(name: "ship", value: ship),
                     URLQueryItem(name: "sailDate", value: sailDate)]
        let data = try await call("GET", "/v1/trips/prefill", query: query)
        guard let value = try? JSONDecoder().decode(TripPrefill.self, from: data) else {
            throw APIError.server("The trip details came back in a shape this version can't read.")
        }
        return value
    }

    func delete(_ coll: String, _ id: String, ifVersion: Int) async throws {
        _ = try await call("DELETE", "/v1/\(coll)/\(id)",
                           query: [URLQueryItem(name: "ifVersion", value: String(ifVersion))])
    }

    /// That deal's price history, oldest first (`GET /v1/deals/{id}/history`), for the sparkline.
    func history(dealId: String) async throws -> [PricePoint] {
        let data = try await call("GET", "/v1/deals/\(dealId)/history")
        do {
            return try JSONDecoder().decode(HistoryResult.self, from: data).history
        } catch {
            throw APIError.server("The price history came back in a shape this version can't read.")
        }
    }

    func registerDevice(token deviceToken: String, environment: String) async throws {
        let body: JSONValue = .object(["token": .string(deviceToken), "environment": .string(environment)])
        _ = try await call("POST", "/v1/devices", body: body)
    }

    /// Reachability (no token needed), then the token itself.
    func check() async throws {
        _ = try await call("GET", "/v1/health", authorized: false)
        do {
            _ = try await call("GET", "/v1/meta/status")
        } catch APIError.notFound {
            // The token worked; the brain just hasn't written a status yet.
        }
    }

    // MARK: Transport

    private func call(_ method: String, _ path: String, query: [URLQueryItem] = [], body: JSONValue? = nil,
                      authorized: Bool = true) async throws -> Data {
        guard var components = URLComponents(string: base + path) else { throw APIError.notConfigured }
        if !query.isEmpty {
            components.queryItems = query
            // A "+" in a timestamp would otherwise arrive as a space.
            components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        }
        guard let url = components.url else { throw APIError.notConfigured }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authorized { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let result: (Data, URLResponse)
        do {
            result = try await APIClient.session.data(for: request)
        } catch {
            throw APIError.offline((error as? URLError)?.localizedDescription ?? "No connection.")
        }
        let (data, response) = result
        guard let http = response as? HTTPURLResponse else { throw APIError.server("No answer from the server.") }

        switch http.statusCode {
        case 200..<300:
            return data
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.rejected(APIClient.describe(data))
        case 404:
            throw APIError.notFound
        case 405:
            throw APIError.unsupported
        case 409:
            throw APIError.conflict
        case 413, 422:
            throw APIError.rejected(APIClient.describe(data))
        case 500...599:
            throw APIError.offline("The deal server isn't answering (HTTP \(http.statusCode)).")
        default:
            throw APIError.server("The server answered HTTP \(http.statusCode).")
        }
    }

    static func describe(_ data: Data) -> String {
        if let value = try? JSONDecoder().decode(JSONValue.self, from: data) {
            let text = value.plainText
            if !text.isEmpty { return text.capped(200) }
        }
        return String(decoding: data.prefix(160), as: UTF8.self)
    }
}
