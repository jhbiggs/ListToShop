# Phase 3 — MCP Server (Node.js on EC2)

Two interfaces: MCP stdio tool and REST API.

## MCP Tool

- `sort_grocery_list_by_store` — AI clients call this to sort a grocery list by a store's aisle order

## REST Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/stores?name=&city=&state=` | Search/list stores |
| GET | `/stores/:id` | Get one layout |
| PUT | `/stores/:id/aisle-order` | Update aisle order |
| POST | `/stores` | Create new store layout |
