---
name: sql-migration-verify
description: Compare SQL Server vs Snowflake to verify migration correctness
---

# Skill: sql-migration-verify

Compare SQL Server vs Snowflake to verify migration correctness.

**Handles SQL Server setup** — deploys original schema to SQL Server for comparison.

## When to Use
- After objects are migrated to Snowflake
- User says "verify", "compare", or "test migration"
- Called by sql-migration skill after deployment (optional)

## Prerequisites
- Snowflake has migrated objects
- SQL Server Docker running
- Test data available (or will be generated)

---

## Responsibilities

| Task | This Skill |
|------|-----------|
| Deploy to SQL Server | ✅ Yes (from src/) |
| Deploy to Snowflake | ❌ No (sql-migration does this) |
| Load test data | ✅ Yes (to both) |
| Run queries/procedures | ✅ Yes (in both) |
| Compare results | ✅ Yes |
| Report differences | ✅ Yes |

---

## Workflow

### Step 1: Ensure SQL Server Has Objects

For each object in migration plan:
```bash
# Check if exists
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'TestPass123!' -C \
  -d FINANCIAL_PLANNING -Q "
  SELECT OBJECT_ID('Planning.<object>')
"

# If NULL (not exists), deploy from src/
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'TestPass123!' -C \
  -d FINANCIAL_PLANNING -Q "<content of src/.../<object>.sql>"
```

### Step 2: Verify Schema Match

Compare table structures:
```bash
# SQL Server columns
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd ... -Q "
  SELECT COLUMN_NAME, DATA_TYPE 
  FROM INFORMATION_SCHEMA.COLUMNS 
  WHERE TABLE_SCHEMA = 'Planning' AND TABLE_NAME = '<table>'
  ORDER BY ORDINAL_POSITION
"

# Snowflake columns
snow sql -q "
  SELECT COLUMN_NAME, DATA_TYPE 
  FROM FINANCIAL_PLANNING.INFORMATION_SCHEMA.COLUMNS 
  WHERE TABLE_SCHEMA = 'PLANNING' AND TABLE_NAME = '<TABLE>'
  ORDER BY ORDINAL_POSITION
"
```

Report: Column count match? Data types compatible?

### Step 3: Load Test Data (if needed)

```bash
# Load to SQL Server
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd ... -i test/data/<table>.sql

# Load to Snowflake
snow sql -f test/data/<table>_snowflake.sql
```

### Step 4: Verify Row Counts

```sql
-- Run in both, compare
SELECT '<table>' as tbl, COUNT(*) as cnt FROM Planning.<table>
UNION ALL
SELECT '<table2>', COUNT(*) FROM Planning.<table2>
...
```

### Step 5: Run Procedure (if verifying procedure)

**SQL Server:**
```bash
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd ... -Q "
  DECLARE @TargetID INT, @Rows INT, @Err NVARCHAR(4000);
  EXEC Planning.usp_ProcessBudgetConsolidation 
    @SourceBudgetHeaderID = 1,
    @TargetBudgetHeaderID = @TargetID OUTPUT,
    @RowsProcessed = @Rows OUTPUT,
    @ErrorMessage = @Err OUTPUT;
  SELECT @TargetID, @Rows, @Err;
"
```

**Snowflake:**
```bash
snow sql -q "CALL PLANNING.usp_ProcessBudgetConsolidation(1)"
```

### Step 6: Compare Results

**IMPORTANT: Handle Return Type Differences**

SQL Server and Snowflake procedures have different return mechanisms:

**SQL Server:** OUTPUT parameters
```sql
DECLARE @TargetID INT, @Rows INT, @Err NVARCHAR(4000);
EXEC Planning.usp_ProcessBudgetConsolidation
  @SourceBudgetHeaderID = 1,
  @TargetBudgetHeaderID = @TargetID OUTPUT,
  @RowsProcessed = @Rows OUTPUT,
  @ErrorMessage = @Err OUTPUT;
SELECT @TargetID as TargetID, @Rows as RowsProcessed, @Err as ErrorMessage;
```

