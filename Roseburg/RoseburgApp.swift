//
//  RoseburgApp.swift
//  Roseburg
//
//  Created by Justin Biggs on 3/15/26.
//

import SwiftUI
import SwiftData

@main
struct RoseburgApp: App {

    let modelContainer: ModelContainer

    init() {
        let container = try! ModelContainer(for: Recipe.self, GroceryItem.self)
        self.modelContainer = container
        GroceryDataStore.shared.configure(with: container)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
