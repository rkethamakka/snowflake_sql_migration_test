---
name: test-data-generator
description: Generate test data for both SQL Server and Snowflake to enable comparison testing
---

# Skill: test-data-generator

Generate test data for both SQL Server and Snowflake to enable comparison testing.

## When to Use
- After tables are migrated to Snowflake
- Need matching data in both systems for verification
- User says "create test data" or "generate data"

## Prerequisites
- SQL Server running (Docker or local)
- Snowflake tables created
- Know which tables need data

## Workflow

### Step 1: Read Procedure Signature
Analyze the stored procedure to understand:
- Required tables (from JOINs and WHERE clauses)
- Required columns (from SELECT and INSERT statements)
- Data relationships (foreign keys, hierarchies)
- Edge cases to test (NULL handling, boundary values)

**IMPORTANT:** Do NOT guess schema - read actual DDL files to get correct:
- Column names
- Data types
- Constraints
- Default values

### Step 2: Determine Data Requirements
For each table:
- Minimum rows needed to test procedure logic
- Foreign key relationships to respect
- Special values needed (e.g., hierarchy levels, date ranges)
- Edge cases (empty sets, NULLs, large values, etc.)

**For hierarchical data:**
- Create 3-4 level hierarchies (not just 1-2 levels)
- Include both leaf and parent nodes
- Test deep nesting (if procedure supports it)

**For intercompany/elimination logic:**
- Include BOTH matched pairs (offsetting entries)
- Include unmatched entries (should NOT be eliminated)
- Test zero amounts, negative amounts, large amounts

### Step 3: Generate INSERT Statements with Schema Mapping

Create two files:
- `test-data/sqlserver/setup.sql` — SQL Server syntax
- `test-data/snowflake/setup.sql` — Snowflake syntax

**CRITICAL: Apply Schema Mapping Rules**

| SQL Server Type | Snowflake Type | Conversion Notes |
|-----------------|----------------|------------------|
| `INT` | `INTEGER` or `FLOAT` | Use FLOAT for JavaScript procedure parameters |
| `NVARCHAR(n)` | `VARCHAR(n)` | Snowflake VARCHAR is Unicode by default |
| `VARCHAR(MAX)` | `VARCHAR(16777216)` | Snowflake max length |
| `DATETIME2` | `TIMESTAMP_NTZ` | No timezone by default |
| `BIT` | `BOOLEAN` | `1`/`0` → `TRUE`/`FALSE` |
| `UNIQUEIDENTIFIER` | `STRING` (36 chars) | Use `UUID_STRING()` |
| `XML` | `VARIANT` | Parse to JSON if needed |
| `HIERARCHYID` | `VARCHAR(4000)` | Materialized path pattern |
| `IDENTITY(1,1)` | Explicit IDs | No `SET IDENTITY_INSERT` in Snowflake |

**Additional differences:**
| Feature | SQL Server | Snowflake |
|---------|-----------|-----------|
| Identity insert | `SET IDENTITY_INSERT table ON` | Not needed (use explicit IDs) |
| Boolean literals | `1` / `0` | `TRUE` / `FALSE` |
| UUID generation | `NEWID()` | `UUID_STRING()` |
| Current timestamp | `GETDATE()` | `CURRENT_TIMESTAMP()` |
| String concatenation | `+` | `||` or `CONCAT()` |
| Schema prefix | `[dbo].[Table]` | `SCHEMA.TABLE` (no brackets) |

### Step 4: Load Data

**SQL Server:**
```bash
# Using sqlcmd
sqlcmd -S localhost -U sa -P '<password>' -d Planning -i test-data/sqlserver/setup.sql

# Or using mssql-cli
mssql-cli -S localhost -U sa -P '<password>' -d Planning -i test-data/sqlserver/setup.sql
```

**Snowflake:**
```bash
snow sql -f test-data/snowflake/setup.sql
```

### Step 5: Verify Data Matches

