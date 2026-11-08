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

    @Environment(\.scenePhase) private var scenePhase

    private let appGroupID = "group.com.mindframe.ListToShop"
    private let sharedKey = "SharedRecipeURL"

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Handle URLs from Share Extension via custom scheme:
                    // listtoshop://add?url=<encoded-recipe-url>
                    guard url.scheme == "listtoshop",
                          url.host == "add",
                          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                          let recipeURL = components.queryItems?.first(where: { $0.name == "url" })?.value else {
                        return
                    }
                    NotificationCenter.default.post(
                        name: .addRecipeFromShareExtension,
                        object: nil,
                        userInfo: ["url": recipeURL]
                    )
                }
                .onChange(of: scenePhase) { _, newPhase in
                    if newPhase == .active {
                        checkForSharedURL()
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    private func checkForSharedURL() {
        guard let sharedDefaults = UserDefaults(suiteName: appGroupID),
              let urlString = sharedDefaults.string(forKey: sharedKey) else {
            return
        }
        // Clear it so we don't process it again
        sharedDefaults.removeObject(forKey: sharedKey)
        sharedDefaults.synchronize()

        NotificationCenter.default.post(
            name: .addRecipeFromShareExtension,
            object: nil,
            userInfo: ["url": urlString]
        )
    }
}

extension Notification.Name {
    static let addRecipeFromShareExtension = Notification.Name("addRecipeFromShareExtension")
}
