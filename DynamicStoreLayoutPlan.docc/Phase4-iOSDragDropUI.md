# Phase 4 — iOS Drag-Drop UI

New file `StoreLayoutEditor.swift`.

## Features

1. **Store picker** — search by name + location, or create new
2. **Drag-to-reorder list** — `List` with `onMove`
3. **Save** — `PUT /stores/:id/aisle-order`
4. **Sort grocery list** — fetch aisle order, sort items client-side

## Example

```swift
struct StoreLayoutEditor: View {
    @State private var aisleOrder: [AisleCategory] = AisleCategory.allCases
    @State private var selectedStore: StoreRecord?

    var body: some View {
        List {
            ForEach(aisleOrder) { category in
                Text(category.displayName)
            }
            .onMove { from, to in
                aisleOrder.move(fromOffsets: from, toOffset: to)
            }
        }
        .toolbar { EditButton() }
        .onChange(of: aisleOrder) { saveToServer() }
    }
}
```
