//
//  QuantityMerger.swift
//  Roseburg
//
//  Created by Justin Biggs on 4/25/26.
//

import Foundation

/// Parses, normalizes, and merges ingredient quantities with unit conversion.
struct QuantityMerger {

    // MARK: - Types

    struct ParsedQuantity {
        var amount: Double
        var unit: String  // normalized unit name
        var raw: String   // original string if unparseable
    }

    // MARK: - Unit Conversion Tables

    /// All units normalized to teaspoons (for volume) or ounces (for weight).
    private static let volumeToTeaspoons: [String: Double] = [
        "tsp": 1,
        "teaspoon": 1,
        "teaspoons": 1,
        "tbsp": 3,
        "tablespoon": 3,
        "tablespoons": 3,
        "fl oz": 6,
        "fluid ounce": 6,
        "fluid ounces": 6,
        "cup": 48,
        "cups": 48,
        "pint": 96,
        "pints": 96,
        "quart": 192,
        "quarts": 192,
        "gallon": 768,
        "gallons": 768,
        "liter": 202.884,
        "liters": 202.884,
        "ml": 0.202884,
        "milliliter": 0.202884,
        "milliliters": 0.202884,
    ]

    private static let weightToOunces: [String: Double] = [
        "oz": 1,
        "ounce": 1,
        "ounces": 1,
        "lb": 16,
        "lbs": 16,
        "pound": 16,
        "pounds": 16,
        "g": 0.035274,
        "gram": 0.035274,
        "grams": 0.035274,
        "kg": 35.274,
        "kilogram": 35.274,
        "kilograms": 35.274,
    ]

    /// Countable units that just add up directly.
    private static let countUnits: Set<String> = [
        "", "piece", "pieces", "clove", "cloves",
        "slice", "slices", "sprig", "sprigs",
        "pinch", "pinches", "dash", "dashes",
        "can", "cans", "bag", "bags",
        "bunch", "bunches", "head", "heads",
        "stalk", "stalks", "ear", "ears",
        "large", "medium", "small",
    ]

    // MARK: - Best Display Unit

    /// Pick the most human-friendly unit for display.
    private static let volumeBreakpoints: [(threshold: Double, unit: String, divisor: Double)] = [
        (768, "gallon", 768),
        (192, "quart", 192),
        (96, "pint", 96),
        (48, "cup", 48),
        (3, "tablespoon", 3),
        (0, "teaspoon", 1),
    ]

    private static let weightBreakpoints: [(threshold: Double, unit: String, divisor: Double)] = [
        (16, "lb", 16),
        (0, "oz", 1),
    ]

    // MARK: - Public API

    /// Merges an array of quantity strings for the same ingredient into one display string.
    /// e.g. ["2 teaspoons", "1 tablespoon"] → "5 teaspoons" or "1 tablespoon + 2 teaspoons"
    static func merge(_ quantities: [String]) -> String {
        let parsed = quantities.map { parse($0) }

        // Group by unit system
        var volumeTsp: Double = 0
        var weightOz: Double = 0
        var counts: [String: Double] = [:]  // unit → total
        var unknowns: [String] = []

        for p in parsed {
            if let factor = volumeToTeaspoons[p.unit] {
                volumeTsp += p.amount * factor
            } else if let factor = weightToOunces[p.unit] {
                weightOz += p.amount * factor
            } else if countUnits.contains(p.unit) {
                counts[p.unit, default: 0] += p.amount
            } else {
                unknowns.append(p.raw)
            }
        }

        var parts: [String] = []

        if volumeTsp > 0 {
            parts.append(formatVolume(volumeTsp))
        }
        if weightOz > 0 {
            parts.append(formatWeight(weightOz))
        }
        for (unit, amount) in counts.sorted(by: { $0.key < $1.key }) {
            parts.append(formatCount(amount, unit: unit))
        }
        parts.append(contentsOf: unknowns)

        return parts.isEmpty ? quantities.joined(separator: " + ") : parts.joined(separator: " + ")
    }

    // MARK: - Parsing

    /// Parses "2 tablespoons" → ParsedQuantity(amount: 2, unit: "tablespoons")
    /// Handles fractions like "1/2", "½", mixed numbers like "1 1/2"
    static func parse(_ raw: String) -> ParsedQuantity {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return ParsedQuantity(amount: 0, unit: "", raw: raw)
        }

