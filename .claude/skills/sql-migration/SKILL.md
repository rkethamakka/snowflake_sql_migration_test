---
name: sql-migration
description: Migrate SQL Server objects to Snowflake (Snowflake only, does not touch SQL Server)
---

# Skill: sql-migration

Migrate SQL Server objects to Snowflake. **Snowflake only** — does not touch SQL Server.

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
    7. Update migration plan status
```

### Step 2: Check If Object Exists
```bash
# For tables
/Users/ravikiran/Library/Python/3.9/bin/snow sql -q "
  SELECT COUNT(*) as cnt FROM FINANCIAL_PLANNING.INFORMATION_SCHEMA.TABLES 
  WHERE TABLE_SCHEMA = 'PLANNING' AND TABLE_NAME = '<OBJECT_NAME>'
"

# For functions
/Users/ravikiran/Library/Python/3.9/bin/snow sql -q "
  SHOW USER FUNCTIONS LIKE '<FUNCTION_NAME>' IN FINANCIAL_PLANNING.PLANNING
"

# For views
/Users/ravikiran/Library/Python/3.9/bin/snow sql -q "
  SHOW VIEWS LIKE '<VIEW_NAME>' IN FINANCIAL_PLANNING.PLANNING
"

# For procedures
/Users/ravikiran/Library/Python/3.9/bin/snow sql -q "
  SHOW PROCEDURES LIKE '<PROCEDURE_NAME>' IN FINANCIAL_PLANNING.PLANNING
"
```

### Step 3: Read Source & Translate

Apply rules in order:
1. **Data Types** → `rules/datatypes.md`
2. **Syntax** → `rules/syntax.md`
3. **Procedures** → `rules/procedures.md` (for functions/procedures)

### Step 4: Deploy to Snowflake
```bash
/Users/ravikiran/Library/Python/3.9/bin/snow sql -f snowflake/<Category>/<Object>.sql
```

### Step 5: Verify Deployment
```bash
# Confirm object now exists
/Users/ravikiran/Library/Python/3.9/bin/snow sql -q "DESCRIBE TABLE PLANNING.<table>"
```

---

## Re-Migration

If user explicitly requests re-migration (e.g., "re-migrate" or "force migrate"):
- Use `CREATE OR REPLACE` syntax
- Print warning: "Re-migrating: <object> (will replace existing)"

Otherwise, if object exists:
- Print: "Skipping: <object> already exists in Snowflake"
- Print: "Use 'force migrate' to replace existing objects"

---

## Rules Reference

| Rule File | Use For |
|-----------|---------|
| `rules/datatypes.md` | INT, VARCHAR, DECIMAL, DATETIME, HIERARCHYID, etc. |
| `rules/syntax.md` | IDENTITY, ROWVERSION, SPARSE, XML, computed columns |
| `rules/procedures.md` | Cursors, TRY-CATCH, table variables, OUTPUT clause |

---

## Messages

| Scenario | Message |
|----------|---------|
| Object exists | `⏭️ Skipping: <object> already exists in Snowflake` |
| Migrating | `🔄 Migrating: <object>` |
| Success | `✅ Migrated: <object>` |
| Failed | `❌ Failed: <object> - <error>` |
| Force migrate | `⚠️ Re-migrating: <object> (replacing existing)` |

---

## Execution Log

| Date | Object | Type | Existed | Action | Status |
|------|--------|------|---------|--------|--------|
| 2026-02-05 | FiscalPeriod | Table | No | Migrated | ✅ |
| 2026-02-05 | GLAccount | Table | No | Migrated | ✅ |
| 2026-02-05 | CostCenter | Table | No | Migrated | ✅ |
| 2026-02-05 | BudgetHeader | Table | No | Migrated | ✅ |
| 2026-02-05 | BudgetLineItem | Table | No | Migrated | ✅ |
| 2026-02-05 | ConsolidationJournal | Table | No | Migrated | ✅ |

---

## Post-Deployment Validation (NEW - 2026-02-06)

**IMPORTANT:** After deploying each object, validate it works correctly.

### For Tables
```sql
-- Verify table exists
DESCRIBE TABLE PLANNING.<table_name>;

