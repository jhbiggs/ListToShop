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

    /// Ingredients this recipe needs. Deleting a recipe does not delete shared items;
    /// the view model removes items that no longer belong to any recipe.
    var items: [GroceryItem] = []

    init(url: String, title: String, rawIngredients: [String], steps: [String] = [], dateAdded: Date = .now) {
        self.url = url
        self.title = title
        self.rawIngredients = rawIngredients
        self.steps = steps
        self.dateAdded = dateAdded
    }
}
