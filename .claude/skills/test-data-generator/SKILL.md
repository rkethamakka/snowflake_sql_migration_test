---
name: test-data-generator
description: Generate test data for both SQL Server and Snowflake to enable comparison testing
---

# Skill: test-data-generator

Generate test data for both SQL Server and Snowflake to enable comparison testing.

## Prerequisites

**Snowflake CLI:**
```bash
which snow || find /usr -name "snow" 2>/dev/null || find ~/Library -name "snow" 2>/dev/null
```

If not found, install: `pip install snowflake-cli-labs`

**Docker:** SQL Server container must be running:
```bash
docker ps | grep sqlserver
```

---

## When to Use
- After migration is deployed to Snowflake
- Before running sql-migration-verify
- User says "generate test data"

## Input
- Migration plan file (to know what tables exist)
- Or explicit list of tables

## Output Files (STRICT)

**ONLY create these 2 files:**
- `test/data/snowflake/<procedure>_setup.sql` (Snowflake test data with DELETE + INSERT statements)
- `test/data/sqlserver/<procedure>_setup.sql` (SQL Server test data with IDENTITY_INSERT and hierarchyid::Parse())

**DO NOT create:**
- ❌ Any .md documentation files (no summaries, no completion reports, no data catalogs)
- ❌ Any Python scripts or loaders
- ❌ Any extra .sql files (no load_data.sql, no load_glaccounts.sql, etc.)
- ❌ Any helper files

The skill must create ONLY the 2 test data setup files.

---

## Workflow

### Step 0: Setup Environment

**IMPORTANT:** Ensure snow CLI is in PATH for all Bash commands:

Every Bash command that uses `snow` must include PATH setup:
```bash
export PATH="$PATH:$HOME/Library/Python/3.9/bin" && snow sql -q "..."
```

### Step 1: Identify Tables from Migration Plan
```bash
cat migration-plans/<procedure>.md
```

Extract table list from Dependencies section.

### Step 2: Get Table Schemas

**Snowflake:**
```bash
snow sql -q "DESCRIBE TABLE FINANCIAL_PLANNING.PLANNING.<TABLE>"
```

**SQL Server:**
```bash
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong@Passw0rd' -C \
  -d FINANCIAL_PLANNING -Q "
  SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE
  FROM INFORMATION_SCHEMA.COLUMNS
  WHERE TABLE_SCHEMA='Planning' AND TABLE_NAME='<TABLE>'"
```

### Step 3: Generate Test Data

Create realistic test data that:
- Covers all foreign key relationships
- Includes edge cases (NULLs, max values)
- Has matching data between systems
- Tests specific business logic (e.g., IC elimination pairs)

**Reference data first (no FKs):**
- FiscalPeriod
- GLAccount
- CostCenter

**Then transactional data:**
- BudgetHeader
- BudgetLineItem

### Step 4: Write Setup Scripts

**Snowflake format:**
```sql
-- Clear existing data
DELETE FROM PLANNING.BudgetLineItem;
DELETE FROM PLANNING.BudgetHeader;
-- ... etc

-- Insert reference data
INSERT INTO PLANNING.FiscalPeriod (...) VALUES (...);

-- Insert transactional data
INSERT INTO PLANNING.BudgetHeader (...) VALUES (...);
INSERT INTO PLANNING.BudgetLineItem (...) VALUES (...);

SELECT 'Test data loaded' AS Status;
```

**SQL Server format:**
```sql
USE FINANCIAL_PLANNING;
GO

SET QUOTED_IDENTIFIER ON;
GO

-- Enable identity insert
SET IDENTITY_INSERT Planning.FiscalPeriod ON;

INSERT INTO Planning.FiscalPeriod (...) VALUES (...);

SET IDENTITY_INSERT Planning.FiscalPeriod OFF;
GO

-- Continue with other tables...
```

### Step 5: Load Data

**Snowflake:**
```bash
snow sql -f test/data/snowflake/<procedure>_setup.sql
```

**SQL Server:**
```bash
cat test/data/sqlserver/<procedure>_setup.sql | \
  docker exec -i sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong@Passw0rd' -C -d FINANCIAL_PLANNING
```

### Step 6: Verify Row Counts

```bash
# Snowflake
snow sql -q "
SELECT 'FiscalPeriod' as tbl, COUNT(*) as cnt FROM PLANNING.FISCALPERIOD
UNION ALL SELECT 'GLAccount', COUNT(*) FROM PLANNING.GLACCOUNT
UNION ALL SELECT 'CostCenter', COUNT(*) FROM PLANNING.COSTCENTER
UNION ALL SELECT 'BudgetHeader', COUNT(*) FROM PLANNING.BUDGETHEADER
UNION ALL SELECT 'BudgetLineItem', COUNT(*) FROM PLANNING.BUDGETLINEITEM
"

# SQL Server
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'YourStrong@Passw0rd' -C -d FINANCIAL_PLANNING -Q "
SET QUOTED_IDENTIFIER ON;
SELECT 'FiscalPeriod' as tbl, COUNT(*) as cnt FROM Planning.FiscalPeriod
UNION ALL SELECT 'GLAccount', COUNT(*) FROM Planning.GLAccount
UNION ALL SELECT 'CostCenter', COUNT(*) FROM Planning.CostCenter
UNION ALL SELECT 'BudgetHeader', COUNT(*) FROM Planning.BudgetHeader
UNION ALL SELECT 'BudgetLineItem', COUNT(*) FROM Planning.BudgetLineItem
"
```

---

## Test Data Design Tips

### For Hierarchy Testing
Create multi-level hierarchies:
```
CORP (root)
├── ENG (level 1)
│   ├── ENG-BE (level 2)
│   └── ENG-FE (level 2)
├── SALES (level 1)
│   └── SALES-W (level 2)
└── MKT (level 1)
```

### For IC Elimination Testing
Create matched pairs:
```sql
-- CORP → ENG: +$10K
(1, 6, 1, 1, 10000, 0, 'MANUAL'),
-- ENG → CORP: -$10K (offsetting)
(1, 6, 2, 1, -10000, 0, 'MANUAL'),
```

### For Amount Verification
Use round numbers that are easy to verify:
- $100,000, $50,000, $25,000
- Makes manual verification easier
