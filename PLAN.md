# Roseburg — Recipe-to-Grocery-List App

Paste recipe URLs → extract ingredients → categorize by grocery aisle using on-device AI → persist across launches.

---

## Step 1: Update Project Settings for iOS 26

**What:** Change the deployment target and entitlements so the app can use Foundation Models and fetch web pages.

**In Xcode:**
- Select the **Roseburg** project in the navigator.
- Under **General → Minimum Deployments**, change iOS to **26.0**.
- Remove **macOS** from Supported Destinations (simplify to iOS-only).
- Open `Roseburg/Roseburg.entitlements` and add the key:
  - `com.apple.security.network.client` → `YES`
  (This allows the app to make outbound network requests to fetch recipe pages.)

**Files changed:**
- `Roseburg.entitlements`
- `project.pbxproj` (via Xcode UI)

---

## Step 2: Add SwiftSoup Package

**What:** Add the SwiftSoup HTML-parsing library so the app can read recipe web pages.

**In Xcode:**
- Go to **File → Add Package Dependencies…**
- Enter the URL: `https://github.com/scinfu/SwiftSoup`
- Choose **Up to Next Major Version** from `2.7.0`.
- Add the `SwiftSoup` library to the **Roseburg** target.

**Why:** Recipe websites embed structured data (JSON-LD) in their HTML. SwiftSoup lets us parse that HTML and pull out the ingredient list reliably.

---

## Step 3: Create Data Models with SwiftData

**What:** Define the core data types the app works with. SwiftData's `@Model` macro handles saving them to disk automatically.

**Files to create:**

### `Roseburg/Models/Recipe.swift`
- `@Model class Recipe` with properties:
  - `url: String` — the pasted recipe link
  - `title: String` — recipe name (parsed from the page)
  - `rawIngredients: [String]` — ingredient strings as extracted from the page
  - `dateAdded: Date`
- Relationship: one Recipe has many GroceryItems.

### `Roseburg/Models/GroceryItem.swift`
- `@Model class GroceryItem` with properties:
  - `name: String` — e.g. "chicken breast"
  - `quantity: String` — e.g. "2 lbs"
  - `category: AisleCategory` — which aisle it belongs to
  - `isChecked: Bool` — for checking items off the list
- `enum AisleCategory: String, Codable, CaseIterable` with cases:
  - `produce`, `dairy`, `meat`, `bakery`, `frozen`, `canned`, `spices`, `beverages`, `snacks`, `condiments`, `other`
- Relationship: each GroceryItem belongs to one Recipe.

---

## Step 4: Create Recipe-Fetching Service

**What:** A service that downloads a recipe web page and extracts the list of ingredients.

**File to create:** `Roseburg/Services/RecipeFetcher.swift`

**How it works:**
1. Accept a URL string.
2. Use `URLSession.shared.data(from:)` to download the HTML.
3. Use SwiftSoup to parse the HTML.
4. Look for a `<script type="application/ld+json">` tag containing JSON-LD with `@type: "Recipe"`.
5. Decode the JSON and extract the `recipeIngredient` array.
6. Return `(title: String, ingredients: [String])`.

**Fallback:** If no JSON-LD is found, scan for `<li>` elements inside a container with class/id containing "ingredient".

---

## Step 5: Create Ingredient Categorizer Using Foundation Models

**What:** Use Apple's on-device LLM (Large Language Model) to intelligently assign each ingredient to a grocery aisle category.

**File to create:** `Roseburg/Services/IngredientCategorizer.swift`

**How it works:**
1. `import FoundationModels`
2. Create a `LanguageModelSession`.
3. Define a `@Generable` struct that maps ingredient names to `AisleCategory` values.
4. Send a prompt like: *"Categorize each ingredient into one of these grocery aisles: produce, dairy, meat, bakery, frozen, canned, spices, beverages, snacks, condiments, other."*
5. The model returns structured output that maps directly to your Swift types.

**Key concept — `@Generable`:** This macro (part of Foundation Models) tells the on-device LLM to return structured Swift data instead of free-form text. You define the output shape as a Swift struct, and the framework handles the rest.

**Important:** Requires a physical device running iOS 26, or the iOS 26 Simulator on Apple Silicon with macOS 26.

---

## Step 6: Create the ViewModel

**What:** An `@Observable` class that ties the services together and manages app state.

**File to create:** `Roseburg/ViewModels/GroceryListViewModel.swift`

**Properties:**
- `recipes: [Recipe]` — all saved recipes (fetched from SwiftData)
- `groceryItems: [GroceryItem]` — all items across all recipes
- `isLoading: Bool`
- `errorMessage: String?`

**Methods:**
- `addRecipe(url: String)` — validates URL → calls `RecipeFetcher` → calls `IngredientCategorizer` → saves `Recipe` and `GroceryItem`s to SwiftData.
- `deleteRecipe(_ recipe: Recipe)` — removes a recipe and its items.
- `toggleItem(_ item: GroceryItem)` — checks/unchecks an item.
- `itemsByCategory` — computed property that groups items by `AisleCategory` for the UI.

---

## Step 7: Build the UI

**What:** Replace the placeholder content with the grocery list interface.

### `Roseburg/ContentView.swift`
Two-section layout:
1. **Top: URL input** — a `TextField` ("Paste a recipe URL…") with an "Add" `Button`.
2. **Bottom: Grocery list** — a `List` with `Section` headers for each aisle category (Produce, Dairy, Meat, etc.). Each row shows the ingredient name, quantity, and a checkmark toggle. Swipe to delete.

### `Roseburg/RoseburgApp.swift`
- Add `.modelContainer(for: [Recipe.self, GroceryItem.self])` to the `WindowGroup` so SwiftData knows which models to persist.

---

## Target Folder Structure

```
Roseburg/
  RoseburgApp.swift
  ContentView.swift
  Roseburg.entitlements
  Models/
    Recipe.swift
    GroceryItem.swift
  Services/
    RecipeFetcher.swift
    IngredientCategorizer.swift
  ViewModels/
    GroceryListViewModel.swift
  Assets.xcassets/
  Preview Content/
```

---

## Important Notes

- **Foundation Models** requires **iOS 26** on a physical Apple device (or the iOS 26 Simulator on Apple Silicon + macOS 26). It will not work on older OS versions or Intel Macs.
- **SwiftData** replaces Core Data with a simpler `@Model` macro. Data persists to disk automatically between app launches — no manual save calls needed.
- **SwiftSoup** is the only external dependency. Everything else uses Apple frameworks.
- **Each step builds on the previous one** — complete them in order.
- After finishing all 7 steps you will have a working MVP. Future enhancements (multiple store profiles, barcode scanning, sharing lists) can be added later.
