import Foundation

nonisolated struct ProjectHourlyRate: Codable, Equatable, Sendable {
    let amount: Decimal
    let currency: String
    static var currencies: [String] { Locale.commonISOCurrencyCodes.sorted() }
    var isValid: Bool { !amount.isNaN && amount >= 0 && amount <= 1_000_000_000_000 && Self.currencies.contains(currency) }

    init(amount: Decimal, currency: String) { self.amount = amount; self.currency = currency }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        amount = try values.decode(Decimal.self, forKey: .amount)
        currency = try values.decode(String.self, forKey: .currency)
        guard isValid else { throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid project hourly rate")) }
    }
    private enum CodingKeys: String, CodingKey { case amount, currency }
    static func parse(_ text: String, currency: String, locale: Locale = .current) throws -> ProjectHourlyRate? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return nil }
        let parts = text.components(separatedBy: locale.decimalSeparator ?? ".")
        guard parts.count <= 2, text.unicodeScalars.contains(where: { CharacterSet.decimalDigits.contains($0) }),
              parts.allSatisfy({ $0.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) } }),
              let amount = try? Decimal(text, format: .number.locale(locale), lenient: false) else { throw ProjectHourlyRateError.invalid }
        let rate = ProjectHourlyRate(amount: amount, currency: currency)
        guard rate.isValid else { throw ProjectHourlyRateError.invalid }
        return rate
    }
    var editableAmount: String {
        var value = amount
        return NSDecimalString(&value, Locale.current)
    }
    static func formatted(_ amount: Decimal, currency: String) -> String {
        amount.formatted(.currency(code: currency))
    }
}

enum ProjectHourlyRateError: LocalizedError {
    case invalid
    var errorDescription: String? { "Enter an hourly rate from 0 to 1,000,000,000,000 and choose a currency, or leave the rate empty." }
}
