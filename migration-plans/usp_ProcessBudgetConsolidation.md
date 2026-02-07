# Migration Plan: usp_ProcessBudgetConsolidation

**Generated:** 2026-02-06  
**Source:** `src/StoredProcedures/usp_ProcessBudgetConsolidation.sql`  
**Target:** Snowflake `FINANCIAL_PLANNING.PLANNING` schema

---

## Executive Summary

**Complexity:** COMPLEX  
**Lines of Code:** 510  
**Recommended Approach:** JavaScript stored procedure with temporary tables  
**Estimated Effort:** 28-39 hours

**Key Challenges:**
- 2 cursors (FAST_FORWARD and SCROLL KEYSET with RELATIVE/PRIOR positioning)
- 3 table variables with indexes
- Dynamic SQL with sp_executesql and table variable scope
- Named transaction savepoints (SAVE TRANSACTION)
- OUTPUT clauses capturing inserted rows
- XML processing for ExtendedProperties
- @@TRANCOUNT, @@ROWCOUNT, @@FETCH_STATUS patterns

---

## Dependencies (in order)

### Tables (6)

| Name | Status | Notes |
|------|--------|-------|
| FiscalPeriod | TO_MIGRATE | No dependencies, reference data |
| GLAccount | TO_MIGRATE | Has SPARSE column (StatutoryAccountCode) |
| CostCenter | TO_MIGRATE | Self-referencing hierarchy (ParentCostCenterID) |
| BudgetHeader | TO_MIGRATE | XML column (ExtendedProperties) → VARIANT |
| BudgetLineItem | TO_MIGRATE | Foreign keys to all above tables |
| ConsolidationJournal | TO_MIGRATE | Audit/logging table |

### Functions (2)

| Name | Type | Status | Notes |
|------|------|--------|-------|
| fn_GetHierarchyPath | Scalar UDF | TO_MIGRATE | Builds hierarchy path string |
| tvf_ExplodeCostCenterHierarchy | Table-valued | TO_MIGRATE | Called with CROSS APPLY (line 218) |

### Views (1)

| Name | Status | Notes |
|------|--------|-------|
| vw_BudgetConsolidationSummary | TO_MIGRATE | Depends on tables |

### Procedure (1)

| Name | Complexity | Approach |
|------|------------|----------|
| usp_ProcessBudgetConsolidation | COMPLEX | JavaScript |

---

## Complexity Analysis

**Code Metrics:**
- Lines: 510
- Cursors: 2
  - HierarchyCursor (lines 97-100): LOCAL FAST_FORWARD READ_ONLY
  - EliminationCursor (lines 108-119): LOCAL SCROLL KEYSET, updateable
- Table variables with indexes: 3
  - @ProcessingLog (lines 57-66): IDENTITY, 1 index
  - @HierarchyNodes (lines 68-76): 1 index
  - @ConsolidatedAmounts (lines 78-87): PRIMARY KEY
- Dynamic SQL: Yes (lines 364-399, sp_executesql with OUTPUT parameters)
- Transaction handling: BEGIN TRY/CATCH, named savepoints (lines 201, 301)
- OUTPUT clauses: 3 (lines 167, 423-428)
- XML processing: Yes (lines 180-186, 381-382)

**Complexity Rating:** COMPLEX
- Multiple cursors with different behaviors (FAST_FORWARD vs SCROLL)
- Complex cursor positioning logic (FETCH RELATIVE, FETCH PRIOR)
- Table variables referenced in dynamic SQL
- Business logic: hierarchy rollup + intercompany elimination

---

## Patterns Detected

### 1. **Bottom-Up Hierarchy Cursor** (lines 229-286)

**Pattern:**
```sql
DECLARE HierarchyCursor CURSOR LOCAL FAST_FORWARD READ_ONLY FOR
    SELECT NodeID, NodeLevel, ParentNodeID
    FROM @HierarchyNodes
    ORDER BY NodeLevel DESC, NodeID;  -- Bottom-up

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Calculate subtotal for current node
    -- Add child subtotals (already processed)
    -- Update node as processed
    -- MERGE into consolidated amounts
END
```

**Snowflake Solution:**
- **Option A (Recommended):** Recursive CTE for bottom-up aggregation
- **Option B:** JavaScript procedure with ordered result set iteration
- **Complexity:** HIGH

---

### 2. **SCROLL Cursor with RELATIVE/PRIOR** (lines 303-345)

**Pattern:**
```sql
DECLARE EliminationCursor CURSOR LOCAL SCROLL KEYSET FOR ...

WHILE @@FETCH_STATUS = 0
BEGIN
    FETCH RELATIVE 1 FROM EliminationCursor ...  -- Look ahead
    IF @@FETCH_STATUS = 0 AND @OffsetAmount = -@ElimAmount
        -- Found matching pair, eliminate
    ELSE
        FETCH PRIOR FROM EliminationCursor ...  -- Move back
    
    FETCH NEXT FROM EliminationCursor ...
END
```

**Snowflake Solution:**
- LEAD/LAG window functions to detect adjacent offsetting entries
- Self-join pattern with ROW_NUMBER()
- JavaScript array manipulation for complex lookahead/lookback logic
- **Complexity:** HIGH

---

### 3. **Table Variables with Indexes** (lines 57-87)

**Pattern:**
```sql
DECLARE @ConsolidatedAmounts TABLE (
    GLAccountID INT NOT NULL,
    ...
    PRIMARY KEY (GLAccountID, CostCenterID, FiscalPeriodID)
);
```

