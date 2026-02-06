# SQL Server → Snowflake Migration

This project includes custom skills for automated migration.

## Skills (in .claude/skills/)

| Skill | Purpose |
|-------|---------|
| sql-migration-planner | Analyze SQL Server source, create migration plan |
| sql-migration | Deploy tables, functions, views, procedures to Snowflake |
| test-data-generator | Generate matching test data for both systems |
| sql-migration-verify | Run side-by-side comparison, generate report |

## Prerequisites

- `snow` CLI installed and configured
- Docker with SQL Server container running
- Snowflake account with FINANCIAL_PLANNING database

## Workflow

1. Read the skill: `.claude/skills/sql-migration-planner/SKILL.md`
2. Analyze: `src/StoredProcedures/usp_ProcessBudgetConsolidation.sql`
3. Follow the skill instructions to deploy, test, and verify

## Results

See `test/results/QUICK_VERIFICATION.md` for verification report.