```sql
-- SQL Server
SELECT 'FiscalPeriod' as tbl, COUNT(*) as cnt FROM Planning.FiscalPeriod
UNION ALL SELECT 'GLAccount', COUNT(*) FROM Planning.GLAccount
-- etc.

-- Snowflake
SELECT 'FiscalPeriod' as tbl, COUNT(*) as cnt FROM PLANNING.FiscalPeriod
UNION ALL SELECT 'GLAccount', COUNT(*) FROM PLANNING.GLAccount
-- etc.
```

## Test Data Template

For `usp_ProcessBudgetConsolidation`:

### FiscalPeriod (4 rows)
```sql
-- Q1-Q4 2024
INSERT INTO Planning.FiscalPeriod (FiscalPeriodID, FiscalYear, FiscalQuarter, FiscalMonth, PeriodName, PeriodStartDate, PeriodEndDate)
VALUES 
(1, 2024, 1, 1, 'Q1 2024', '2024-01-01', '2024-03-31'),
(2, 2024, 2, 4, 'Q2 2024', '2024-04-01', '2024-06-30'),
(3, 2024, 3, 7, 'Q3 2024', '2024-07-01', '2024-09-30'),
(4, 2024, 4, 10, 'Q4 2024', '2024-10-01', '2024-12-31');
```

### CostCenter (7 rows - 3 level hierarchy)
```sql
-- Level 1: Company
-- Level 2: Engineering, Sales
-- Level 3: Backend, Frontend, North, South
INSERT INTO Planning.CostCenter (CostCenterID, CostCenterCode, CostCenterName, ParentCostCenterID, HierarchyLevel)
VALUES
(1, 'CORP', 'Company', NULL, 1),
(2, 'ENG', 'Engineering', 1, 2),
(3, 'SALES', 'Sales', 1, 2),
(4, 'ENG-BE', 'Backend Team', 2, 3),
(5, 'ENG-FE', 'Frontend Team', 2, 3),
(6, 'SALES-N', 'North Region', 3, 3),
(7, 'SALES-S', 'South Region', 3, 3);
```

### GLAccount (5 rows)
```sql
INSERT INTO Planning.GLAccount (GLAccountID, AccountNumber, AccountName, AccountType)
VALUES
(1, '4000', 'Revenue', 'R'),
(2, '5000', 'Cost of Sales', 'X'),
(3, '6000', 'Operating Expenses', 'X'),
(4, '7000', 'Admin Expenses', 'X'),
(5, '8000', 'Other Income', 'R');
```

### BudgetHeader (1 row - source budget)
```sql
INSERT INTO Planning.BudgetHeader (BudgetHeaderID, BudgetCode, BudgetName, BudgetType, ScenarioType, FiscalYear, StartPeriodID, EndPeriodID, StatusCode)
VALUES
(1, 'BUD-2024-001', '2024 Annual Budget', 'ANNUAL', 'BASE', 2024, 1, 4, 'APPROVED');
```

### BudgetLineItem (12 rows - spread across cost centers)
```sql
-- Sample amounts for each cost center and account
INSERT INTO Planning.BudgetLineItem (BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID, OriginalAmount, AdjustedAmount)
VALUES
-- Backend team
(1, 1, 4, 1, 100000, 0),  -- Revenue Q1
(1, 3, 4, 1, 50000, 0),   -- OpEx Q1
-- Frontend team
(1, 1, 5, 1, 80000, 0),   -- Revenue Q1
(1, 3, 5, 1, 40000, 0),   -- OpEx Q1
-- Sales North
(1, 1, 6, 1, 200000, 0),  -- Revenue Q1
(1, 2, 6, 1, 120000, 0),  -- Cost of Sales Q1
-- etc.
```

## Output Files

