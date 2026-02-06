---
name: sql-migration-planner
description: Analyze a SQL Server stored procedure and produce a complete migration plan
---

# Skill: sql-migration-planner

Analyze a SQL Server stored procedure and produce a complete migration plan.

## Prerequisites

**Find your snow CLI path:**
```bash
which snow || find /usr -name "snow" 2>/dev/null || find ~/Library -name "snow" 2>/dev/null
```

If not found, install: `pip install snowflake-cli-labs`

---

## When to Use
- User wants to migrate a stored procedure
- User asks "what do I need to migrate for X?"
- User says "plan migration for usp_..."

## Input
Procedure name (e.g., `usp_ProcessBudgetConsolidation`)

## Output
Structured migration plan saved to: `migration-plans/<procedure_name>.md`

---

## Workflow

### Step 1: Read Procedure Source
```bash
cat src/StoredProcedures/<procedure_name>.sql
```

Look for dependency header comment:
```sql
/*
    Dependencies: 
        - Tables: X, Y, Z
        - Views: vw_X
        - Functions: fn_X, tvf_X
        - Types: XTableType
*/
```

### Step 2: Check Snowflake State
```bash
snow sql -q "SHOW TABLES IN FINANCIAL_PLANNING.PLANNING"
snow sql -q "SHOW USER FUNCTIONS IN FINANCIAL_PLANNING.PLANNING"
snow sql -q "SHOW VIEWS IN FINANCIAL_PLANNING.PLANNING"
snow sql -q "SHOW PROCEDURES IN FINANCIAL_PLANNING.PLANNING"
```

### Step 3: Check SQL Server State
```bash
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'TestPass123!' -C \
  -d FINANCIAL_PLANNING -Q "
  SELECT name, type_desc FROM sys.objects 
  WHERE schema_id = SCHEMA_ID('Planning')
  ORDER BY type_desc, name"
```

### Step 4: Analyze Complexity

Count and categorize:
- **Lines of code**
- **Cursors** (FAST_FORWARD, SCROLL, KEYSET, etc.)
- **Dynamic SQL** (EXEC, sp_executesql)
- **Table variables** with indexes
- **OUTPUT clauses**
- **Transaction handling** (BEGIN TRY/CATCH, SAVE TRANSACTION)
- **XML processing**

Complexity ratings:
- **SIMPLE:** <100 lines, no cursors, no dynamic SQL
- **MODERATE:** 100-300 lines, 1-2 cursors, simple dynamic SQL
- **COMPLEX:** >300 lines, multiple cursors, complex dynamic SQL

### Step 5: Identify Patterns

Common patterns requiring special handling:
1. **Cursor-based hierarchy traversal** → Closure table + recursive CTE
2. **SCROLL cursor for matching** → Self-join pattern
3. **Table variables with OUTPUT** → Temp tables
4. **Dynamic SQL with table types** → JavaScript procedure

### Step 6: Generate Plan

Write `migration-plans/<procedure_name>.md`:

```markdown
# Migration Plan: <procedure_name>

## Dependencies (in order)

### Tables
| Name | Status | Notes |
|------|--------|-------|
| Table1 | TO_MIGRATE | |

### Functions
| Name | Status | Notes |
|------|--------|-------|

### Views
| Name | Status | Notes |
|------|--------|-------|

### Procedure
| Name | Complexity | Approach |
|------|------------|----------|
| usp_X | COMPLEX | JavaScript |

## Complexity Analysis

- Lines: X
- Cursors: N (types)
- Dynamic SQL: Yes/No
- Recommended approach: SQL Scripting / JavaScript

## Patterns Detected

1. **Pattern Name** (lines X-Y)
   - Description
   - Recommended fix

## Estimated Effort

- Dependencies: X hours
- Procedure: X hours
- Testing: X hours
- **Total:** X hours
```

---

## Example Output

```
Migration Plan: usp_ProcessBudgetConsolidation

Dependencies:
  Tables (6): BudgetHeader, BudgetLineItem, GLAccount, CostCenter, FiscalPeriod, ConsolidationJournal
  Views (1): vw_BudgetConsolidationSummary
  Functions (2): fn_GetHierarchyPath, tvf_ExplodeCostCenterHierarchy

Complexity: COMPLEX (510 lines, 2 cursors, dynamic SQL)
Approach: JavaScript stored procedure

Patterns:
  1. Bottom-up hierarchy cursor → Closure table + recursive CTE
  2. SCROLL cursor for IC matching → Self-join pattern

Estimated: 25-35 hours
```
