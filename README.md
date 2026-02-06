# SQL Server → Snowflake Migration

Migrated `usp_ProcessBudgetConsolidation` - a 510-line stored procedure with cursors, hierarchy rollups, and intercompany eliminations.

## Quick Start (OpenClaw Skills)

Run these skills in order:

```
1. sql-migration-planner  → Analyze source, generate migration plan
2. sql-migration          → Deploy tables, functions, views, procedures to Snowflake
3. test-data-generator    → Generate matching test data for both systems
4. sql-migration-verify   → Run side-by-side comparison, generate report
```

**Results:** [test/results/QUICK_VERIFICATION.md](test/results/QUICK_VERIFICATION.md)

## What Changed

| SQL Server | Snowflake |
|------------|-----------|
| CURSOR + WHILE loops | Recursive CTEs + temp tables |
| Table variables | CREATE TEMPORARY TABLE |
| OUTPUT parameters | RETURNS VARIANT (JSON) |
| HIERARCHYID | Closure table pattern |
| 510 lines | 191 lines |

## Key Fix

Found an order-of-operations bug during verification: elimination logic was running AFTER rollup instead of BEFORE. Fixed in Snowflake version.

## Files

```
snowflake/procedures/usp_ProcessBudgetConsolidation.sql  ← Main deliverable
test/results/QUICK_VERIFICATION.md                       ← Test results
```

## AI Usage

Used Claude for schema translation, pattern identification, and test generation. Human review required for complex business logic and bug fixes.
