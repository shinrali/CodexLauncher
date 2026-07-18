import Foundation

struct TOMLSection {
    var name: String?
    var lines: [String]
}

enum TOMLSupport {
    static func splitSections(_ text: String) -> [TOMLSection] {
        var sections: [TOMLSection] = [TOMLSection(name: nil, lines: [])]

        for line in text.components(separatedBy: .newlines) {
            if let sectionName = sectionName(from: line) {
                sections.append(TOMLSection(name: sectionName, lines: [line]))
            } else {
                sections[sections.count - 1].lines.append(line)
            }
        }

        return sections
    }

    static func sectionName(from line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("["), trimmed.hasSuffix("]") else { return nil }
        return String(trimmed.dropFirst().dropLast())
    }

    static func keyValues(in lines: [String]) -> [String: String] {
        var result: [String: String] = [:]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix("["),
                  let equals = trimmed.firstIndex(of: "=")
            else { continue }

            let key = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            result[key] = unquote(rawValue)
        }

        return result
    }

    static func unquote(_ value: String) -> String {
        var value = value
        if let comment = value.firstIndex(of: "#") {
            let beforeComment = value[..<comment]
            if beforeComment.filter({ $0 == "\"" }).count % 2 == 0 {
                value = String(beforeComment).trimmingCharacters(in: .whitespaces)
            }
        }

        guard value.count >= 2 else { return value }
        if value.hasPrefix("\""), value.hasSuffix("\"") {
            return String(value.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        if value.hasPrefix("'"), value.hasSuffix("'") {
            return String(value.dropFirst().dropLast())
        }
        return value
    }

    static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func stringArray(_ value: String?) -> [String] {
        guard var value else { return [] }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("["), value.hasSuffix("]") else { return [] }
        return splitCommaSeparated(String(value.dropFirst().dropLast())).map(unquote)
    }

    static func quotedArray(_ values: [String]) -> String {
        "[" + values.map(quoted).joined(separator: ", ") + "]"
    }

    static func inlineStringTable(_ value: String?) -> [String: String] {
        guard var value else { return [:] }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("{"), value.hasSuffix("}") else { return [:] }

        var result: [String: String] = [:]
        for item in splitCommaSeparated(String(value.dropFirst().dropLast())) {
            guard let equals = firstUnquotedEquals(in: item) else { continue }
            let key = String(item[..<equals]).trimmingCharacters(in: .whitespacesAndNewlines)
            let raw = String(item[item.index(after: equals)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            result[unquote(key)] = unquote(raw)
        }
        return result
    }

    static func updatingKeys(in lines: [String], values: [String: String?]) -> [String] {
        var result = lines
        var handled: Set<String> = []

        for index in result.indices {
            let trimmed = result[index].trimmingCharacters(in: .whitespaces)
            guard !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix("["),
                  let equals = firstUnquotedEquals(in: trimmed)
            else { continue }
            let key = String(trimmed[..<equals]).trimmingCharacters(in: .whitespaces)
            guard let value = values[key] else { continue }
            handled.insert(key)
            result[index] = value.map { "\(key) = \($0)" } ?? ""
        }

        let additions = values.compactMap { key, value -> String? in
            guard !handled.contains(key), let value else { return nil }
            return "\(key) = \(value)"
        }.sorted()

        let headerIndex = result.firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") }
        let insertionIndex = headerIndex.map { result.index(after: $0) } ?? result.startIndex
        result.insert(contentsOf: additions, at: insertionIndex)
        return result.filter { !$0.isEmpty }
    }

    private static func splitCommaSeparated(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false

        for character in text {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\", quote == "\"" {
                current.append(character)
                escaped = true
                continue
            }
            if character == "\"" || character == "'" {
                if quote == character { quote = nil }
                else if quote == nil { quote = character }
                current.append(character)
                continue
            }
            if character == ",", quote == nil {
                let item = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !item.isEmpty { result.append(item) }
                current = ""
            } else {
                current.append(character)
            }
        }

        let item = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !item.isEmpty { result.append(item) }
        return result
    }

    private static func firstUnquotedEquals(in text: String) -> String.Index? {
        var quote: Character?
        var escaped = false
        for index in text.indices {
            let character = text[index]
            if escaped { escaped = false; continue }
            if character == "\\", quote == "\"" { escaped = true; continue }
            if character == "\"" || character == "'" {
                if quote == character { quote = nil }
                else if quote == nil { quote = character }
            } else if character == "=", quote == nil {
                return index
            }
        }
        return nil
    }
}
