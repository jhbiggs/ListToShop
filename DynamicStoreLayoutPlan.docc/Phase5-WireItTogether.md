# Phase 5 — Wire It Together

## Steps

1. `StoreService.swift` — networking layer (`URLSession`) for the REST API
2. Update `GroceryListViewModel` — add `sortByStore(_ storeId: UUID)`
3. MCP tool queries the same Postgres DB for community-maintained layouts

## Implementation Order

1. Provision EC2 + RDS on AWS
2. Build Node.js server with REST + MCP tool, deploy to EC2
3. Build `StoreService.swift` networking layer
4. Build `StoreLayoutEditor` drag-drop view
5. Add "Sort by store" button to main grocery list view
6. Test end-to-end
