# SQL Server → Snowflake Migration

Migrated `usp_ProcessBudgetConsolidation` - a 510-line stored procedure with cursors, hierarchy rollups, and intercompany eliminations.

## Quick Start

### 1. Clone and open in Claude Code

```bash
git clone https://github.com/rkethamakka/snowflake_sql_migration_test.git
cd snowflake_sql_migration_test
claude
```

Skills are bundled in `.claude/skills/` and load automatically.

### 2. Run the migration workflow

```
Read .claude/skills/sql-migration-planner/SKILL.md and analyze src/StoredProcedures/usp_ProcessBudgetConsolidation.sql

Deploy to Snowflake following .claude/skills/sql-migration/SKILL.md

Generate test data using .claude/skills/test-data-generator/SKILL.md

Verify migration using .claude/skills/sql-migration-verify/SKILL.md
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
.claude/skills/                                          ← Migration skills (auto-loaded)
snowflake/procedures/usp_ProcessBudgetConsolidation.sql  ← Main deliverable
test/results/QUICK_VERIFICATION.md                       ← Test results
```

## Prerequisites

- Snowflake CLI (`snow`) installed and configured
- Docker with SQL Server container (for verification)
- Claude Code

## AI Usage

Used Claude for schema translation, pattern identification, and test generation. Human review required for complex business logic and bug fixes.
