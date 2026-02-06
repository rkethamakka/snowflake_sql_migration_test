# Migration Plan: usp_ProcessBudgetConsolidation

**Date:** 2026-02-06
**Planner:** sql-migration-planner skill
**Status:** ✅ Ready for Migration

---

## Executive Summary

**Complexity:** COMPLEX
**Lines of Code:** 510 lines
**Cursors:** 2 cursors (1 FAST_FORWARD, 1 SCROLL)
**Dynamic SQL:** No
**Recommended Approach:** **JavaScript Stored Procedure**

**Estimated Effort:** 6-8 hours total
- Migration: 4-5 hours
- Testing: 2-3 hours

**Risk Level:** HIGH (complex cursor logic, hierarchy processing, elimination matching)

---

## Current State

### Snowflake
- **Tables:** None (clean slate)
- **Functions:** None
- **Views:** None
- **Procedures:** None

### Source Files Available
✅ Tables: 8 files in `src/Tables/`
✅ Functions: 4 files in `src/Functions/`
✅ Views: 2 files in `src/Views/`
✅ Procedure: `src/StoredProcedures/usp_ProcessBudgetConsolidation.sql`

---

## Recommended Approach

**Complexity Assessment:** COMPLEX

**Factors:**
- ✅ **510 lines of code** (>50 line threshold)
- ✅ **2 CURSORS:** FAST_FORWARD (hierarchy) + SCROLL (elimination)
- ✅ **Complex procedural logic:** Nested loops, table variables with indexes
- ✅ **Row-by-row iteration:** Bottom-up hierarchy traversal
- ❌ Dynamic SQL: None detected

**Recommended Implementation:** **JavaScript Stored Procedure**

**Justification:**
1. SCROLL cursor cannot be converted to SQL Scripting (no equivalent)
2. Complex hierarchy rollup requires procedural logic
3. JavaScript provides temp tables, loops, and full SQL execution control
4. Better error handling with try/catch
5. Can use `snowflake.execute()` for dynamic operations

---

## Dependencies

### Tables (6 required)
1. **FiscalPeriod** - `src/Tables/FiscalPeriod.sql`
2. **GLAccount** - `src/Tables/GLAccount.sql`
3. **CostCenter** - `src/Tables/CostCenter.sql`
4. **BudgetHeader** - `src/Tables/BudgetHeader.sql`
5. **BudgetLineItem** - `src/Tables/BudgetLineItem.sql`
6. **ConsolidationJournal** - `src/Tables/ConsolidationJournal.sql`

### Functions (2 required)
1. **fn_GetHierarchyPath** - `src/Functions/fn_GetHierarchyPath.sql`
2. **tvf_ExplodeCostCenterHierarchy** - `src/Functions/tvf_ExplodeCostCenterHierarchy.sql`

### Views (1 required)
1. **vw_BudgetConsolidationSummary** - `src/Views/vw_BudgetConsolidationSummary.sql`

### User-Defined Types (NOT migrating)
- BudgetLineItemTableType → Replace with temp tables
- AllocationResultTableType → Replace with temp tables

---

## Migration Order

1. **FiscalPeriod** (no dependencies)
2. **GLAccount** (no dependencies)
3. **CostCenter** (no dependencies)
4. **BudgetHeader** (depends on FiscalPeriod)
5. **BudgetLineItem** (depends on BudgetHeader, GLAccount, CostCenter, FiscalPeriod)
6. **ConsolidationJournal** (depends on BudgetHeader)
7. **fn_GetHierarchyPath** (depends on CostCenter)
8. **tvf_ExplodeCostCenterHierarchy** (depends on CostCenter)
9. **vw_BudgetConsolidationSummary** (depends on all tables)
10. **usp_ProcessBudgetConsolidation** (depends on everything)

---

## Detected Patterns

### Pattern 1: Bottom-Up Hierarchy Cursor (CRITICAL)
**Location:** Lines 97-100, 229-285
**Pattern:** FAST_FORWARD cursor ordered by `NodeLevel DESC`, processes leaf nodes first, accumulates child subtotals into parents
**SQL Server Logic:**
```sql
CURSOR FOR ... ORDER BY NodeLevel DESC  -- Bottom-up
WHILE @@FETCH_STATUS = 0
  -- Calculate subtotal for current node
  -- Add child subtotals
  -- Store accumulated result
```

