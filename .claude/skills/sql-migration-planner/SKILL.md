---
name: sql-migration-planner
description: Analyze a SQL Server stored procedure and produce a complete migration plan
---

# Skill: sql-migration-planner

Analyze a SQL Server stored procedure and produce a complete migration plan.

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
docker exec sqlserver /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P 'TestPass123!' -C -d FINANCIAL_PLANNING -Q "
SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = 'Planning';
SELECT ROUTINE_NAME, ROUTINE_TYPE FROM INFORMATION_SCHEMA.ROUTINES WHERE ROUTINE_SCHEMA = 'Planning';
"
```

### Step 4: Verify Source Files Exist
```bash
ls -la src/Tables/
ls -la src/Functions/
ls -la src/Views/
ls -la src/StoredProcedures/
```

### Step 5: Determine Migration Order

**Order rules:**
1. Tables with no FK dependencies first
2. Tables with FK dependencies (ordered by dependency chain)
3. Scalar functions (may be used by views)
4. Table-valued functions
5. Views (depend on tables/functions)
6. Procedures (depend on everything)

### Step 6: Assess Procedure Complexity & Choose Approach (NEW - 2026-02-06)

**CRITICAL:** Decide JavaScript vs SQL Scripting HERE, not during migration.

#### JavaScript vs SQL Scripting Decision Tree

**Use JavaScript If:**
- ✅ Procedure has CURSOR logic (especially SCROLL cursors)
- ✅ Procedure has dynamic SQL (`sp_executesql`, `EXEC(@sql)`)
- ✅ Procedure has complex procedural logic (nested loops, multiple WHILE loops)
- ✅ Procedure > 50 lines of code
- ✅ Procedure needs row-by-row iteration
- ✅ Procedure uses OUTPUT clause extensively

**Use SQL Scripting If:**
- ✅ Procedure is simple (< 50 lines)
- ✅ No cursors, all set-based logic
- ✅ No dynamic SQL
- ✅ Simple control flow (IF/ELSE, basic loops)

**Add to plan document:**
```markdown
## Recommended Approach

**Complexity Assessment:** [Simple | Moderate | Complex]
**Lines of Code:** [N lines]
**Cursors:** [None | N cursors (types: FORWARD_ONLY / SCROLL)]
**Dynamic SQL:** [Yes | No]

**Recommended Implementation:** [JavaScript | SQL Scripting]

**Justification:** [Explanation]
```

### Step 7: Identify Challenges & Patterns

Scan procedure for SQL Server-specific features and recommend patterns:

| SQL Server Feature | Snowflake Approach | Pattern/Skill Reference |
|-------------------|-------------------|------------------------|
| `CURSOR (sequential)` | Set-based query | Convert to INSERT/UPDATE with GROUP BY |
| `CURSOR SCROLL` (matching pairs) | Self-join | Self-join pattern for matching/pairing |
| `CURSOR (bottom-up hierarchy)` | Recursive CTE + closure table | Closure table pattern for hierarchy rollup |
| `DECLARE @T TABLE` | Temp tables | `CREATE TEMPORARY TABLE` |
| `TRY...CATCH` | EXCEPTION blocks | `EXCEPTION WHEN OTHER THEN ...` |
| `OUTPUT inserted/deleted` | RETURNING clause (limited) | Snowflake MERGE has no OUTPUT - use preview table |
| `MERGE` | Supported but no OUTPUT | Create preview table before MERGE for audit |
| `sp_executesql` | JavaScript `snowflake.execute()` | Use JavaScript for dynamic SQL |
| `SAVE TRANSACTION` | Not supported | Restructure to avoid partial rollbacks |
| `HIERARCHYID` | VARCHAR path or ParentID | Use ParentID + recursive CTE instead of string parsing |
| `ROWVERSION` | Remove | Use streams or change tracking |
| `SPARSE` | Regular columns | Just remove SPARSE keyword |
| `XML` | VARIANT | Parse XML to JSON, store as VARIANT |
| `FILESTREAM` | Stage references | Use Snowflake stages |
| `@@ROWCOUNT` | `SQLROWCOUNT` (SQL) or `getNumRowsAffected()` (JS) | Different in each approach |
| `@@ERROR` | EXCEPTION handling | Use EXCEPTION blocks |

**Add pattern detection to plan:**

```markdown
## Detected Patterns

### Pattern 1: Bottom-Up Hierarchy Cursor
**Location:** Lines 229-285
**Pattern:** Cursor ordered by NodeLevel DESC, accumulates child subtotals
**Recommended Fix:** Closure table with recursive CTE
**Reference:** sql-migration skill, Cursor Conversion Pattern 2
**Effort:** 2-3 hours

### Pattern 2: SCROLL Cursor for Matching
**Location:** Lines 108-344
**Pattern:** SCROLL cursor with FETCH RELATIVE, finds offsetting pairs
**Recommended Fix:** Self-join pattern
**Reference:** sql-migration skill, Cursor Conversion Pattern 3
**Effort:** 1-2 hours
```

### Step 8: Plan Test Data & Verification (NEW - 2026-02-06)

**CRITICAL:** Plan testing BEFORE starting migration, not after.

**Add to plan document:**

```markdown
## Test Data Plan

### Required Tables
- FiscalPeriod: 12 rows (all periods for fiscal year)
- GLAccount: 10-20 rows (revenue, expense, intercompany accounts)
- CostCenter: 15-20 rows (3-4 level hierarchy)
- BudgetHeader: 2-3 budgets (APPROVED status)
- BudgetLineItem: 50-100 rows (spread across cost centers and accounts)