        // Normalize unicode fractions
        var normalized = trimmed
            .replacingOccurrences(of: "½", with: "1/2")
            .replacingOccurrences(of: "⅓", with: "1/3")
            .replacingOccurrences(of: "⅔", with: "2/3")
            .replacingOccurrences(of: "¼", with: "1/4")
            .replacingOccurrences(of: "¾", with: "3/4")
            .replacingOccurrences(of: "⅛", with: "1/8")

        // Pattern: optional number, optional fraction, then unit
        let pattern = #"^(\d+)?\s*(\d+/\d+)?\s*(.*)$"#
        guard let match = normalized.range(of: pattern, options: .regularExpression) else {
            return ParsedQuantity(amount: 1, unit: normalized.lowercased(), raw: raw)
        }

        let regex = try! NSRegularExpression(pattern: pattern)
        let nsRange = NSRange(normalized.startIndex..., in: normalized)
        guard let result = regex.firstMatch(in: normalized, range: nsRange) else {
            return ParsedQuantity(amount: 1, unit: normalized.lowercased(), raw: raw)
        }

        var amount: Double = 0

        // Whole number part
        if let wholeRange = Range(result.range(at: 1), in: normalized),
           let whole = Double(normalized[wholeRange]) {
            amount += whole
        }

        // Fraction part
        if let fracRange = Range(result.range(at: 2), in: normalized) {
            let frac = String(normalized[fracRange])
            let parts = frac.split(separator: "/")
            if parts.count == 2,
               let num = Double(parts[0]),
               let den = Double(parts[1]), den != 0 {
                amount += num / den
            }
        }

        // Unit part
        var unit = ""
        if let unitRange = Range(result.range(at: 3), in: normalized) {
            unit = normalized[unitRange]
                .trimmingCharacters(in: .whitespaces)
                .lowercased()
                // Strip trailing period (e.g. "tbsp.")
                .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        }

        if amount == 0 && !unit.isEmpty {
            amount = 1
        }

        return ParsedQuantity(amount: amount, unit: unit, raw: raw)
    }

    // MARK: - Formatting

    private static func formatVolume(_ teaspoons: Double) -> String {
        for bp in volumeBreakpoints {
            if teaspoons >= bp.threshold || bp.threshold == 0 {
                let value = teaspoons / bp.divisor
                return "\(formatNumber(value)) \(pluralize(bp.unit, value))"
            }
        }
        return "\(formatNumber(teaspoons)) teaspoons"
    }

    private static func formatWeight(_ ounces: Double) -> String {
        for bp in weightBreakpoints {
            if ounces >= bp.threshold || bp.threshold == 0 {
                let value = ounces / bp.divisor
                return "\(formatNumber(value)) \(pluralize(bp.unit, value))"
            }
        }
        return "\(formatNumber(ounces)) oz"
    }

    private static func formatCount(_ amount: Double, unit: String) -> String {
        if unit.isEmpty {
            return formatNumber(amount)
        }
        return "\(formatNumber(amount)) \(pluralize(unit, amount))"
    }

    private static func formatNumber(_ value: Double) -> String {
        // Show as fraction if close to common fractions
        let fractions: [(Double, String)] = [
            (0.125, "⅛"), (0.25, "¼"), (0.333, "⅓"),
            (0.5, "½"), (0.667, "⅔"), (0.75, "¾"),
        ]

        let whole = Int(value)
        let remainder = value - Double(whole)

        if remainder < 0.05 {
            return "\(whole)"
        }

        for (frac, symbol) in fractions {
            if abs(remainder - frac) < 0.05 {
                return whole > 0 ? "\(whole)\(symbol)" : symbol
            }
        }

        // Fall back to decimal
        if value == value.rounded() {
            return "\(Int(value))"
        }
        return String(format: "%.1f", value)
    }

    private static func pluralize(_ unit: String, _ amount: Double) -> String {
        guard amount != 1 else { return unit }
        // Already plural
        if unit.hasSuffix("s") { return unit }
        // Special cases
        switch unit {
        case "lb": return "lbs"
        case "oz": return "oz"
        case "bunch": return "bunches"
        case "pinch": return "pinches"
        case "dash": return "dashes"
        default: return unit + "s"
        }
    }
}
