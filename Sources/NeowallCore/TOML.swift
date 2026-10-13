import Foundation

public enum TOMLValue: Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([TOMLValue])

    public var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var bool: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var strings: [String]? {
        if case .array(let values) = self { return values.compactMap(\.string) }
        return nil
    }
}

/// Parser for the flat `key = value` subset of TOML used by the config file
/// and by Omarchy `colors.toml` theme files. Section headers are ignored.
public enum FlatTOML {
    public static func parse(_ text: String) -> [String: TOMLValue] {
        var out: [String: TOMLValue] = [:]
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = stripComment(String(rawLine)).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("["), let eq = line.firstIndex(of: "=") else { continue }
            let key = line[..<eq]
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            let value = line[line.index(after: eq)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty, let parsed = parseValue(value) { out[key] = parsed }
        }
        return out
    }

    /// Returns the prefix of `line` that precedes any `#` comment, honouring quotes.
    static func stripComment(_ line: String) -> String {
        var quote: Character?
        for index in line.indices {
            let char = line[index]
            if let open = quote {
                if char == open { quote = nil }
            } else if char == "\"" || char == "'" {
                quote = char
            } else if char == "#" {
                return String(line[..<index])
            }
        }
        return line
    }

    static func parseValue(_ raw: String) -> TOMLValue? {
        let value = raw.trimmingCharacters(in: .whitespaces)
        guard let first = value.first, let last = value.last else { return nil }
        if value.count >= 2, first == last, first == "\"" || first == "'" {
            return .string(String(value.dropFirst().dropLast()))
        }
        if first == "[", last == "]" {
            return .array(splitTopLevel(String(value.dropFirst().dropLast())).compactMap(parseValue))
        }
        if value == "true" { return .bool(true) }
        if value == "false" { return .bool(false) }
        if let number = Double(value.replacingOccurrences(of: "_", with: "")) { return .number(number) }
        return nil
    }

    private static func splitTopLevel(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        for char in text {
            if let open = quote {
                if char == open { quote = nil }
                current.append(char)
            } else if char == "\"" || char == "'" {
                quote = char
                current.append(char)
            } else if char == "," {
                parts.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        parts.append(current)
        return parts
    }
}
