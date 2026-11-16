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
        #if DEBUG
        // UI tests pass -uiTestingDemo to get sample data in memory. Real data is never touched.
        let demo = ProcessInfo.processInfo.arguments.contains("-uiTestingDemo")
        let container = demo
            ? try! ModelContainer(for: Recipe.self, GroceryItem.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            : try! ModelContainer(for: Recipe.self, GroceryItem.self)
        if demo { DemoData.seed(into: container.mainContext) }
        #else
        let container = try! ModelContainer(for: Recipe.self, GroceryItem.self)
        #endif
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

#if DEBUG
/// Sample recipes and grocery items, used only by UI tests and screenshots.
enum DemoData {
    static func seed(into context: ModelContext) {
        let enchiladas = Recipe(
            url: "https://www.allrecipes.com/recipe/8691/chicken-enchiladas-i/",
            title: "Chicken Enchiladas",
            rawIngredients: [
                "4 skinless, boneless chicken breast halves",
                "1 onion, chopped",
                "1 (15 ounce) can tomato sauce",
                "8 (10 inch) flour tortillas",
            ],
            steps: [
                "Preheat the oven to 350 degrees F and grease a 9x13 baking dish.",
                "Cook the chicken until no longer pink, then shred it.",
                "Fill each tortilla with chicken and onion, roll, and place seam side down in the dish.",
            ],
            totalMinutes: 50
        )
        enchiladas.lineItemKeys = ["chicken breast", "onion", "tomato sauce", "flour tortilla"]

        let rabe = Recipe(
            url: "https://www.allrecipes.com/recipe/0000/orecchiette-with-broccoli-rabe/",
            title: "Orecchiette with Broccoli Rabe",
            rawIngredients: [
                "8 oz orecchiette",
                "1 1/2 pounds broccoli rabe, stems cleaned, cut into 1-inch pieces",
                "2 cloves garlic, minced",
                "1/4 cup olive oil",
            ],
            steps: [
                "Boil the orecchiette in salted water until al dente.",
                "Blanch the broccoli rabe for 2 minutes, then drain.",
                "Warm the olive oil with the garlic and toss everything together.",
            ],
            totalMinutes: 30
        )
        rabe.lineItemKeys = ["orecchiette", "broccoli rabe", "garlic", "olive oil"]

        context.insert(enchiladas)
        context.insert(rabe)

        let groceries = [
            GroceryItem(name: "Broccoli rabe", quantity: "1 1/2 pounds", category: .produce, recipes: [rabe]),
            GroceryItem(name: "Garlic", quantity: "2 cloves", category: .produce, recipes: [rabe]),
            GroceryItem(name: "Onion", quantity: "1", category: .produce, recipes: [enchiladas]),
            GroceryItem(name: "Chicken breast", quantity: "4", category: .meat, recipes: [enchiladas]),
            GroceryItem(name: "Tomato sauce", quantity: "1 (15 ounce) can", category: .canned, recipes: [enchiladas]),
            GroceryItem(name: "Flour tortilla", quantity: "8 (10 inch)", category: .bakery, recipes: [enchiladas]),
            GroceryItem(name: "Orecchiette", quantity: "8 oz", category: .bakery, recipes: [rabe]),
            GroceryItem(name: "Olive oil", quantity: "1/4 cup", category: .condiments, isChecked: true, recipes: [rabe]),
            GroceryItem(name: "Paper towels", quantity: "", category: .other),
        ]
        groceries.forEach { context.insert($0) }
        try? context.save()
    }
}
#endif

extension Notification.Name {
    static let addRecipeFromShareExtension = Notification.Name("addRecipeFromShareExtension")
}
