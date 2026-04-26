# ``DynamicStoreLayoutPlan``

A shared store layout MCP server backed by AWS EC2 and PostgreSQL, with an iOS drag-drop editor.

## Overview

```
┌──────────────┐       HTTPS        ┌──────────────────┐       ┌────────────┐
│  iOS App     │  ◄──────────────►  │  EC2 (MCP Server) │  ───► │ PostgreSQL │
│  (drag-drop) │   REST + stdio     │  Node.js          │       │ (RDS)      │
└──────────────┘                    └──────────────────┘       └────────────┘
```

## Topics

### Phases

- <doc:Phase1-AWSInfrastructure>
- <doc:Phase2-DatabaseSchema>
- <doc:Phase3-MCPServer>
- <doc:Phase4-iOSDragDropUI>
- <doc:Phase5-WireItTogether>
