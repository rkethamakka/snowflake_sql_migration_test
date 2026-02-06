# SQL Server → Snowflake Migration

Migrated `usp_ProcessBudgetConsolidation` - a 510-line stored procedure with cursors, hierarchy rollups, and intercompany eliminations.

## Quick Start

### 1. Load the skills into Claude Code

```bash
git clone https://github.com/rkethamakka/openclaw-skills.git
```

Then tell Claude: "Read the SKILL.md files in openclaw-skills/sql-migration*"

### 2. Run skills in order

```
"Analyze src/StoredProcedures/usp_ProcessBudgetConsolidation.sql and create a migration plan"
→ Uses sql-migration-planner

"Deploy the migration to Snowflake"
→ Uses sql-migration

"Generate test data for both SQL Server and Snowflake"
→ Uses test-data-generator

"Verify the migration with side-by-side comparison"
→ Uses sql-migration-verify
```

### 3. View results

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