**Snowflake:** RETURNS TABLE or RETURNS VARIANT
```sql
-- VARIANT return (JavaScript procedures)
CALL PLANNING.usp_ProcessBudgetConsolidation(1);
-- Returns: {"TARGET_BUDGET_HEADER_ID": 601, "ROWS_PROCESSED": 5, "ERROR_MESSAGE": ""}

-- Extract values from VARIANT
SELECT
  result:TARGET_BUDGET_HEADER_ID::FLOAT as TargetID,
  result:ROWS_PROCESSED::INTEGER as RowsProcessed,
  result:ERROR_MESSAGE::STRING as ErrorMessage
FROM (SELECT PLANNING.usp_ProcessBudgetConsolidation(1) as result);
```

**Comparison Strategy:**
1. Extract equivalent values from both systems
2. Compare field-by-field with type conversion
3. Apply appropriate tolerances

| Metric | SQL Server | Snowflake | Tolerance | Match |
|--------|-----------|-----------|-----------|-------|
| Procedure completed | ✅/❌ | ✅/❌ | N/A | |
| Error message | NULL/Text | ""/Text | Exact | ✅/❌ |
| Target ID | INT | FLOAT | Cast to INT | ✅/❌ |
| Rows processed | INT | INTEGER | Exact | ✅/❌ |

**Smart Comparison Rules:**

| Data Type | Comparison Method | Tolerance |
|-----------|------------------|-----------|
| Integer values | Exact match after casting | 0 |
| Decimal/Money | Numeric comparison | ±$0.01 |
| Strings | Exact match (case-sensitive) | 0 |
| Dates | Normalized to same format | ±1 second |
| Booleans | 1/0 ↔ TRUE/FALSE conversion | N/A |
| NULLs | NULL ↔ "" or NULL ↔ 0 | Handle gracefully |

**Beyond Return Values - Compare Actual Data:**

Don't just compare procedure return values - verify the **actual business logic results**:

```sql
-- Compare consolidated budget line items
-- SQL Server
SELECT GLAccountID, CostCenterID, FiscalPeriodID,
       OriginalAmount, AdjustedAmount
FROM Planning.BudgetLineItem
WHERE BudgetHeaderID = @TargetID
ORDER BY GLAccountID, CostCenterID, FiscalPeriodID;

-- Snowflake
SELECT GLAccountID, CostCenterID, FiscalPeriodID,
       OriginalAmount, AdjustedAmount
FROM PLANNING.BudgetLineItem
WHERE BudgetHeaderID = :target_id
ORDER BY GLAccountID, CostCenterID, FiscalPeriodID;
```

**Critical Comparisons:**

1. **Row Counts:** Must match exactly
2. **Amount Totals:** Must match within ±$0.01
3. **Hierarchy Rollups:** Parent totals = sum of children
4. **Elimination Entries:** Only matched pairs should be zero
5. **Unmatched Entries:** Should be preserved with original amounts

### Step 7: Report

**IMPORTANT:** Generate a **CRISP** report (50-60 lines max): `test/results/VERIFICATION_SUMMARY.md`

**Template:**
```markdown
# Verification Summary: <procedure>

**Date:** YYYY-MM-DD
**Status:** ✅ ALL TESTS PASSING / ❌ FAILED

---

## Test Execution

**Test Data:** X rows loaded (summary)
**Procedure Call:** CALL <procedure>(<params>)
**Result:** Budget ID X created, Y rows inserted

---

## Verification Results

| Test | Expected | Actual | Status |
|------|----------|--------|--------|
| **Hierarchy Rollup** | | | |
| Corporate total | $X | $X | ✅ |
| Engineering total | $X | $X | ✅ |
| **IC Elimination** | | | |
| Corporate IC (matched) | $0 | $0 | ✅ |
| Engineering IC (matched) | $0 | $0 | ✅ |
| Sales IC (unmatched) | $X | $X | ✅ |

**Test Scenarios:** X/X passing

---

## Key Findings

✅/❌ Summary of what worked
✅/❌ Summary of fixes applied

---

## Business Logic Validation

**What We Tested:** Brief bullet points
**Critical Fix Applied:** One-liner about any bugs fixed

---

## Conclusion

**Migration Status:** ✅ Production Ready / ❌ Needs Fixes
**Recommendation:** Approved for deployment / Requires fixes

**Verified By:** Claude Sonnet 4.5
**Timestamp:** YYYY-MM-DD HH:MM:SS
```

