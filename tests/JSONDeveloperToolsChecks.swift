import Foundation

@main struct JSONDeveloperToolsChecks {
    static func main() throws {
        var checks = 0
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message); checks += 1
        }
        let source = #"{"z":99581589502011978889,"a":1.2300e+400,"中":"😀\n北京","z":false}"#
        let parsed = try JSONParser.parse(source)
        let formatted = parsed.rendered(indent: 4)
        expect(formatted.contains("99581589502011978889"), "Long integers must remain exact")
        expect(formatted.contains("1.2300e+400"), "Exponent tokens must remain exact")
        expect(parsed.children.map(\.0) == ["z", "a", "中", "z"], "Order and duplicate keys must survive")
        let roundtrip = try JSONParser.parse(formatted).rendered(indent: 0)
        expect(roundtrip == parsed.rendered(indent: 0), "Format/minify round trip")
        expect(parsed.rendered(sort: "ascending").range(of: "\"a\"")!.lowerBound < parsed.rendered(sort: "ascending").range(of: "\"z\"")!.lowerBound, "Sort keys")
        for source in ["null", "true", "false", "0", "-0", "-1.25E-3", "[]", "{}", #""hello""#] {
            _ = try JSONParser.parse(source); checks += 1
        }
        for source in ["", "01", "-", "1.", "1e", "[1,]", "{\"x\":1,}", "{x:1}", "true false", "[NaN]", "\"a\nb\"", #""\x""#, #""\uD800""#, "[1 2]", "\u{FEFF}{}"] {
            do { _ = try JSONParser.parse(source); fatalError("Accepted malformed JSON: \(source)") } catch { checks += 1 }
        }
        do { _ = try JSONParser.parse("{\n  \"你好\":\n}"); fatalError("Missing value accepted") }
        catch let error as JSONToolError { expect(error.message.contains("第 3 行"), "Error line"); expect(error.offset == "{\n  \"你好\":\n".utf16.count, "UTF16 error offset") }
        let quoted = JSONValue.quote("a\n\"😀\\b")
        guard case .string(let decoded) = try JSONParser.parse(quoted) else { fatalError() }
        expect(decoded == "a\n\"😀\\b", "Escape Unicode roundtrip")
        let nested = try JSONParser.parse(#"{"payload":"{\"x\":123}"}"#).nestedDecoded()
        expect(tryValue(nested, "/payload/x") == "123", "Nested decode")
        let pointer = try JSONParser.parse(#"{"a/b":{"~":[1,2]}}"#)
        expect(tryValue(pointer, "/a~1b/~0/1") == "2", "Escaped JSON pointer")
        let edited = try pointer.replacing(JSONValue.pointerParts("/a~1b/~0/0"), with: .number("999999999999999999999"))
        expect(tryValue(edited, "/a~1b/~0/0") == "999999999999999999999", "Node editing preserves precision")
        do { _ = try JSONValue.pointerParts("/a~2"); fatalError("Bad pointer accepted") } catch { checks += 1 }
        expect(JSONValue.number("1.0").equivalent(to: .number("1e0")), "Schema numeric equality")
        expect(JSONValue.number("1e400").isInteger, "Large integer exponents")
        expect(!JSONValue.number("995815895020119788891234567890123456789").equivalent(to: .number("995815895020119788891234567890123456788")), "Schema comparison must not round numbers")
        expect(!JSONValue.number("1.5").isInteger, "Fraction is not integer")
        let schema = try JSONParser.parse(#"{"type":"object","required":["name"],"properties":{"name":{"type":"string","minLength":2}},"additionalProperties":false}"#)
        let valid = try JSONParser.parse(#"{"name":"Eave"}"#)
        expect(trySchema(valid, schema).isEmpty, "Valid schema")
        let invalid = try JSONParser.parse(#"{"name":"a","extra":1}"#)
        expect(trySchema(invalid, schema).count == 2, "Schema diagnostics")
        do { _ = try JSONSchemaValidator.validate(valid, schema: JSONParser.parse(#"{"$ref":"https://example.com"}"#)); fatalError("Unsupported reference accepted") } catch { checks += 1 }
        do { _ = try JSONSchemaValidator.validate(valid, schema: JSONParser.parse(#"{"properties":{"absent":{"$ref":"external.json"}}}"#)); fatalError("Unsupported inactive schema accepted") } catch { checks += 1 }
        let escapedSchema = try JSONParser.parse(#"{"type":"integer","enum":[1e400]}"#)
        expect(trySchema(.number("10e399"), escapedSchema).isEmpty, "Schema integer equality with large exponent")
        do { _ = try JSONParser.parse(String(repeating: "[", count: 130) + "0" + String(repeating: "]", count: 130)); fatalError("Depth limit") } catch { checks += 1 }
        do { _ = try JSONParser.parse(String(repeating: " ", count: JSONParser.maximumBytes + 1)); fatalError("Size limit") } catch { checks += 1 }
        print("PASS: \(checks) JSON developer tool checks")
    }
    static func tryValue(_ root: JSONValue, _ pointer: String) -> String { try! root.at(JSONValue.pointerParts(pointer)).rendered(indent: 0) }
    static func trySchema(_ root: JSONValue, _ schema: JSONValue) -> [String] { try! JSONSchemaValidator.validate(root, schema: schema) }
}