-- Verify column count and names
SELECT COUNT(*) as column_count FROM FINANCIAL_PLANNING.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PLANNING' AND TABLE_NAME = '<TABLE_NAME>';

-- Verify constraints exist
SHOW PRIMARY KEYS IN TABLE PLANNING.<table_name>;
SHOW FOREIGN KEYS IN TABLE PLANNING.<table_name>;

-- Try inserting a sample row (then delete)
INSERT INTO PLANNING.<table_name> (<columns>) VALUES (<test_values>);
DELETE FROM PLANNING.<table_name> WHERE <test_condition>;
```

### For Views
```sql
-- Verify view exists
DESCRIBE VIEW PLANNING.<view_name>;

-- Execute sample query
SELECT * FROM PLANNING.<view_name> LIMIT 1;

-- Verify column count matches source
SELECT COUNT(*) FROM FINANCIAL_PLANNING.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'PLANNING' AND TABLE_NAME = '<VIEW_NAME>';
```

### For Functions
```sql
-- Verify function exists
SHOW USER FUNCTIONS LIKE '<FUNCTION_NAME>' IN FINANCIAL_PLANNING.PLANNING;

-- Execute with sample parameters
SELECT PLANNING.<function_name>(<test_params>);

-- Verify return type
DESCRIBE FUNCTION PLANNING.<function_name>(<param_types>);
```

### For Stored Procedures
```sql
-- Verify procedure exists
SHOW PROCEDURES LIKE '<PROCEDURE_NAME>' IN FINANCIAL_PLANNING.PLANNING;

-- Verify signature
DESCRIBE PROCEDURE PLANNING.<procedure_name>(<param_types>);

-- Execute with test parameters (if safe)
CALL PLANNING.<procedure_name>(<test_params>);
```

**If any validation fails:** Stop migration, investigate and fix before proceeding.

---

## Syntax Pattern Detection (NEW - 2026-02-06)

**Detect common syntax errors BEFORE deployment:**

### LET Syntax Validation

**WRONG:**
```sql
LET variable TYPE;
SELECT value INTO variable FROM table;
```

**RIGHT:**
```sql
LET variable TYPE := (SELECT value FROM table);
```

**Detection Rule:** If converting T-SQL DECLARE + SELECT INTO pattern, auto-fix to LET := syntax.

### Subquery in DECLARE Section

**WRONG:**
```sql
DECLARE
  budget_count INTEGER := (SELECT COUNT(*) FROM BudgetHeader);  -- Not allowed in DECLARE
BEGIN
  ...
END;
```

**RIGHT (SQL Scripting):**
```sql
DECLARE
  budget_count INTEGER;  -- Declare without initializer
BEGIN
  budget_count := (SELECT COUNT(*) FROM BudgetHeader);  -- Assign in BEGIN block
  ...