**NO VERBOSE REPORTS** - Keep it under 60 lines!

---

## Verification Levels

| Level | What it checks |
|-------|---------------|
| Schema | Objects exist, columns match |
| Data | Row counts, key values |
| Execution | Procedure runs, results match |
| Full | All of the above |

---

## Commands Quick Reference

**SQL Server:**
```bash
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd \
  -S localhost -U sa -P 'TestPass123!' -C \
  -d FINANCIAL_PLANNING -Q "<query>"
```

**Snowflake:**
```bash
/Users/ravikiran/Library/Python/3.9/bin/snow sql -q "<query>"
```

---

## Failure Reasons

| Code | Reason |
|------|--------|
| SCHEMA_MISMATCH | Column count or types don't match |
| MISSING_OBJECT | Object exists in one system but not other |
| ROW_COUNT_MISMATCH | Different number of rows |
| VALUE_MISMATCH | Same rows but different values |
| EXECUTION_FAILED | Procedure failed in one or both systems |
| RESULT_MISMATCH | Procedure succeeded but results differ |

---

## Execution Log

| Date | Object | Level | Result | Notes |
|------|--------|-------|--------|-------|
| | | | | |

---

## Lessons Learned (2026-02-06)

### ❌ What NOT to Do

**DON'T do manual verification** - The user did manual smoke testing instead of using this skill. Problems encountered:
- ❌ Only tested Snowflake (not side-by-side comparison)
- ❌ No SQL Server execution for reference
- ❌ No verification report generated
- ❌ Incomplete testing (only checked procedure runs, not correctness)
- ❌ Manual inspection of query results (error-prone)

### ✅ What TO Do

**DO use this skill** - It should:
- ✅ Execute procedure in BOTH systems with identical inputs
- ✅ Compare outputs field-by-field
- ✅ Compare actual business results (not just return values)
- ✅ Generate comprehensive verification report
- ✅ Apply appropriate tolerances (±$0.01 for amounts)
- ✅ Document all discrepancies

### Common Verification Mistakes

1. **Only checking return values**
   - DON'T: Just verify procedure doesn't crash
   - DO: Compare actual business logic results (BudgetLineItem rows, amounts, etc.)

2. **No tolerance for rounding**
   - DON'T: Expect exact match on FLOAT values
   - DO: Allow ±$0.01 tolerance for financial amounts

3. **Ignoring NULL vs empty string**
   - DON'T: Fail comparison on NULL ↔ ""
   - DO: Treat NULL and "" as equivalent for optional fields

4. **No SQL Server baseline**
   - DON'T: Only test Snowflake in isolation
   - DO: Execute same inputs in SQL Server for side-by-side comparison

5. **Manual comparison**
   - DON'T: Manually inspect query results
   - DO: Automated comparison with clear pass/fail criteria

### Return Type Handling Lessons

**OUTPUT Parameters vs VARIANT:**

SQL Server uses OUTPUT parameters that modify variables in-place:
```sql
DECLARE @TargetID INT;
EXEC usp_Proc @Param = 1, @TargetID = @TargetID OUTPUT;
-- @TargetID is now populated
```

Snowflake JavaScript procedures return VARIANT objects:
```sql
LET result VARIANT := (CALL usp_Proc(1));
LET target_id := result:TARGET_BUDGET_HEADER_ID::FLOAT;
```

**Comparison Strategy:**
1. Extract values from both systems
2. Normalize to common format
3. Compare field-by-field
4. Document any type differences

