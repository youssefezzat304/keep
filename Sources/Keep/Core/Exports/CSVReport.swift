import Foundation

nonisolated enum CSVField: Sendable {
    case text(String)
    case value(String)
    static func number(_ value: Double) -> Self { .value(String(value)) }
    static func integer(_ value: Int) -> Self { .value(String(value)) }
    static func flag(_ value: Bool) -> Self { .value(value ? "true" : "false") }
}

nonisolated enum CSVReport {
    /// User-authored text is prefixed with an apostrophe if a spreadsheet could evaluate it.
    static func encode(headers: [String], rows: [[CSVField]]) throws -> Data {
        func quote(_ value: String) -> String {
            if value.contains(",") || value.contains("\"") || value.contains("\n") || value.contains("\r") {
                return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            }
            return value
        }
        var output = headers.map(quote).joined(separator: ",") + "\r\n"
        for row in rows {
            try Task.checkCancellation()
            let fields = row.map { field -> String in
                switch field {
                case .value(let value): return quote(value)
                case .text(let text):
                    let leading = text.trimmingCharacters(in: .whitespacesAndNewlines).first
                    let unsafe = leading.map { "=+-@".contains($0) } == true || text.first == "\t" || text.first == "\r" || text.first == "\n"
                    return quote((unsafe ? "'" : "") + text)
                }
            }
            output += fields.joined(separator: ",") + "\r\n"
        }
        return Data(output.utf8)
    }
}
