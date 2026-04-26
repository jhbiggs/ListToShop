# Phase 2 — Database Schema

Define the PostgreSQL schema for store layouts.

## SQL

```sql
CREATE TABLE stores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  city TEXT NOT NULL,
  state TEXT NOT NULL,
  aisle_order TEXT[] NOT NULL DEFAULT ARRAY[
    'produce','dairy','meat','bakery','frozen',
    'canned','spices','beverages','snacks','condiments','other'
  ],
  updated_by TEXT,
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(name, city, state)
);
```
