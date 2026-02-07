# SQL Server → Snowflake Migration

Migrating complex SQL Server stored procedures to Snowflake using reusable AI skills.

## Procedures

| Procedure | Lines | Status | Key Challenges |
|-----------|-------|--------|----------------|
| usp_ProcessBudgetConsolidation | 510 | ✅ Verified | Cursors, hierarchy rollups, IC eliminations |
| usp_ExecuteCostAllocation | 428 | ✅ Verified | GOTO, app locks, recursive CTE, WAITFOR |
| usp_BulkImportBudgetData | 519 | ⚠️ Deployed | BULK INSERT, TVP, dynamic SQL |
| usp_GenerateRollingForecast | 440 | ⚠️ Deployed | Dynamic PIVOT, statistical functions |
| usp_ReconcileIntercompanyBalances | 373 | ⚠️ Deployed | XML operations, HASHBYTES |
| usp_PerformFinancialClose | 521 | ⚠️ Deployed | Orchestration, nested proc calls |

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
./scripts/full-cleanup.sh

/sql-migration-planner usp_ProcessBudgetConsolidation

/sql-migration usp_ProcessBudgetConsolidation

/test-data-generator usp_ProcessBudgetConsolidation

/sql-migration-verify usp_ProcessBudgetConsolidation
```

### 3. View results

| Procedure | Verification |
|-----------|--------------|
| usp_ProcessBudgetConsolidation | [VERIFICATION_SUMMARY_usp_ProcessBudgetConsolidation.md](test/results/VERIFICATION_SUMMARY_usp_ProcessBudgetConsolidation.md) |
| usp_ExecuteCostAllocation | [VERIFICATION_SUMMARY_usp_ExecuteCostAllocation.md](test/results/VERIFICATION_SUMMARY_usp_ExecuteCostAllocation.md) |
| **All Procedures** | [VERIFICATION_SUMMARY_ALL_PROCEDURES.md](test/results/VERIFICATION_SUMMARY_ALL_PROCEDURES.md) |

## Performance Benchmark (One Stored Procedure)

Clean-slate execution times from scratch (usp_ProcessBudgetConsolidation):

### Claude Code

| Step | Duration | Description |
|------|----------|-------------|
| Cleanup | 13s | Drop Snowflake objects, kill Docker, clear files |
| Planner | 163s | Analyze 510-line procedure, create migration plan |
| Migration | 872s | Deploy 6 tables, 2 functions, 1 view, 1 procedure |
| Test Data | 1973s | Generate and load test data to both systems |
| Verification | 986s | Deploy to SQL Server, execute both, compare results |
| **Total** | **4007s (66 min)** | Full workflow from clean state to verified |

### OpenClaw

| Step | Duration | Description |
|------|----------|-------------|
| Cleanup | 30s | Drop Snowflake objects, kill Docker, clear files |
| Planner | <1s | Analyze 510-line procedure, create migration plan |
| Migration | 121s | Deploy 6 tables, 2 functions, 1 view, 1 procedure |
| Test Data | 10s | Generate and load test data (Snowflake only) |
| Verification | 8s | Execute procedure, verify results |
| **Total** | **~170s (2.8 min)** | Full workflow from clean state to verified |

### Comparison

| Metric | Claude Code | OpenClaw | Improvement |
|--------|-------------|----------|-------------|
| Total Time | 66 min | 2.8 min | **23x faster** |
| Planner | 163s | <1s | Instant |
| Migration | 872s | 121s | 7x faster |

**Why the difference?** These skills are portable and work on any AI framework. OpenClaw executes commands directly with minimal overhead. Claude Code includes more interactive reasoning time.

System: MacBook Pro M1, snow CLI, Docker SQL Server 2022

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
snowflake/procedures/                                    ← Migrated stored procedures
  usp_ProcessBudgetConsolidation.sql
  usp_ExecuteCostAllocation.sql
migration-plans/                                         ← Analysis and migration plans
  usp_ProcessBudgetConsolidation.md
  usp_ExecuteCostAllocation.md
test/results/                                            ← Verification reports (per procedure)
  VERIFICATION_SUMMARY_usp_ProcessBudgetConsolidation.md
  VERIFICATION_SUMMARY_usp_ExecuteCostAllocation.md
test/data/snowflake/                                     ← Test data (per procedure)
test/data/sqlserver/
scripts/sync-skills.sh                                   ← Sync skills to OpenClaw
```

## Skill Portability

These skills work on multiple AI frameworks:

| Framework | How to Use |
|-----------|------------|
| Claude Code | Skills auto-load from `.claude/skills/` |
| OpenClaw | Run `./scripts/sync-skills.sh to-openclaw` |
| Custom | Read SKILL.md files and follow the workflow |

## Prerequisites

- Snowflake CLI (`snow`) installed and configured
- Docker with SQL Server container (for verification)
- Claude Code or OpenClaw

## AI Usage

Used Claude for schema translation, pattern identification, and test generation. Human review required for complex business logic and bug fixes.