END;
```

**RIGHT (JavaScript):**
```javascript
var budgetCount = snowflake.execute({
  sqlText: "SELECT COUNT(*) FROM BudgetHeader"
});
```

### VARCHAR Length Limits

**Detection Rule:** Warn if VARCHAR length > 16777216 (Snowflake max).

SQL Server `VARCHAR(MAX)` → Snowflake `VARCHAR(16777216)`

### JavaScript Procedure Parameter Types

**IMPORTANT:** JavaScript procedures have different type requirements.

| SQL Server | SQL Scripting | JavaScript Procedure |
|------------|--------------|---------------------|
| `@ID INT` | `ID INTEGER` | `ID FLOAT` |
| `@Code VARCHAR(50)` | `CODE VARCHAR(50)` | `CODE STRING` |
| `@Flag BIT` | `FLAG BOOLEAN` | `FLAG BOOLEAN` |

**Detection Rule:** If migrating to JavaScript, suggest FLOAT for numeric parameters instead of INTEGER.

---

## JavaScript vs SQL Scripting Decision Tree (NEW - 2026-02-06)

**CRITICAL:** Choose the right approach EARLY to avoid wasted work.

### Use JavaScript If:
- ✅ Procedure has CURSOR logic (especially SCROLL cursors)
- ✅ Procedure has dynamic SQL (`sp_executesql`, `EXEC(@sql)`)
- ✅ Procedure has complex procedural logic (nested loops, multiple WHILE loops)
- ✅ Procedure > 50 lines
- ✅ Procedure needs row-by-row iteration
- ✅ Procedure uses temp tables extensively (easier in JavaScript)

### Use SQL Scripting If:
- ✅ Procedure is simple (< 50 lines)
- ✅ No cursors, all set-based logic
- ✅ No dynamic SQL
- ✅ Simple control flow (IF/ELSE, basic loops)

### Example: usp_ProcessBudgetConsolidation
**Original:** 510 lines, 2 SCROLL cursors, complex hierarchy logic, eliminations
**Decision:** **JavaScript** (complex cursors + >50 lines)
**Outcome:** ✅ Correct choice, procedure works

**Lesson:** Should have chosen JavaScript from the start, not after failed SQL Scripting attempt.

---

## Common Migration Errors (NEW - 2026-02-06)

### Error 1: LET Syntax Errors
**Symptom:** Compilation fails with "Unexpected 'SELECT'"
**Cause:** Using T-SQL DECLARE + SELECT INTO pattern
**Fix:** Use `LET variable := (SELECT ...)` syntax
**Prevention:** Auto-detect and convert this pattern

### Error 2: Column Length Mismatch
**Symptom:** "String too long" runtime errors
**Cause:** Snowflake VARCHAR(50) vs SQL Server NVARCHAR(100)
**Fix:** Review all VARCHAR lengths in DDL
**Prevention:** Compare source and target DDL before deployment

### Error 3: Missing Schema Prefix
**Symptom:** "Object not found" errors
**Cause:** Snowflake requires schema prefix: `PLANNING.table` not just `table`
**Fix:** Add schema prefix to all object references
**Prevention:** Use find/replace during translation

### Error 4: Case Sensitivity
**Symptom:** Column not found errors
**Cause:** Snowflake uppercases unquoted identifiers by default
**Fix:** Use consistent casing or quoted identifiers
**Prevention:** Document casing strategy in migration plan

### Error 5: @@ROWCOUNT Not Replaced
**Symptom:** Compilation fails on @@ROWCOUNT
**Cause:** SQL Server variable not supported in Snowflake
**Fix SQL Scripting:** Use `SQLROWCOUNT` system variable
**Fix JavaScript:** Use `getNumRowsAffected()` method
**Prevention:** Add to syntax pattern detection

---

## Cursor Conversion Patterns (NEW - 2026-02-06)

### Pattern 1: Simple Sequential Cursor → Set-Based Query

**SQL Server:**
```sql
DECLARE cur CURSOR FOR SELECT ID, Name FROM Table;
OPEN cur;
FETCH NEXT FROM cur INTO @ID, @Name;
WHILE @@FETCH_STATUS = 0
BEGIN
  -- Simple operation per row
  INSERT INTO Target VALUES (@ID, UPPER(@Name));
  FETCH NEXT FROM cur INTO @ID, @Name;
END;
CLOSE cur;
DEALLOCATE cur;
```

**Snowflake (Set-Based):**
```sql
INSERT INTO Target SELECT ID, UPPER(Name) FROM Table;
```

### Pattern 2: Bottom-Up Hierarchy Cursor → Closure Table

**SQL Server:**
```sql
DECLARE cur CURSOR FOR
  SELECT CostCenterID FROM CostCenter ORDER BY NodeLevel DESC;  -- Bottom-up
OPEN cur;
WHILE @@FETCH_STATUS = 0
BEGIN
  -- Calculate subtotal for current node
  SELECT @Subtotal = SUM(Amount) WHERE CostCenterID = @ID;
  -- Add child subtotals
  SELECT @Subtotal += SUM(ChildSubtotal) WHERE ParentID = @ID;
  UPDATE Hierarchy SET Subtotal = @Subtotal WHERE ID = @ID;
  FETCH NEXT;
