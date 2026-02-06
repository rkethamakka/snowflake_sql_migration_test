# SQL Server → Snowflake Migration

Migrated `usp_ProcessBudgetConsolidation` - a 510-line stored procedure with cursors, hierarchy rollups, and intercompany eliminations.

## Quick Start

```bash
# Deploy to Snowflake
snow sql -f snowflake/tables/*.sql
snow sql -f snowflake/functions/*.sql
snow sql -f snowflake/views/*.sql
snow sql -f snowflake/procedures/usp_ProcessBudgetConsolidation.sql

# Load test data
snow sql -f test/data/snowflake/usp_ProcessBudgetConsolidation_setup.sql

# Run procedure
snow sql -q "CALL PLANNING.usp_ProcessBudgetConsolidation(1, 'FULL', TRUE, FALSE, NULL, 100, FALSE)"
```

## Verification

Run both systems and compare:

```bash
# SQL Server
docker exec sqlserver sqlcmd -d FINANCIAL_PLANNING -Q "
  EXEC Planning.usp_ProcessBudgetConsolidation @SourceBudgetHeaderID=1, ...
"

# Snowflake  
snow sql -q "CALL PLANNING.usp_ProcessBudgetConsolidation(1, 'FULL', TRUE, ...)"
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