```
test/data/
├── sqlserver/
│   ├── {procedure_name}_setup.sql      ← Creates test data (SQL Server syntax)
│   ├── {procedure_name}_cleanup.sql    ← Deletes test data (for re-runs)
│   └── README.md                       ← Documents test scenarios
├── snowflake/
│   ├── {procedure_name}_setup.sql      ← Creates test data (Snowflake syntax)
│   ├── {procedure_name}_cleanup.sql    ← Deletes test data
│   └── README.md                       ← Documents schema differences
└── verify-counts.sql                   ← Compares row counts between systems
```

---

## Lessons Learned (2026-02-06)

### ❌ What NOT to Do

**DON'T create test data manually** - The user created test data with manual INSERT statements instead of using this skill. Problems encountered:
- ❌ Column name errors (wrong case, wrong names)
- ❌ Data type mismatches (INT vs FLOAT for JavaScript procedures)
- ❌ Only created data in Snowflake (not SQL Server)
- ❌ No documentation of test scenarios
- ❌ Error-prone and time-consuming

### ✅ What TO Do

**DO use this skill** - It should:
- ✅ Read actual table DDL for correct schema
- ✅ Generate data for BOTH systems automatically
- ✅ Apply schema mapping rules (NVARCHAR→VARCHAR, etc.)
- ✅ Handle JavaScript procedure parameter types (INT→FLOAT)
- ✅ Document test scenarios and edge cases
- ✅ Provide cleanup scripts for re-runs

### Common Mistakes to Avoid

1. **Guessing column names**
   - DON'T: Assume column names from procedure logic
   - DO: Read actual table DDL from `sqlserver/Tables/*.sql` and `snowflake/Tables/*.sql`

2. **Wrong data types for JavaScript procedures**
   - DON'T: Use `INT` parameters (causes type errors)
   - DO: Use `FLOAT` for numeric parameters in JavaScript procedures

3. **Insufficient hierarchy depth**
   - DON'T: Create only 1-2 level hierarchies
   - DO: Create 3-4 levels to test rollup logic properly

4. **Missing edge cases**
   - DON'T: Only test happy path
   - DO: Include NULLs, zeros, unmatched pairs, empty sets

5. **Only creating data in one system**
   - DON'T: Create test data only in Snowflake
   - DO: Create identical data in BOTH SQL Server and Snowflake for comparison

### Schema Mapping Lessons

**JavaScript Procedures Require FLOAT:**
```sql
-- SQL Server original parameter
@SourceBudgetHeaderID INT

-- Snowflake JavaScript procedure parameter
SOURCE_BUDGET_HEADER_ID FLOAT  -- Must be FLOAT, not INTEGER

-- Test data must use FLOAT values
INSERT INTO BudgetHeader (BudgetHeaderID, ...) VALUES (1.0, ...);  -- Not just 1
```

**NVARCHAR → VARCHAR:**
```sql
-- SQL Server
BudgetCode NVARCHAR(50)

-- Snowflake
BudgetCode VARCHAR(50)  -- No 'N' prefix needed

-- Test data
INSERT ... VALUES ('BUD-2024-001', ...);  -- Same in both systems
```

**BIT → BOOLEAN:**
```sql
-- SQL Server test data
IntercompanyFlag BIT
INSERT ... VALUES (1, ...);

-- Snowflake test data
IntercompanyFlag BOOLEAN
INSERT ... VALUES (TRUE, ...);
```

### Critical Lessons from usp_ProcessBudgetConsolidation Testing (2026-02-06)

**1. Test Data MUST Expose Order-of-Operations Bugs**

The test data we generated successfully exposed a critical bug:
- **Bug:** Elimination logic ran AFTER hierarchy rollup
- **Test Data Design:** Matched IC pair (+$10K/-$10K) where one entry was a child of the other
- **Why it worked:** When Corporate (+$10K) rolled up Engineering (-$10K), they netted to $0 BEFORE elimination could find the pair
- **Lesson:** Design test data to expose SEQUENCING issues, not just logic correctness

