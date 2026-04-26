//
//  OrganizeByAisleIntent.swift
//  Roseburg
//
//  Created by Justin Biggs on 4/19/26.
//

import AppIntents
import Foundation

/// Groups the current grocery list by store aisle, ordered for an efficient shopping route.
/// Apple Intelligence / Siri can invoke this to present an organized shopping list.
struct OrganizeByAisleIntent: AppIntent {

    static var title: LocalizedStringResource = "Organize Groceries by Aisle"

    static var description = IntentDescription(
        "Groups your grocery list items by their typical Aldi store aisle, ordered for an efficient shopping route.",
        categoryName: "Grocery List"
    )

    @Parameter(title: "Store Name", default: "Aldi")
    var storeName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Organize groceries for \(\.$storeName)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let grouped = try GroceryDataStore.shared.fetchItemsByCategory()

        if grouped.isEmpty {
            return .result(value: "Your grocery list is empty. Add a recipe first!")
        }

        // Build a formatted, aisle-ordered shopping list
        var output = "🛒 Shopping List for \(storeName)\n"
        output += String(repeating: "─", count: 30) + "\n\n"

        // Aldi typical store order: produce → bakery → dairy → meat → frozen → canned → spices → condiments → snacks → beverages → other
        let aisleOrder: [AisleCategory] = [
            .produce, .bakery, .dairy, .meat, .frozen,
            .canned, .spices, .condiments, .snacks, .beverages, .other
        ]

        for category in aisleOrder {
            guard let section = grouped.first(where: { $0.category == category }) else { continue }
            output += "📍 \(category.displayName)\n"
            for item in section.items {
                let qty = item.quantity.isEmpty ? "" : " (\(item.quantity))"
                output += "  ☐ \(item.name)\(qty)\n"
            }
            output += "\n"
        }

        return .result(value: output)
    }
}

/// Shows the full grocery list with categories.
struct ShowGroceryListIntent: AppIntent {

    static var title: LocalizedStringResource = "Show Grocery List"

    static var description = IntentDescription(
        "Shows all items on your grocery list, organized by category.",
        categoryName: "Grocery List"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[GroceryItemEntity]> {
        let items = try GroceryDataStore.shared.fetchUncheckedItems()
        let entities = items.map { GroceryItemEntity(from: $0) }
        return .result(value: entities)
    }
}