**Snowflake Solution:**
```sql
CREATE OR REPLACE TEMPORARY TABLE ConsolidatedAmounts (
    GLAccountID NUMBER(38,0) NOT NULL,
    ...
    PRIMARY KEY (GLAccountID, CostCenterID, FiscalPeriodID)
);
```
- **Complexity:** MEDIUM (straightforward translation)

---

### 4. **Dynamic SQL with Table Variables** (lines 364-399)

**Pattern:**
```sql
SET @DynamicSQL = N'
    UPDATE ca
    SET FinalAmount = ca.ConsolidatedAmount - ca.EliminationAmount
    FROM @ConsolidatedAmounts ca  -- Table variable in scope!
    ...
';
EXEC sp_executesql @DynamicSQL, @ParamDefinition, @RowCountOUT = @AllocationRowCount OUTPUT;
```

**Snowflake Solution:**
- JavaScript with string manipulation for dynamic SQL
- Use snowflake.execute() with temp tables (not table variables)
- Track row count via stmt.getNumRowsAffected()
- **Complexity:** MEDIUM

---

### 5. **OUTPUT Clause** (lines 167, 423-428)

**Pattern:**
```sql
INSERT INTO Planning.BudgetHeader (...)
OUTPUT inserted.BudgetHeaderID, inserted.BudgetCode INTO @InsertedHeaders
SELECT ...
```

**Snowflake Solution:**
- Use separate query after INSERT to retrieve generated IDs
- Or use JavaScript with RETURNING clause (limited support)
- **Complexity:** LOW

---

### 6. **XML Processing** (lines 180-186, 381-382)

**Pattern:**
```sql
-- XML construction
CAST('<Root>' + ... AS XML)

-- XML querying
@ProcessingOptions.value('(/Options/IncludeZeroBalances)[1]', 'BIT')
```

**Snowflake Solution:**
```sql
-- JSON construction (VARIANT type)
OBJECT_CONSTRUCT('Root', OBJECT_CONSTRUCT(...))

-- JSON querying
GET_PATH(processing_options, 'Options.IncludeZeroBalances')::BOOLEAN
```
- **Complexity:** MEDIUM

---

## Snowflake Translation Guidelines

### Data Type Mappings

| SQL Server | Snowflake | Notes |
|------------|-----------|-------|
| INT | NUMBER(38,0) | No native INT |
| BIGINT | NUMBER(38,0) | Same as INT |
| DECIMAL(19,4) | NUMBER(19,4) | Direct |
| NVARCHAR(MAX) | VARCHAR | No length limit |
| VARCHAR(20) | VARCHAR(20) | Direct |
| BIT | BOOLEAN | Direct |
| DATETIME2 | TIMESTAMP_NTZ | No timezone |
| UNIQUEIDENTIFIER | VARCHAR(36) | Use UUID_STRING() |
| XML | VARIANT | Store as JSON |

### Function Mappings

| SQL Server | Snowflake |
|------------|-----------|
| SYSUTCDATETIME() | CURRENT_TIMESTAMP() |
| GETDATE() | CURRENT_DATE() |
| NEWID() | UUID_STRING() |
| FORMAT(date, 'yyyyMMdd') | TO_CHAR(date, 'YYYYMMDD') |
| @@ROWCOUNT | stmt.getNumRowsAffected() (JS) |
| @@TRANCOUNT | Track manually in JavaScript |
| @@FETCH_STATUS | Use JavaScript while(rs.next()) |
| ERROR_NUMBER() | SQLCODE in exception |
| ERROR_MESSAGE() | SQLERRM in exception |

---

## Estimated Effort

| Phase | Task | Hours |
|-------|------|-------|
| **Phase 1** | Migrate 6 tables (DDL + indexes + constraints) | 6-8 |
| **Phase 2** | Migrate 2 functions (scalar + TVF → JS UDF) | 4-6 |
| **Phase 3** | Migrate 1 view | 2-3 |
| **Phase 4** | Migrate procedure (JavaScript translation) | 10-14 |
| **Testing** | Unit + integration + comparison tests | 6-8 |
| **Total** | | **28-39 hours** |

---

## Risk Assessment

### High Risk
1. SCROLL cursor with RELATIVE/PRIOR positioning - no direct equivalent
2. Table variables in dynamic SQL scope - requires temp tables
3. Complex cursor logic for elimination matching

### Medium Risk
1. XML → JSON conversion - different syntax
2. Named savepoints - limited Snowflake support
3. Error handling model differences

### Low Risk
1. Table creation - straightforward conversion
2. Basic CRUD operations
3. Scalar function mappings

---

## Testing Strategy

### Unit Tests (per dependency)
- Each table: Insert/select/update/delete
- Each function: Various input parameters
- Each view: Row count and column validation

### Integration Tests
1. Hierarchy rollup: Verify parent = sum(children)
2. Elimination matching: Verify paired entries eliminated
3. Allocation calculation: Verify FinalAmount = Consolidated - Elimination
4. Transaction rollback: Verify partial rollback on error

### Comparison Tests (SQL Server vs Snowflake)
- Identical test data loaded to both systems
- Execute procedure in both
- Compare:
  - Return values (target ID, rows processed)
  - Row counts in output tables
  - Amount totals and distributions
  - Hierarchy subtotals

---

## Next Steps

1. **Execute:** `/sql-migration usp_ProcessBudgetConsolidation`
2. **Test Data:** `/test-data-generator usp_ProcessBudgetConsolidation`
3. **Verify:** `/sql-migration-verify usp_ProcessBudgetConsolidation`

**Status:** Ready for migration