**Key Test Data Requirements for Consolidation:**
- ✅ Matched IC pairs at DIFFERENT hierarchy levels (parent-child relationship)
- ✅ Unmatched IC entries (to verify only matched pairs eliminated)
- ✅ Multi-level hierarchy (3+ levels) to test rollup accumulation
- ✅ Parent nodes with BOTH direct amounts AND child amounts
- ✅ Parent nodes with ONLY child amounts (no direct)
- ✅ Edge cases: zero amounts, NULL values

**2. Read Actual Table DDL (Never Guess)**

During test data generation, we had to:
- Read actual DDL files to get correct column names (CostCenterID, not CostCenterId)
- Verify data types match (FLOAT for JavaScript procedures, not INT)
- Check for required vs optional columns (IsActive, EffectiveFromDate)
- Understand default values and constraints

**3. Schema Mapping Precision**

Apply these mappings CONSISTENTLY:
- `NVARCHAR(n)` → `VARCHAR(n)` (Snowflake VARCHAR is Unicode)
- `BIT` → `BOOLEAN` (1/0 → TRUE/FALSE)
- `INT` → `FLOAT` (for JavaScript procedure parameters)
- `DATETIME2` → `TIMESTAMP_NTZ`
- `GETDATE()` → `CURRENT_TIMESTAMP()`

**4. Test Data Volume**

For this procedure, we generated:
- 12 FiscalPeriod rows (full year)
- 6 GLAccount rows (5 operational + 1 IC)
- 7 CostCenter rows (3-level hierarchy)
- 1 BudgetHeader row (source budget)
- 14 BudgetLineItem rows (40 total after verification)

This was SUFFICIENT to expose the bug. More data would NOT have found it faster.

**Lesson:** Quality over quantity - design data to test edge cases, not just volume.

### Automation Improvements Needed

**Auto-detect data type conversions:**
1. Read procedure signature
2. Identify parameter types (INT vs FLOAT)
3. Generate matching test data types
4. Warn about JavaScript FLOAT requirement

**Auto-detect hierarchical patterns:**
1. Scan for `ParentCostCenterID`, `HierarchyPath`, etc.
2. Generate multi-level hierarchies automatically
3. Include closure table test data if needed
4. **NEW:** Generate parent-child IC pairs to test elimination order

**Auto-detect intercompany patterns:**
1. Scan for `IntercompanyFlag` column
2. Generate matched pairs (offsetting amounts)
3. Generate unmatched entries (should be preserved)
4. **NEW:** Create matched pairs across DIFFERENT hierarchy levels to test order-of-operations

---

## Usage Example

```bash
# Invoke the skill (don't do manual work)
Skill: test-data-generator usp_ProcessBudgetConsolidation

# The skill should:
# 1. Read procedure DDL and identify required tables
# 2. Read table DDL for correct schema
# 3. Generate test data for SQL Server (test/data/sqlserver/usp_ProcessBudgetConsolidation_setup.sql)
# 4. Generate test data for Snowflake (test/data/snowflake/usp_ProcessBudgetConsolidation_setup.sql)
# 5. Apply schema mapping (NVARCHAR→VARCHAR, BIT→BOOLEAN, INT→FLOAT)
# 6. Load data to both systems
# 7. Verify row counts match
```

**Expected Outcome:**
- Identical data in both systems (accounting for data type differences)
- Ready for side-by-side verification testing
- Documented test scenarios
- Cleanup scripts for re-runs

---

## Future Enhancements

1. **Smart data generation**
   - Analyze procedure logic to generate edge cases
   - Detect loops and generate data to test iteration
   - Detect aggregations and generate data to test SUM/COUNT

2. **Schema auto-detection**
   - Read procedure DDL to find table references
   - Read table DDL to get exact column names and types
   - Auto-generate INSERT statements with correct schema

3. **Referential integrity validation**
   - Verify all foreign keys satisfied
   - Warn about missing reference data
   - Auto-generate parent records if needed

4. **Data volume scaling**
   - Generate minimal data for quick tests
   - Generate realistic volumes for performance tests
   - Support batch generation for large datasets