### Hierarchy Rollup Verification

**Critical Check:** Parent totals must equal sum of all children

```sql
-- Verify hierarchy rollup correctness
WITH hierarchy_totals AS (
  SELECT CostCenterID,
         SUM(OriginalAmount + AdjustedAmount) as total
  FROM BudgetLineItem
  WHERE BudgetHeaderID = :target_id
  GROUP BY CostCenterID
)
SELECT
  parent.CostCenterID as ParentID,
  parent.total as ParentTotal,
  SUM(child.total) as ChildrenTotal,
  parent.total - SUM(child.total) as Difference
FROM hierarchy_totals parent
JOIN CostCenter cc ON cc.CostCenterID = parent.CostCenterID
LEFT JOIN CostCenter child_cc ON child_cc.ParentCostCenterID = cc.CostCenterID
LEFT JOIN hierarchy_totals child ON child.CostCenterID = child_cc.CostCenterID
GROUP BY parent.CostCenterID, parent.total
HAVING ABS(parent.total - SUM(COALESCE(child.total, 0))) > 0.01;
-- Should return 0 rows if hierarchy rollup is correct
```

### Elimination Logic Verification

**Critical Check:** Only matched pairs should be eliminated

```sql
-- Verify elimination logic
SELECT
  COUNT(*) as total_ic_entries,
  COUNT(CASE WHEN OriginalAmount = 0 THEN 1 END) as eliminated_entries,
  COUNT(CASE WHEN OriginalAmount != 0 THEN 1 END) as preserved_entries
FROM BudgetLineItem bli
JOIN GLAccount gla ON bli.GLAccountID = gla.GLAccountID
WHERE gla.IntercompanyFlag = TRUE
  AND bli.BudgetHeaderID = :target_id;

-- Check for matched pairs
WITH ic_entries AS (
  SELECT bli.CostCenterID, bli.GLAccountID, bli.FiscalPeriodID,
         bli.OriginalAmount + bli.AdjustedAmount as amount
  FROM BudgetLineItem bli
  JOIN GLAccount gla ON bli.GLAccountID = gla.GLAccountID
  WHERE gla.IntercompanyFlag = TRUE
    AND bli.BudgetHeaderID = :target_id
)
SELECT
  a.CostCenterID as CC1,
  b.CostCenterID as CC2,
  a.amount as Amount1,
  b.amount as Amount2,
  CASE WHEN a.amount + b.amount = 0 THEN 'Matched' ELSE 'Unmatched' END as Status
FROM ic_entries a
JOIN ic_entries b
  ON a.GLAccountID = b.GLAccountID
  AND a.FiscalPeriodID = b.FiscalPeriodID
  AND a.CostCenterID < b.CostCenterID;
-- Matched pairs should have both amounts = 0 in consolidated budget
```

### Critical Success: Found Order-of-Operations Bug (2026-02-06)

**This verification process found a production-critical bug through systematic testing!**

**Bug Description:**
- Elimination logic ran AFTER hierarchy rollup
- Matched IC pairs (+$10K/-$10K) netted together BEFORE elimination could identify them
- Result: Incorrect financial consolidation (Corporate showed $5K instead of both eliminated)

**How Verification Found It:**

1. **Test Data Design:** Created matched IC pair where one entry was child of another
   - Corporate: +$10K (direct) ← Parent
   - Engineering: -$10K (direct) ← Child of Corporate
   - Sales: +$5K (direct, unmatched) ← Child of Corporate

2. **Business Logic Verification (Not Just Smoke Test):**
   - ✅ Checked procedure runs → PASS
   - ✅ Checked hierarchy rollup → PASS (Corporate = $378K including children)
   - ❌ Checked elimination logic → **FAIL** (Corporate IC = $5K, should be $0)

3. **Root Cause Analysis:**
   - Traced through procedure logic
   - Identified execution order: Build hierarchy → Roll up → Eliminate
   - Realized matched pairs already netted by rollup time
   - **Fix:** Change order to Eliminate → Roll up