### Edge Cases to Test
- [ ] Empty budget (no line items)
- [ ] Single-level hierarchy (no rollup)
- [ ] Deep hierarchy (4+ levels)
- [ ] Matched intercompany pairs (should eliminate)
- [ ] Unmatched intercompany entries (should preserve)
- [ ] Zero amounts
- [ ] Negative amounts
- [ ] NULL values in optional fields

### Test Scenarios
1. **Happy Path:** Standard budget with 3-level hierarchy and matched IC pairs
2. **Edge Case 1:** Empty budget
3. **Edge Case 2:** Deep hierarchy (4 levels)
4. **Edge Case 3:** Unmatched IC entries

### Data Generation Approach
- **Tool:** Use test-data-generator skill (NOT manual creation)
- **Systems:** Generate for BOTH SQL Server and Snowflake
- **Validation:** Row counts must match between systems
```

```markdown
## Verification Plan

### Verification Approach
- **Tool:** Use sql-migration-verify skill (NOT manual comparison)
- **Level:** Full (schema + data + execution + results)

### Success Criteria
- [ ] Procedure compiles successfully
- [ ] Procedure executes without errors
- [ ] Row counts match (±0 tolerance)
- [ ] Amount totals match (±$0.01 tolerance)
- [ ] Hierarchy rollup correct (parent = sum of children)
- [ ] Elimination logic correct (only matched pairs = 0)
- [ ] Execution time < 2x SQL Server (performance acceptable)

### Metrics to Compare
| Metric | Tolerance | Critical? |
|--------|-----------|-----------|
| Row count: BudgetLineItem | Exact (0) | Yes |
| Sum of amounts | ±$0.01 | Yes |
| Hierarchy totals | ±$0.01 | Yes |
| Elimination pairs | Exact (0) | Yes |
| Execution time | < 2x SQL Server | No (informational) |

### Verification Report
- **Location:** `test/results/{procedure}_verification.md`
- **Generated by:** sql-migration-verify skill
- **Review:** Manual review of generated report required
```

### Step 9: Generate Plan Document

Write to: `migration-plans/<procedure_name>.md`

Include:
- **Executive Summary** (complexity, recommended approach, estimated effort)
- **Current State** (what exists in each system)
- **Dependencies** with source file verification
- **Migration Order** (numbered sequence)
- **Complexity Assessment** (JavaScript vs SQL Scripting decision)
- **Detected Patterns** (cursors, hierarchies, eliminations) ← NEW
- **Challenges Table** with Snowflake approach
- **Test Data Plan** ← NEW
- **Verification Plan** ← NEW
- **Estimated Effort**
- **Risk Assessment** ← NEW

---

## Example Output

See: `migration-plans/usp_ProcessBudgetConsolidation.md`

---

## Execution Log

| Date | Procedure | Plan File | Status |
|------|-----------|-----------|--------|
| 2026-02-05 | usp_ProcessBudgetConsolidation | ✅ Generated | Ready for migration |

---

## Lessons Learned (2026-02-06)

### From usp_ProcessBudgetConsolidation Migration:

1. **JavaScript vs SQL Scripting Should Be Decided in Planning**
   - **What Happened:** Plan didn't specify approach, team tried SQL Scripting first, failed, switched to JavaScript
   - **Impact:** Wasted 4 hours on failed attempt
   - **Fix:** Add complexity assessment and explicit recommendation to plan
   - **Status:** ✅ Added Step 6 (Assess Complexity & Choose Approach)

2. **Cursor Patterns Should Be Identified Upfront**
   - **What Happened:** Plan mentioned "CURSOR → refactor" but didn't specify WHICH pattern
   - **Impact:** Team had to figure out closure table pattern during migration
   - **Fix:** Detect specific cursor patterns (hierarchy, matching, etc.) and recommend specific solutions
   - **Status:** ✅ Added pattern detection to Step 7

3. **Test Data Plan Was Missing**
   - **What Happened:** No test data plan in migration plan, team created manual test data (error-prone)
   - **Impact:** Wrong column types, only created data in Snowflake, wasted 2 hours
   - **Fix:** Require test data plan in every migration plan
   - **Status:** ✅ Added Step 8 (Plan Test Data & Verification)

4. **Verification Approach Not Documented**
   - **What Happened:** No verification plan, team did manual smoke test instead of using skills
   - **Impact:** No side-by-side comparison, no verification report, low confidence
   - **Fix:** Require verification plan with success criteria
   - **Status:** ✅ Added verification plan to Step 8

5. **Gap Analysis Too Generic**
   - **What Happened:** Plan identified "CURSOR" but didn't analyze WHICH cursor or impact
   - **Impact:** Discovered critical logic gaps during migration (hierarchy rollup, elimination pairing)
   - **Fix:** Deeper analysis of cursor logic, identify specific patterns
   - **Status:** ✅ Added detailed pattern detection

### Continuous Improvement

**Each migration plan should:**
- ✅ Assess complexity and recommend approach (JavaScript vs SQL Scripting)
- ✅ Detect specific patterns (not just generic "cursor")
- ✅ Include test data plan with edge cases
- ✅ Include verification plan with success criteria
- ✅ Reference specific cursor conversion patterns from sql-migration skill
- ✅ Include risk assessment

**Future Enhancements:**
1. **Automated pattern detection** - Scan procedure and auto-identify patterns
2. **Effort estimation** - Based on lines of code, cursor count, complexity
3. **Risk scoring** - HIGH/MEDIUM/LOW risk for each detected pattern
4. **Template selection** - Choose JavaScript or SQL Scripting template based on assessment
