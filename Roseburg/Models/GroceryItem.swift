//
//  GroceryItem.swift
//  Roseburg
//
//  Created by Justin Biggs on 3/26/26.
//

import Foundation
import SwiftData

enum AisleCategory: String, Codable, CaseIterable, Identifiable {
    case produce, dairy, meat, bakery, frozen, canned, spices, beverages, snacks, condiments, other

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }
}

@Model
final class GroceryItem {
    var name: String
    var quantity: String
    var category: AisleCategory
    var isChecked: Bool

    @Relationship(inverse: \Recipe.items)
    var recipe: Recipe?

    init(name: String, quantity: String, category: AisleCategory = .other, isChecked: Bool = false, recipe: Recipe? = nil) {
        self.name = name
        self.quantity = quantity
        self.category = category
        self.isChecked = isChecked
        self.recipe = recipe
    }
}