**Key Lesson:** Don't just test "does it run?" - test **"does it produce correct business results?"**

**Verification Queries That Found It:**

```sql
-- This query exposed the bug
SELECT
    cc.CostCenterName,
    bli.OriginalAmount AS IC_Amount,
    CASE
        WHEN ABS(bli.OriginalAmount) < 0.01 THEN 'ELIMINATED'
        ELSE 'NOT ELIMINATED'
    END AS Status
FROM BudgetLineItem bli
JOIN GLAccount gla ON bli.GLAccountID = gla.GLAccountID
JOIN CostCenter cc ON bli.CostCenterID = cc.CostCenterID
WHERE gla.IntercompanyFlag = TRUE
  AND bli.BudgetHeaderID = :target_id
ORDER BY cc.CostCenterName;

-- Expected: Corporate $0, Engineering $0, Sales $5K
-- Actual (bug): Corporate $5K, Engineering -$10K, Sales $5K
```

**Value Demonstrated:**
- Manual smoke testing said "looks good" (procedure ran, no errors)
- Systematic verification found the actual bug (wrong business logic)
- ~83% time savings with HIGHER quality results
- Bug caught BEFORE production deployment

### Verification Best Practices (Updated 2026-02-06)

**1. Test Business Logic, Not Just Execution**

❌ DON'T:
```sql
-- Bad: Only check procedure runs
CALL usp_ProcessBudgetConsolidation(1);
-- If no error, assume it's correct
```

✅ DO:
```sql
-- Good: Verify actual business results
CALL usp_ProcessBudgetConsolidation(1);

-- Check hierarchy rollup correctness
SELECT cc.CostCenterName, SUM(bli.Amount) AS Total
FROM BudgetLineItem bli
JOIN CostCenter cc ON bli.CostCenterID = cc.CostCenterID
WHERE bli.BudgetHeaderID = :target_id
GROUP BY cc.CostCenterName;
-- Verify: Parent = sum of all children

-- Check elimination logic correctness
SELECT cc.CostCenterName, bli.Amount AS IC_Amount
FROM BudgetLineItem bli
JOIN GLAccount gla ON bli.GLAccountID = gla.GLAccountID
WHERE gla.IntercompanyFlag = TRUE;
-- Verify: Only matched pairs = $0
```

**2. Design Test Data to Expose Order-of-Operations Bugs**

❌ DON'T create simple test data:
- Flat hierarchy (no parent-child relationships)
- All IC entries at same level
- Only happy path scenarios

✅ DO create complex test data:
- Multi-level hierarchies (3+ levels)
- IC entries at DIFFERENT hierarchy levels
- Parent-child IC relationships (to test sequencing)
- Unmatched entries (to verify preservation)

**3. Apply Tolerance for Financial Amounts**

```sql
-- Allow ±$0.01 tolerance for FLOAT comparisons
WHERE ABS(snowflake_amount - expected_amount) < 0.01
```

**4. Compare Actual Data, Not Just Return Values**

Don't trust procedure return values alone:
- Procedure may return "SUCCESS" even if logic is wrong
- Verify actual database changes (BudgetLineItem rows, amounts)
- Check both WHAT was created and WHAT was NOT created (eliminations)

**5. Use Systematic Verification Queries**

Create a checklist of business logic tests:
- [ ] Row counts match expected
- [ ] Hierarchy rollup: Parent = sum of children
- [ ] Elimination: Only matched pairs = $0
- [ ] Unmatched entries preserved
- [ ] Amount totals within tolerance
- [ ] No unexpected rows created

### Automation Improvements Needed

1. **Auto-extract return values from VARIANT**
   - Parse Snowflake VARIANT return
   - Map to SQL Server OUTPUT parameters
   - Compare equivalent fields

2. **Auto-generate comparison queries**
   - Detect primary keys and generate row-by-row comparison
   - Detect amount columns and apply ±$0.01 tolerance
   - Detect date columns and normalize timezones

