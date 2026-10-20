import Foundation

/// Numbers remain source tokens: formatting must never round IDs or normalize exponents.
indirect enum JSONValue {
    case object([(String, JSONValue)])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    var children: [(String, JSONValue)] {
        switch self {
        case .object(let members): return members
        case .array(let values): return values.enumerated().map { (String($0.offset), $0.element) }
        default: return []
        }
    }
    var typeName: String {
        switch self {
        case .object: return "object"
        case .array: return "array"
        case .string: return "string"
        case .number: return "number"
        case .bool: return "boolean"
        case .null: return "null"
        }
    }
    var summary: String {
        switch self {
        case .object(let items): return "{ \(items.count) 个字段 }"
        case .array(let items): return "[ \(items.count) 项 ]"
        default: return rendered(indent: 0)
        }
    }
    /// Compare numeric values without converting through floating point, even for large IDs.
    private static func normalizedNumber(_ token: String) -> (String, Int)? {
        let parts = token.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        guard let exponent = parts.count == 2 ? Int(parts[1]) : 0 else { return nil }
        var mantissa = String(parts[0])
        let negative = mantissa.hasPrefix("-")
        if negative { mantissa.removeFirst() }
        let fraction = mantissa.split(separator: ".", omittingEmptySubsequences: false)
        var digits = Array(mantissa.filter { $0 != "." }.drop(while: { $0 == "0" }))
        if digits.isEmpty { return ("0", 0) }
        var zeros = 0
        while digits.last == "0" { digits.removeLast(); zeros += 1 }
        let adjustment = zeros - (fraction.count == 2 ? fraction[1].count : 0)
        let (power, overflow) = exponent.addingReportingOverflow(adjustment)
        guard !overflow else { return nil }
        return ((negative ? "-" : "") + String(digits), power)
    }
    var isInteger: Bool {
        guard case .number(let token) = self, let normalized = Self.normalizedNumber(token) else { return false }
        return normalized.1 >= 0
    }
    func equivalent(to other: JSONValue) -> Bool {
        switch (self, other) {
        case (.number(let a), .number(let b)):
            if let x = Self.normalizedNumber(a), let y = Self.normalizedNumber(b) { return x == y }
            return a == b
        case (.array(let a), .array(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.equivalent(to: $1) }
        case (.object(let a), .object(let b)):
            let x = a.sorted { $0.0 < $1.0 }, y = b.sorted { $0.0 < $1.0 }
            return x.count == y.count && zip(x, y).allSatisfy { $0.0 == $1.0 && $0.1.equivalent(to: $1.1) }
        default: return rendered(indent: 0) == other.rendered(indent: 0)
        }
    }
    static func quote(_ text: String) -> String {
        let data = try! JSONSerialization.data(withJSONObject: text, options: [.fragmentsAllowed, .withoutEscapingSlashes])
        return String(decoding: data, as: UTF8.self)
    }
    func rendered(indent: Int = 2, sort: String = "original", level: Int = 0) -> String {
        let pretty = indent > 0
        let padding = String(repeating: " ", count: level * indent)
        let inner = String(repeating: " ", count: (level + 1) * indent)
        func container(_ start: String, _ end: String, _ items: [String]) -> String {
            guard !items.isEmpty else { return start + end }
            return pretty ? start + "\n" + inner + items.joined(separator: ",\n" + inner) + "\n" + padding + end : start + items.joined(separator: ",") + end
        }
        switch self {
        case .object(let members):
            let ordered = sort == "original" ? members : members.sorted { sort == "ascending" ? $0.0 < $1.0 : $0.0 > $1.0 }
            return container("{", "}", ordered.map { Self.quote($0.0) + (pretty ? ": " : ":") + $0.1.rendered(indent: indent, sort: sort, level: level + 1) })
        case .array(let values): return container("[", "]", values.map { $0.rendered(indent: indent, sort: sort, level: level + 1) })
        case .string(let value): return Self.quote(value)
        case .number(let token): return token
        case .bool(let value): return value ? "true" : "false"
        case .null: return "null"
        }
    }
    func nestedDecoded(depth: Int = 0) -> JSONValue {
        guard depth < 32 else { return self }
        switch self {
        case .string(let text):
            guard let parsed = try? JSONParser.parse(text) else { return self }
            if case .string(let next) = parsed, next == text { return self }
            return parsed.nestedDecoded(depth: depth + 1)
        case .object(let fields): return .object(fields.map { ($0.0, $0.1.nestedDecoded(depth: depth + 1)) })
        case .array(let values): return .array(values.map { $0.nestedDecoded(depth: depth + 1) })
        default: return self
        }
    }
    static func pointerToken(_ key: String) -> String { key.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1") }
    static func pointerParts(_ pointer: String) throws -> [String] {
        if pointer.isEmpty { return [] }
        guard pointer.hasPrefix("/") else { throw JSONToolError("路径使用 JSON Pointer，例如 /data/0/name") }
        return try pointer.dropFirst().components(separatedBy: "/").map { token in
            let bytes = Array(token)
            for i in bytes.indices where bytes[i] == "~" {
                guard i + 1 < bytes.count, bytes[i + 1] == "0" || bytes[i + 1] == "1" else { throw JSONToolError("路径中无效的 ~ 转义") }
            }
            return token.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
        }
    }
    func at(_ parts: [String]) throws -> JSONValue {
        guard let key = parts.first else { return self }
        guard let child = children.first(where: { $0.0 == key }) else { throw JSONToolError("路径不存在：\(key)") }
        return try child.1.at(Array(parts.dropFirst()))
    }
    func replacing(_ parts: [String], with replacement: JSONValue) throws -> JSONValue {
        guard let key = parts.first else { return replacement }
        let rest = Array(parts.dropFirst())
        switch self {
        case .object(var fields):
            guard let i = fields.firstIndex(where: { $0.0 == key }) else { throw JSONToolError("字段不存在：\(key)") }
            fields[i].1 = try fields[i].1.replacing(rest, with: replacement)
            return .object(fields)
        case .array(var items):
            guard let i = Int(key), String(i) == key, items.indices.contains(i) else { throw JSONToolError("数组下标无效") }
            items[i] = try items[i].replacing(rest, with: replacement)
            return .array(items)
        default: throw JSONToolError("该节点没有子节点")
        }
    }
}

struct JSONToolError: LocalizedError {
    let message: String
    var offset: Int? = nil
    init(_ message: String, offset: Int? = nil) { self.message = message; self.offset = offset }
    var errorDescription: String? { message }
}

struct JSONParser {
    private let source: [UInt8]
    private var index = 0
    static let maximumBytes = 2_000_000

    static func parse(_ text: String) throws -> JSONValue {
        guard text.utf8.count <= maximumBytes else { throw JSONToolError("文件超过 2 MB，请缩小后再处理") }
        var parser = JSONParser(source: Array(text.utf8))
        let result = try parser.value(depth: 0)
        parser.whitespace()
        guard parser.index == parser.source.count else { throw parser.failure("JSON 后存在多余内容") }
        return result
    }
    private func failure(_ message: String) -> JSONToolError {
        let prefix = String(decoding: source.prefix(index), as: UTF8.self)
        let line = prefix.filter { $0 == "\n" }.count + 1
        let column = (prefix.split(separator: "\n", omittingEmptySubsequences: false).last?.count ?? 0) + 1
        return JSONToolError("第 \(line) 行，第 \(column) 列：\(message)", offset: prefix.utf16.count)
    }
    private mutating func whitespace() { while index < source.count && [9, 10, 13, 32].contains(source[index]) { index += 1 } }
    private mutating func take(_ byte: UInt8) -> Bool {
        if index < source.count && source[index] == byte { index += 1; return true }
        return false
    }
    private mutating func string() throws -> String {
        let start = index
        guard take(34) else { throw failure("应为双引号字符串") }
        while index < source.count {
            let byte = source[index]; index += 1
            if byte == 34 {
                let data = Data(source[start..<index])
                guard let text = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) as? String else { throw failure("字符串转义或 Unicode 无效") }
                return text
            }
            if byte < 32 { throw failure("字符串中存在未转义的控制字符") }
            if byte == 92 { index += 1 }
        }
        throw failure("字符串缺少结束引号")
    }
    private mutating func value(depth: Int) throws -> JSONValue {
        guard depth <= 128 else { throw failure("嵌套深度超过 128 层") }
        whitespace()
        guard index < source.count else { throw failure("缺少 JSON 值") }
        if source[index] == 34 { return .string(try string()) }
        if take(123) {
            whitespace()
            if take(125) { return .object([]) }
            var fields: [(String, JSONValue)] = []
            while true {
                whitespace(); let key = try string(); whitespace()
                guard take(58) else { throw failure("字段名后缺少冒号") }
                fields.append((key, try value(depth: depth + 1)))
                whitespace()
                if take(125) { return .object(fields) }
                guard take(44) else { throw failure("字段间缺少逗号") }
            }
        }
        if take(91) {
            whitespace()
            if take(93) { return .array([]) }
            var values: [JSONValue] = []
            while true {
                values.append(try value(depth: depth + 1)); whitespace()
                if take(93) { return .array(values) }
                guard take(44) else { throw failure("数组项之间缺少逗号") }
            }
        }
        for (literal, result) in [("true", JSONValue.bool(true)), ("false", .bool(false)), ("null", .null)] {
            let bytes = Array(literal.utf8)
            if source[index...].starts(with: bytes) { index += bytes.count; return result }
        }
        let start = index
        _ = take(45)
        if !take(48) {
            guard index < source.count, (49...57).contains(source[index]) else { throw failure("应为对象、数组、字符串、数字、true、false 或 null") }
            while index < source.count && (48...57).contains(source[index]) { index += 1 }
        }
        if take(46) { try digits() }
        if take(101) || take(69) { if !take(43) { _ = take(45) }; try digits() }
        return .number(String(decoding: source[start..<index], as: UTF8.self))
    }
    private mutating func digits() throws {
        let start = index
        while index < source.count && (48...57).contains(source[index]) { index += 1 }
        guard start != index else { throw failure("数字不完整") }
    }
}

/// Explicitly scoped offline validator. Unsupported assertions fail visibly instead of silently passing.
enum JSONSchemaValidator {
    private static let supported: Set<String> = ["$schema", "$id", "title", "description", "default", "examples", "type", "properties", "required", "items", "enum", "const", "additionalProperties", "minItems", "maxItems", "minLength", "maxLength"]

    private static func verifySchema(_ schema: JSONValue) throws {
        if case .bool = schema { return }
        guard case .object(let fields) = schema else { throw JSONToolError("Schema 必须是对象或布尔值") }
        for (key, value) in fields {
            guard supported.contains(key) else { throw JSONToolError("当前离线校验暂不支持 Schema 关键字：\(key)") }
            if key == "properties" {
                guard case .object(let properties) = value else { throw JSONToolError("Schema properties 必须为对象") }
                for (_, rule) in properties { try verifySchema(rule) }
            } else if key == "items" || key == "additionalProperties" { try verifySchema(value) }
        }
    }
    static func validate(_ value: JSONValue, schema: JSONValue, path: String = "$") throws -> [String] {
        if path == "$" { try verifySchema(schema) }
        if case .bool(let allowed) = schema { return allowed ? [] : ["\(path)：Schema 不允许此值"] }
        guard case .object(let fields) = schema else { throw JSONToolError("Schema 必须是对象或布尔值") }
        func field(_ name: String) -> JSONValue? { fields.first { $0.0 == name }?.1 }
        var errors: [String] = []
        if let type = field("type") {
            let types: [String]
            switch type {
            case .string(let name): types = [name]
            case .array(let values): types = try values.map { guard case .string(let name) = $0 else { throw JSONToolError("Schema type 必须是字符串") }; return name }
            default: throw JSONToolError("Schema type 无效")
            }
            guard !types.isEmpty, types.allSatisfy({ ["object", "array", "string", "number", "integer", "boolean", "null"].contains($0) }) else { throw JSONToolError("Schema type 无效") }
            let integer = value.isInteger
            if !types.contains(value.typeName) && !(integer && types.contains("integer")) { errors.append("\(path)：期望 \(types.joined(separator: " / "))，实际 \(value.typeName)") }
        }
        func same(_ a: JSONValue, _ b: JSONValue) -> Bool { a.equivalent(to: b) }
        if let allowed = field("enum") {
            guard case .array(let choices) = allowed, !choices.isEmpty else { throw JSONToolError("Schema enum 必须为非空数组") }
            if !choices.contains(where: { same($0, value) }) { errors.append("\(path)：不在 enum 候选值中") }
        }
        if let expected = field("const"), !same(expected, value) { errors.append("\(path)：不符合 const") }
        func checkCount(_ count: Int, min: String, max: String) throws {
            for key in [min, max] {
                if let limit = field(key) {
                    guard case .number(let token) = limit, let n = Int(token), n >= 0 else { throw JSONToolError("Schema \(key) 必须为非负整数") }
                    if (key == min && count < n) || (key == max && count > n) { errors.append("\(path)：不符合 \(key) = \(n)") }
                }
            }
        }
        switch value {
        case .object(let members):
            if let required = field("required") {
                guard case .array(let keys) = required else { throw JSONToolError("Schema required 必须为数组") }
                for key in keys {
                    guard case .string(let name) = key else { throw JSONToolError("Schema required 项必须为字符串") }
                    if !members.contains(where: { $0.0 == name }) { errors.append("\(path)：缺少必填字段 \(name)") }
                }
            }
            var properties: [(String, JSONValue)] = []
            if let p = field("properties") { guard case .object(let pairs) = p else { throw JSONToolError("Schema properties 必须为对象") }; properties = pairs }
            for (name, child) in members {
                if let rule = properties.first(where: { $0.0 == name })?.1 ?? field("additionalProperties") {
                    errors += try validate(child, schema: rule, path: path + "/" + JSONValue.pointerToken(name))
                }
            }
        case .array(let values):
            try checkCount(values.count, min: "minItems", max: "maxItems")
            if let items = field("items") { for (i, child) in values.enumerated() { errors += try validate(child, schema: items, path: path + "/\(i)") } }
        case .string(let string): try checkCount(string.unicodeScalars.count, min: "minLength", max: "maxLength")
        default: break
        }
        return errors
    }
}
