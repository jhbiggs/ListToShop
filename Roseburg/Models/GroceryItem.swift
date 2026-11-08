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

    /// Recipes that call for this item. Shared ingredients link to several recipes.
    @Relationship(inverse: \Recipe.items)
    var recipes: [Recipe] = []

    /// Items with no recipe links were added by hand and survive recipe deletion.
    var isManual: Bool { recipes.isEmpty }

    init(name: String, quantity: String, category: AisleCategory = .other, isChecked: Bool = false, recipes: [Recipe] = []) {
        self.name = name
        self.quantity = quantity
        self.category = category
        self.isChecked = isChecked
        self.recipes = recipes
    }
}