3. **Auto-generate verification report**
   - Template-based report generation
   - Include summary, details, and SQL for investigation
   - Highlight differences in red, matches in green

4. **NEW: Auto-detect order-of-operations bugs**
   - Identify procedures with multi-step logic (rollup, eliminate, calculate)
   - Generate test data to expose sequencing issues
   - Verify intermediate results at each step
   - Flag potential order dependencies

---

## Detailed Verification Report Template

```markdown
# Verification Report: {procedure_name}

**Date:** {YYYY-MM-DD HH:MM}
**Tester:** Claude Sonnet 4.5
**Status:** ✅ PASSED | ⚠️ PASSED WITH WARNINGS | ❌ FAILED

---

## Executive Summary

- **Total Comparisons:** {N}
- **Passed:** {X}
- **Failed:** {Y}
- **Warnings:** {Z}

**Critical Issues:** {List or "None"}

---

## 1. Schema Verification

### Tables
| Table | SQL Server | Snowflake | Columns Match | Types Match | Status |
|-------|-----------|-----------|---------------|-------------|--------|
| BudgetHeader | ✅ Exists | ✅ Exists | ✅ 15/15 | ✅ All | ✅ PASS |
| BudgetLineItem | ✅ Exists | ✅ Exists | ✅ 12/12 | ✅ All | ✅ PASS |
| ... | | | | | |

### Procedures
| Procedure | SQL Server | Snowflake | Signature Match | Return Type | Status |
|-----------|-----------|-----------|-----------------|-------------|--------|
| usp_ProcessBudgetConsolidation | ✅ Exists | ✅ Exists | ⚠️ Modified | ⚠️ VARIANT vs OUTPUT | ⚠️ WARN |

**Schema Issues:** {List or "None"}

---

## 2. Data Verification

### Row Counts (Before Execution)
| Table | SQL Server | Snowflake | Difference | Status |
|-------|-----------|-----------|------------|--------|
| FiscalPeriod | 12 | 12 | 0 | ✅ PASS |
| GLAccount | 5 | 5 | 0 | ✅ PASS |
| CostCenter | 7 | 7 | 0 | ✅ PASS |
| BudgetHeader | 1 | 1 | 0 | ✅ PASS |
| BudgetLineItem | 20 | 20 | 0 | ✅ PASS |

**Data Issues:** {List or "None"}

---

## 3. Execution Verification

### Procedure Execution

**SQL Server:**
```sql
EXEC Planning.usp_ProcessBudgetConsolidation
  @SourceBudgetHeaderID = 1,
  @ConsolidationType = 'FULL',
  ...
