//
//  RoseburgShortcuts.swift
//  Roseburg
//
//  Created by Justin Biggs on 4/19/26.
//

import AppIntents

/// Registers Roseburg's intents as Siri Shortcuts phrases so they appear
/// automatically in the Shortcuts app and respond to voice commands.
struct RoseburgShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OrganizeByAisleIntent(),
            phrases: [
                "Organize my groceries in \(.applicationName)",
                "Sort my grocery list by aisle in \(.applicationName)",
                "Show my \(.applicationName) shopping list by aisle",
            ],
            shortTitle: "Organize by Aisle",
            systemImageName: "cart.fill"
        )

        AppShortcut(
            intent: ShowGroceryListIntent(),
            phrases: [
                "Show my grocery list in \(.applicationName)",
                "What's on my \(.applicationName) list",
            ],
            shortTitle: "Show Grocery List",
            systemImageName: "list.bullet"
        )
    }
}