END;
```

**Snowflake (Closure Table with Recursive CTE):**
```sql
-- Build closure table of ancestor-descendant relationships
CREATE TEMP TABLE hierarchy_paths AS
WITH RECURSIVE hierarchy_tree AS (
  SELECT CostCenterID, ParentCostCenterID, CostCenterID as descendant_id, 0 as distance
  FROM CostCenter
  UNION ALL
  SELECT cc.CostCenterID, cc.ParentCostCenterID, ht.descendant_id, ht.distance + 1
  FROM CostCenter cc
  JOIN hierarchy_tree ht ON cc.CostCenterID = ht.ParentCostCenterID
)
SELECT * FROM hierarchy_tree;

-- Sum all descendant amounts into each ancestor
SELECT
  hp.CostCenterID as ancestor_id,
  SUM(bli.Amount) as total_with_descendants
FROM hierarchy_paths hp
JOIN BudgetLineItem bli ON hp.descendant_id = bli.CostCenterID
GROUP BY hp.CostCenterID;
```

### Pattern 3: SCROLL Cursor for Matching/Pairing → Self-Join

**SQL Server:**
```sql
DECLARE cur CURSOR SCROLL FOR SELECT ID, Amount FROM Entries ORDER BY Amount;
OPEN cur;
FETCH NEXT FROM cur INTO @ID1, @Amt1;
WHILE @@FETCH_STATUS = 0
BEGIN
  FETCH NEXT FROM cur INTO @ID2, @Amt2;  -- Look ahead
  IF @Amt1 + @Amt2 = 0  -- Found matching pair
    UPDATE Entries SET Eliminated = 1 WHERE ID IN (@ID1, @ID2);
  FETCH PRIOR;  -- Look back
  FETCH NEXT;
END;
```

**Snowflake (Self-Join):**
```sql
UPDATE Entries e
SET Eliminated = TRUE
WHERE EXISTS (
  SELECT 1
  FROM Entries e2
  WHERE e2.Amount = -e.Amount
    AND e2.ID <> e.ID
);
```

**Lesson:** SCROLL cursors usually indicate matching/pairing logic → self-join pattern

---

## Reference to Verification Workflow (NEW - 2026-02-06)

**After migration, ALWAYS run verification workflow:**

1. Generate test data: Use `test-data-generator` skill (not manual creation)
2. Execute procedure: Run in BOTH SQL Server and Snowflake
3. Compare results: Use `sql-migration-verify` skill (not manual comparison)
4. Review report: Check `test/results/{procedure}_verification.md`

**DO NOT:**
- ❌ Create test data manually
- ❌ Only test Snowflake in isolation
- ❌ Do manual comparison of results
- ❌ Skip verification step

**DO:**
- ✅ Use test-data-generator skill
- ✅ Execute on both systems with identical inputs
- ✅ Use sql-migration-verify skill for automated comparison
- ✅ Generate and review verification report

---

## Lessons Learned Summary (2026-02-06)

### From usp_ProcessBudgetConsolidation Migration:

1. **JavaScript vs SQL Scripting Decision**
   - Lesson: Should be decided in PLANNING phase, not during migration
   - Impact: Wasted 4 hours on failed SQL Scripting attempt
   - Fix: Add decision tree to sql-migration-planner

2. **Cursor Conversion Complexity**
   - Lesson: Cursors need specific patterns (closure table, self-join, etc.)
   - Impact: Initial simple aggregation was wrong, caused incorrect results
   - Fix: Document cursor patterns in this skill

3. **Post-Deployment Validation**
   - Lesson: Should test compilation immediately after deployment
   - Impact: Syntax errors discovered late
   - Fix: Add validation steps after each object deployment

4. **LET Syntax Errors**
   - Lesson: T-SQL DECLARE + SELECT INTO doesn't work in Snowflake
   - Impact: Multiple compilation failures
   - Fix: Auto-detect and convert this pattern

5. **Reference to Skills Workflow**
   - Lesson: Skills should reference each other (test-data-generator, sql-migration-verify)
   - Impact: User did manual work instead of using designed workflow
   - Fix: Add explicit workflow reference at end of this skill