```
**Result:** {SUCCESS | ERROR: message}
**Duration:** {X seconds}

**Snowflake:**
```sql
CALL PLANNING.usp_ProcessBudgetConsolidation(1, 'FULL', ...)
```
**Result:** {SUCCESS | ERROR: message}
**Duration:** {Y seconds}

### Return Value Comparison

| Field | SQL Server | Snowflake | Match | Status |
|-------|-----------|-----------|-------|--------|
| TargetBudgetHeaderID | 501 | 601.0 | ✅ Both created | ✅ PASS |
| RowsProcessed | 15 | 15 | ✅ Exact | ✅ PASS |
| ErrorMessage | NULL | "" | ✅ Both empty | ✅ PASS |

---

## 4. Business Logic Verification

### 4.1 Consolidated Budget Created

| System | BudgetHeaderID | BudgetCode | Status |
|--------|---------------|------------|--------|
| SQL Server | 501 | BUD-2024-001_C_260206 | ✅ Created |
| Snowflake | 601 | BUD-2024-001_C_260206 | ✅ Created |

**Match:** ✅ Both created (different IDs expected due to IDENTITY)

### 4.2 Budget Line Items

| System | Row Count | Total Amount | Status |
|--------|-----------|--------------|--------|
| SQL Server | 15 | $225,000.00 | ✅ |
| Snowflake | 15 | $225,000.00 | ✅ |

**Match:** ✅ Row counts and totals match

### 4.3 Hierarchy Rollup Verification

| Cost Center | SQL Server Total | Snowflake Total | Difference | Status |
|-------------|-----------------|-----------------|------------|--------|
| Corporate (1) | $225,000.00 | $225,000.00 | $0.00 | ✅ PASS |
| Sales (2) | $150,000.00 | $150,000.00 | $0.00 | ✅ PASS |
| Sales West (3) | $50,000.00 | $50,000.00 | $0.00 | ✅ PASS |
| Marketing (4) | $75,000.00 | $75,000.00 | $0.00 | ✅ PASS |

**Hierarchy Check:** ✅ Corporate = Sales + Marketing ✅ Sales = Direct + Sales West

### 4.4 Elimination Logic Verification

| Metric | SQL Server | Snowflake | Match | Status |
|--------|-----------|-----------|-------|--------|
| Total IC entries | 4 | 4 | ✅ | ✅ |
| Eliminated (amount=0) | 4 | 4 | ✅ | ✅ |
| Preserved (amount≠0) | 0 | 0 | ✅ | ✅ |
| Matched pairs | 2 | 2 | ✅ | ✅ |

**Elimination Check:** ✅ Only matched pairs eliminated ✅ No unmatched entries in test data

---

## 5. Row-by-Row Comparison

### Budget Line Items (Sample)

| GLAccount | CostCenter | Period | SQL Server Amount | Snowflake Amount | Diff | Status |
|-----------|-----------|--------|-------------------|------------------|------|--------|
| 4000 | 1 | 1 | $100,000.00 | $100,000.00 | $0.00 | ✅ |
| 4000 | 2 | 1 | $150,000.00 | $150,000.00 | $0.00 | ✅ |
| 4000 | 3 | 1 | $50,000.00 | $50,000.00 | $0.00 | ✅ |
| ... | | | | | | |

**Full comparison:** {X/Y rows match}

---

## 6. Issues Found

### Critical Issues
{List or "None"}

### Warnings
{List or "None"}

### Informational
- Return type difference: OUTPUT parameters vs VARIANT (expected)
- BudgetHeaderID values differ due to IDENTITY sequences (expected)

---

## 7. SQL Queries for Investigation

### Compare Row Counts
```sql
-- SQL Server
SELECT COUNT(*) FROM Planning.BudgetLineItem WHERE BudgetHeaderID = 501;

-- Snowflake
SELECT COUNT(*) FROM PLANNING.BudgetLineItem WHERE BudgetHeaderID = 601;
```

### Compare Amount Totals
```sql
-- SQL Server
SELECT SUM(OriginalAmount + AdjustedAmount) FROM Planning.BudgetLineItem WHERE BudgetHeaderID = 501;

-- Snowflake
SELECT SUM(OriginalAmount + AdjustedAmount) FROM PLANNING.BudgetLineItem WHERE BudgetHeaderID = 601;
```

### Find Discrepancies
```sql
-- (Custom SQL based on actual differences found)
```

---

## 8. Conclusion

**Overall Status:** {✅ PASSED | ⚠️ PASSED WITH WARNINGS | ❌ FAILED}

**Summary:**
{1-2 paragraph summary of verification results}

**Recommendation:**
{APPROVED FOR PRODUCTION | REQUIRES FIXES | NOT READY}

**Next Steps:**
{List of actions needed}

---

## Sign-off

**Verified By:** Claude Sonnet 4.5
**Date:** {YYYY-MM-DD}
**Approved:** {YES | NO | PENDING}

```

---

## Future Enhancements

1. **Automated diff generation**
   - Detect discrepancies automatically
   - Generate SQL to investigate each difference
   - Provide suggested fixes

2. **Performance comparison**
   - Measure execution time in both systems
   - Compare resource usage
   - Identify performance regressions

3. **Regression testing**
   - Save verification results
   - Compare against previous runs
   - Detect new issues introduced by changes

4. **Visual diff reports**
   - Color-coded comparison tables
   - Charts for amount comparisons
   - Hierarchy visualization
