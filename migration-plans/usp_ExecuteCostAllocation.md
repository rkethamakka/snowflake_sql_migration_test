# Migration Plan: usp_ExecuteCostAllocation

## Dependencies (in order)

### Tables
| Name | Status | Notes |
|------|--------|-------|
| AllocationRule | ✅ EXISTS | Rule definitions with dependencies |
| BudgetLineItem | ✅ EXISTS | Already migrated |
| CostCenter | ✅ EXISTS | Already migrated |
| GLAccount | ✅ EXISTS | Already migrated |

### Functions
| Name | Status | Notes |
|------|--------|-------|
| fn_GetAllocationFactor | ✅ DEPLOYED | JavaScript UDF |

### Views
| Name | Status | Notes |
|------|--------|-------|
| vw_AllocationRuleTargets | ✅ EXISTS | Already migrated |

### Types
| Name | Status | Notes |
|------|--------|-------|
| AllocationResultTableType | SKIPPED | Using VARIANT instead |

### Procedure
| Name | Complexity | Status |
|------|------------|--------|
| usp_ExecuteCostAllocation | COMPLEX | ✅ DEPLOYED |

## Complexity Analysis

- Lines: 428
- Cursors: 0 (uses WHILE loop instead)
- Dynamic SQL: No
- GOTO statements: 1 (for cleanup)
- WAITFOR DELAY: 1 (throttling)
- Application locks: 2 (sp_getapplock, sp_releaseapplock)
- Temp tables: 4 (#AllocationQueue, #AllocationResults, #ProcessedRules, #RuleDependencies)
- Recursive CTE: 1 (dependency graph)
- OUTPUT parameters: 2 (@RowsAllocated, @WarningMessages)
- STRING_SPLIT: 2 calls
- STRING_AGG: 1 call
- CROSS APPLY: 2 (complex correlated subqueries)
- TRY_CONVERT: 2 calls
- MERGE statement: 1

**Recommended approach:** JavaScript stored procedure

## Patterns Detected

### 1. Application Locks (lines 98-115)
- `sp_getapplock` / `sp_releaseapplock` for concurrency control
- **Snowflake:** Use advisory locks or table-based locking

### 2. STRING_SPLIT for CSV parsing (lines 127, 175)
- Parses comma-separated rule IDs
- **Snowflake:** Use `SPLIT_TO_TABLE(str, ',')`

### 3. Recursive CTE for dependency graph (lines 138-165)
- Builds transitive closure of rule dependencies
- **Snowflake:** Recursive CTEs supported with `MAXRECURSION` → use JavaScript loop

### 4. CROSS APPLY to inline TVF (lines 170-195)
- Correlated subquery pattern
- **Snowflake:** Use LATERAL join

### 5. WAITFOR DELAY for throttling (lines 212-216)
- No direct equivalent
- **Snowflake:** JavaScript `Date` with busy-wait or skip

### 6. UPDATE with OUTPUT clause (lines 225-237)
- Captures affected rows
- **Snowflake:** Use MERGE or separate SELECT after UPDATE

### 7. STRING_AGG with ORDER BY (lines 315-322)
- **Snowflake:** `LISTAGG(col, ';') WITHIN GROUP (ORDER BY ...)`

### 8. GOTO for cleanup (line 339)
- **Snowflake:** Use try/catch/finally pattern in JavaScript

## Migration Strategy

### Phase 1: Dependencies
1. Create `AllocationRule` table
2. Create `fn_GetAllocationFactor` function (JavaScript UDF)

### Phase 2: Procedure
Convert to JavaScript stored procedure:
- Replace temp tables with JavaScript arrays or session temp tables
- Replace WHILE loop with JavaScript loop
- Replace app locks with table-based concurrency check
- Replace STRING_SPLIT with SPLIT_TO_TABLE
- Replace CROSS APPLY with LATERAL
- Use VARIANT for complex return values

## Estimated Effort

- Dependencies: 4-6 hours
- Procedure: 8-12 hours
- Testing: 2-3 hours
- **Total:** 14-21 hours

## Test Scenarios

1. **Single rule allocation** - Basic flow
2. **Multiple rules with dependencies** - Step-down processing
3. **Dry run mode** - No persistence
4. **Concurrency** - Verify locking behavior
5. **Max iterations reached** - Warning generation
6. **CSV rule list parsing** - STRING_SPLIT equivalent
