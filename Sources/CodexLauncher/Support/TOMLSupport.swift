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
}
