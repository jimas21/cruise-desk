import Foundation

/// Any JSON value. Documents are cached and queued as raw JSON so a newer server field is never lost, and so a
/// PATCH can carry `null` (which removes a field on the server).
enum JSONValue: Hashable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])
}

extension JSONValue: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}

extension JSONValue {
    /// Converts any Encodable value (used for sample data in previews).
    init<T: Encodable>(encoding value: T) {
        if let data = try? JSONEncoder().encode(value),
           let decoded = try? JSONDecoder().decode(JSONValue.self, from: data) {
            self = decoded
        } else {
            self = .null
        }
    }

    /// Decodes this value into a typed model, or nil if it does not fit.
    func decode<T: Decodable>(_ type: T.Type) -> T? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    /// PATCH semantics, as the server applies them: fields are merged and a `null` removes the field.
    func merging(_ fields: [String: JSONValue]) -> JSONValue {
        var object: [String: JSONValue] = [:]
        if case .object(let existing) = self { object = existing }
        for (key, value) in fields {
            if value == .null {
                object.removeValue(forKey: key)
            } else {
                object[key] = value
            }
        }
        return .object(object)
    }

    /// A short, readable rendering of an error body such as `{"detail": [{"loc": [...], "msg": "..."}]}`.
    var plainText: String {
        switch self {
        case .null:
            return ""
        case .bool(let value):
            return value ? "true" : "false"
        case .int(let value):
            return String(value)
        case .double(let value):
            return String(value)
        case .string(let value):
            return value
        case .array(let items):
            return items.map { $0.plainText }.filter { !$0.isEmpty }.joined(separator: "; ")
        case .object(let object):
            if let detail = object["detail"] { return detail.plainText }
            if let errors = object["errors"] { return errors.plainText }
            let message = (object["msg"] ?? object["message"] ?? object["error"])?.plainText
            var field: String?
            if case .array(let parts)? = object["loc"] {
                field = parts.map { $0.plainText }.filter { $0 != "body" && $0 != "data" }.joined(separator: ".")
            } else if let named = object["field"] {
                field = named.plainText
            }
            if let message {
                if let field, !field.isEmpty { return "\(field): \(message)" }
                return message
            }
            return object.keys.sorted().map { key in "\(key): \(object[key]?.plainText ?? "")" }.joined(separator: "; ")
        }
    }
}
