//
//  Recipe.swift
//  Roseburg
//
//  Created by Justin Biggs on 3/26/26.
//

import Foundation
import SwiftData

@Model
final class Recipe {
    var url: String
    var title: String
    var rawIngredients: [String]
    var steps: [String]
    var dateAdded: Date
    /// Total cooking time in minutes, or nil when the recipe page didn't list one.
    var totalMinutes: Int? = nil
    /// True when the time came from the on-device model rather than the recipe page.
    var timeIsEstimated: Bool = false

    /// Ingredients this recipe needs. Deleting a recipe does not delete shared items;
    /// the view model removes items that no longer belong to any recipe.
    var items: [GroceryItem] = []

    init(url: String, title: String, rawIngredients: [String], steps: [String] = [], dateAdded: Date = .now, totalMinutes: Int? = nil) {
        self.url = url
        self.title = title
        self.rawIngredients = rawIngredients
        self.steps = steps
        self.dateAdded = dateAdded
        self.totalMinutes = totalMinutes
    }
}
