# SQL Server → Snowflake Migration

Migrated `usp_ProcessBudgetConsolidation` - a 510-line stored procedure with cursors, hierarchy rollups, and intercompany eliminations.

## Quick Start

### 1. Install skills as Claude Code plugins

```bash
git clone https://github.com/rkethamakka/openclaw-skills.git
# Add to Claude Code as plugins
```

### 2. Run skills in order

```bash
/sql-migration-planner src/StoredProcedures/usp_ProcessBudgetConsolidation.sql
/sql-migration deploy to Snowflake
/test-data-generator generate for both systems
/sql-migration-verify run side-by-side comparison
```

### 3. View results

[test/results/QUICK_VERIFICATION.md](test/results/QUICK_VERIFICATION.md)

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