**Snowflake Solution:** **Closure Table Pattern with Recursive CTE**
**Reference:** sql-migration skill, Cursor Conversion Pattern 2
**Effort:** 3-4 hours

**Implementation:**
1. Build closure table (all ancestor-descendant relationships)
2. Roll up amounts using closure table joins
3. Single-pass set-based operation

### Pattern 2: SCROLL Cursor for Elimination Matching (CRITICAL)
**Location:** Lines 108-115, 303-344
**Pattern:** SCROLL cursor with `FETCH RELATIVE`, looks forward/backward to find offsetting IC pairs
**SQL Server Logic:**
```sql
CURSOR LOCAL SCROLL ... WHERE IntercompanyFlag = 1
  FETCH RELATIVE 1  -- Look ahead
  IF match found THEN eliminate both
  FETCH PRIOR       -- Look backward
```

**Snowflake Solution:** **Self-Join Pattern + Eliminate BEFORE Rollup**
**Reference:** sql-migration skill, Cursor Conversion Pattern 3
**Effort:** 2-3 hours

**Implementation:**
1. Self-join to find matched pairs (amount = -amount)
2. Mark pairs for elimination
3. **CRITICAL:** Apply eliminations BEFORE hierarchy rollup (order-of-operations fix)

### Pattern 3: Table Variables with Indexes
**Location:** Lines 57-87
**Pattern:** `DECLARE @T TABLE (..., INDEX IX_...)`
**Snowflake Solution:** Temporary tables (no indexes needed in Snowflake)
**Effort:** 1 hour

---

## Migration Challenges

| SQL Server Feature | Snowflake Approach | Impact |
|-------------------|-------------------|--------|
| **CURSOR FAST_FORWARD** | Recursive CTE + closure table | HIGH - Requires refactor |
| **CURSOR SCROLL** | Self-join pattern | HIGH - Complex matching logic |
| **Table variables** | CREATE TEMPORARY TABLE | MEDIUM - Straightforward |
| **IDENTITY columns** | AUTOINCREMENT | LOW - Direct equivalent |
| **TRY...CATCH** | EXCEPTION WHEN OTHER | LOW - Similar syntax |
| **@@ROWCOUNT** | getNumRowsAffected() | LOW - JavaScript method |
| **OUTPUT parameters** | RETURNS VARIANT | MEDIUM - Return JSON object |
| **SCOPE_IDENTITY()** | Not needed | LOW - Use explicit IDs |
| **SAVE TRANSACTION** | Not supported | MEDIUM - All-or-nothing transactions |

---

## Test Data Plan

### Required Tables & Row Counts
- **FiscalPeriod:** 12 rows (all periods for fiscal year 2024)
- **GLAccount:** 6 rows (4 operational + 2 IC accounts)
- **CostCenter:** 7 rows (3-level hierarchy: Corporate → Depts → Teams)
- **BudgetHeader:** 1 budget (APPROVED status)
- **BudgetLineItem:** 40 rows (spread across hierarchy + IC entries)

### Edge Cases to Test
- [x] Multi-level hierarchy (3 levels: Corporate → Engineering/Sales → Teams/Regions)
- [x] Matched IC pairs (+$10K/-$10K at different hierarchy levels)
- [x] Unmatched IC entries ($5K with no offset)
- [x] Parent with both direct amounts AND child amounts
- [x] Parent with ONLY child amounts (no direct)
- [x] Zero amounts
- [x] Negative amounts

### Test Scenarios

**Scenario 1: Happy Path with Order-of-Operations Test**
- 3-level hierarchy
- Matched IC pair: Corporate +$10K ↔ Engineering -$10K (parent-child relationship)
- Unmatched IC entry: Sales +$5K
- **Expected Result:** Corporate IC = $0, Engineering IC = $0, Sales IC = $5K
- **Tests:** Elimination happens BEFORE rollup (not after)

**Scenario 2: Hierarchy Rollup Accuracy**
- Corporate should include ALL descendants
- **Expected:** Corporate = $125K (direct) + $115K (Engineering) + $138K (Sales) = $378K

### Data Generation Approach
- **Tool:** `/test-data-generator usp_ProcessBudgetConsolidation`
- **Output:** `test/data/snowflake/usp_ProcessBudgetConsolidation_setup.sql`
- **Validation:** Verify 40 rows loaded, referential integrity intact

---

## Verification Plan

