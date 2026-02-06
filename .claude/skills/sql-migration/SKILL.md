---
name: sql-migration
description: Migrate SQL Server objects to Snowflake (Snowflake only, does not touch SQL Server)
---

# Skill: sql-migration

Migrate SQL Server objects to Snowflake. **Snowflake only** — does not touch SQL Server.

## Prerequisites

**Find your snow CLI path:**
```bash
which snow || find /usr -name "snow" 2>/dev/null || find ~/Library -name "snow" 2>/dev/null
```

If not found, install: `pip install snowflake-cli-labs`

**Docker:** SQL Server container must be running for verification (handled by sql-migration-verify)

---

## When to Use
- User wants to migrate a stored procedure and its dependencies
- User says "migrate", "convert", or "translate"

## Input
- **Option A:** Procedure name → runs planner first, then migrates
- **Option B:** Migration plan file → `migration-plans/<procedure>.md`

## Output
- Translated DDL saved to `snowflake/<Category>/`
- Deployed to Snowflake
- Status updated in migration plan

## Key Behavior
- **Check before migrate:** If object already exists in Snowflake, SKIP and report
- **No SQL Server:** This skill does NOT deploy to SQL Server (that's verify's job)
- **Idempotent:** Safe to run multiple times

---

## Workflow

### Step 0: Get Migration Plan
```
Check: Does migration-plans/<procedure>.md exist?
  NO  → Run sql-migration-planner skill first
  YES → Read the plan, get ordered dependency list
```

### Step 1: For Each Object in Migration Order

```
For object in [Tables → Functions → Views → Procedure]:
    1. Check if object exists in Snowflake
       EXISTS → Skip, print "Already exists: <object>"
       NOT EXISTS → Continue
    2. Read source from src/<Category>/<Object>.sql
    3. Translate to Snowflake syntax (apply rules)
    4. Save translated to snowflake/<Category>/<Object>.sql
    5. Deploy to Snowflake
    6. Verify deployment succeeded
```

### Step 2: Verify All Deployed
```bash
snow sql -q "SHOW TABLES IN FINANCIAL_PLANNING.PLANNING"
snow sql -q "SHOW USER FUNCTIONS IN FINANCIAL_PLANNING.PLANNING"
snow sql -q "SHOW VIEWS IN FINANCIAL_PLANNING.PLANNING"
snow sql -q "SHOW PROCEDURES IN FINANCIAL_PLANNING.PLANNING"
```

### Step 3: Update Plan
Add deployment status to migration-plans/<procedure>.md

---

## Translation Rules

### Data Types
| SQL Server | Snowflake |
|------------|-----------|
| DATETIME | TIMESTAMP_NTZ |
| DATETIME2 | TIMESTAMP_NTZ |
| MONEY | NUMBER(19,4) |
| SMALLMONEY | NUMBER(10,4) |
| BIT | BOOLEAN |
| UNIQUEIDENTIFIER | VARCHAR(36) |
| HIERARCHYID | VARCHAR(900) |
| XML | VARIANT |
| NVARCHAR(MAX) | VARCHAR(16777216) |
| VARCHAR(MAX) | VARCHAR(16777216) |
| IMAGE/VARBINARY(MAX) | BINARY |
| ROWVERSION | BINARY(8) |

### Functions
| SQL Server | Snowflake |
|------------|-----------|
| GETDATE() | CURRENT_TIMESTAMP() |
| GETUTCDATE() | CURRENT_TIMESTAMP() |
| NEWID() | UUID_STRING() |
| ISNULL(a,b) | COALESCE(a,b) or IFNULL(a,b) |
| LEN() | LENGTH() |
| CHARINDEX() | POSITION() or CHARINDEX() |
| DATEADD() | DATEADD() (same) |
| DATEDIFF() | DATEDIFF() (same) |

### DDL Changes
| SQL Server | Snowflake |
|------------|-----------|
| CREATE TABLE ... WITH (...) | Remove WITH clause |
| IDENTITY(1,1) | AUTOINCREMENT or IDENTITY |
| CONSTRAINT ... PRIMARY KEY CLUSTERED | PRIMARY KEY (remove CLUSTERED) |
| CONSTRAINT ... WITH (FILLFACTOR=...) | Remove WITH clause |
| ON [PRIMARY] | Remove |
| TEXTIMAGE_ON [PRIMARY] | Remove |
| CREATE INDEX ... ON ... INCLUDE (...) | Remove INCLUDE clause |

### Schema Handling
- SQL Server: `Planning.TableName`
- Snowflake: `FINANCIAL_PLANNING.PLANNING.TABLENAME` (uppercase)

### Stored Procedure Patterns

**Table Variables → Temp Tables:**
```sql
-- SQL Server
DECLARE @Results TABLE (ID INT, Value VARCHAR(100))

-- Snowflake
CREATE OR REPLACE TEMPORARY TABLE Results (ID INT, Value VARCHAR(100));
```

**OUTPUT Clause → Separate Query:**
```sql
-- SQL Server
INSERT INTO Target OUTPUT inserted.* INTO @Results SELECT * FROM Source

-- Snowflake
INSERT INTO Target SELECT * FROM Source;
-- Then query Target to get inserted rows
```

**CURSOR → Recursive CTE or JavaScript:**
```sql
-- Complex cursors: Use JavaScript stored procedure
CREATE OR REPLACE PROCEDURE proc_name(...)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
AS $$
  // JavaScript implementation
$$;
```

---

## Directory Structure

```
src/
  Tables/           ← SQL Server source tables
  Views/            ← SQL Server source views
  Functions/        ← SQL Server source functions
  StoredProcedures/ ← SQL Server source procedures

snowflake/
  tables/           ← Translated Snowflake tables
  views/            ← Translated Snowflake views
  functions/        ← Translated Snowflake functions
  procedures/       ← Translated Snowflake procedures

migration-plans/
  <procedure>.md    ← Migration plan with status
```

---

## Example Commands

**Deploy a single table:**
```bash
snow sql -f snowflake/tables/BudgetHeader.sql
```

**Deploy all tables:**
```bash
for f in snowflake/tables/*.sql; do snow sql -f "$f"; done
```

**Check if object exists:**
```bash
snow sql -q "SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA='PLANNING' AND TABLE_NAME='BUDGETHEADER'"
```