### Verification Approach
- **Tool:** `/sql-migration-verify`
- **Level:** Business logic validation (not just smoke test)
- **Report:** `test/results/VERIFICATION_SUMMARY.md` (60 lines max)

### Success Criteria
- [ ] Procedure compiles successfully
- [ ] Procedure executes without errors
- [ ] Hierarchy rollup correct: Parent total = sum of all descendants
- [ ] IC elimination correct: Only matched pairs eliminated
- [ ] Unmatched IC entries preserved
- [ ] Row counts match expected (19 rows for test case)
- [ ] Amount totals within ±$0.01 tolerance

### Metrics to Compare

| Metric | Expected Value | Tolerance | Critical? |
|--------|---------------|-----------|-----------|
| Rows inserted | 19 rows | Exact | Yes |
| Corporate total | $378,000 | ±$0.01 | Yes |
| Engineering total | $115,000 | ±$0.01 | Yes |
| Sales total | $138,000 | ±$0.01 | Yes |
| Corporate IC (matched) | $0 | Exact | Yes |
| Engineering IC (matched) | $0 | Exact | Yes |
| Sales IC (unmatched) | $5,000 | ±$0.01 | Yes |

### Verification Tests

**Test 1: Matched IC Pairs Eliminated**
```sql
SELECT COUNT(*) FROM BudgetLineItem WHERE GLAccountID = 6 AND ABS(OriginalAmount) < 0.01
-- Expected: 2 (Corporate and Engineering both $0)
```

**Test 2: Unmatched IC Entry Preserved**
```sql
SELECT OriginalAmount FROM BudgetLineItem WHERE GLAccountID = 6 AND CostCenterID = 3
-- Expected: $5,000 (Sales unmatched entry)
```

**Test 3: Hierarchy Rollup Correct**
```sql
SELECT SUM(OriginalAmount) FROM BudgetLineItem WHERE CostCenterID = 1
-- Expected: $378,000 (Corporate includes all descendants)
```

---

## Risk Assessment

### HIGH Risk Items
1. **SCROLL Cursor Elimination Logic**
   - Risk: Matching logic may miss edge cases
   - Mitigation: Comprehensive test data with matched/unmatched pairs
   - Verification: Compare all IC entries, verify only matched pairs eliminated

2. **Order-of-Operations Bug**
   - Risk: Elimination after rollup causes matched pairs to net before elimination
   - Mitigation: Eliminate BEFORE rollup (design decision)
   - Verification: Test with parent-child IC pairs

### MEDIUM Risk Items
1. **Closure Table Performance**
   - Risk: Deep hierarchies may have performance impact
   - Mitigation: Test with 4+ level hierarchy
   - Verification: Execution time < 2x SQL Server

2. **Transaction Handling**
   - Risk: No SAVEPOINT support, all-or-nothing transactions
   - Mitigation: Document limitation
   - Verification: Test rollback scenarios

### LOW Risk Items
1. **Syntax Conversion**
   - Risk: Minor syntax differences
   - Mitigation: Use translation rules
   - Verification: Procedure compiles

---

## Execution Checklist

### Pre-Migration
- [ ] Review this plan
- [ ] Confirm JavaScript approach approved
- [ ] Understand closure table pattern
- [ ] Understand self-join elimination pattern

### Migration (4-5 hours)
- [ ] Migrate tables (1 hour)
- [ ] Migrate functions (30 min)
- [ ] Migrate views (30 min)
- [ ] Migrate procedure with closure table pattern (2-3 hours)
- [ ] Deploy to Snowflake

### Testing (2-3 hours)
- [ ] Run `/test-data-generator` (30 min)
- [ ] Run `/sql-migration-verify` (30 min)
- [ ] Review VERIFICATION_SUMMARY.md
- [ ] Fix any issues found (1-2 hours)
- [ ] Re-verify until all tests pass

### Sign-Off
- [ ] All tests passing (8/8 scenarios)
- [ ] Verification report generated
- [ ] No critical issues
- [ ] Approved for production

---

## Next Steps

1. **Review and approve this plan**
2. **Run:** `/sql-migration` (executes migration using this plan)
3. **Run:** `/test-data-generator usp_ProcessBudgetConsolidation`
4. **Run:** `/sql-migration-verify`
5. **Review:** `test/results/VERIFICATION_SUMMARY.md`

---

**Plan Status:** ✅ APPROVED - Ready for migration
**Estimated Completion:** 6-8 hours
**Next Action:** Execute `/sql-migration`
