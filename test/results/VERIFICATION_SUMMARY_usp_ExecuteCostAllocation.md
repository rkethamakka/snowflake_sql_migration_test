# Verification Summary: usp_ExecuteCostAllocation

## Status: ✅ VERIFIED

**Date:** 2026-02-06  
**Procedure:** usp_ExecuteCostAllocation (428 lines)

## Test Results

| Metric | SQL Server | Snowflake |
|--------|-----------|-----------|
| Rules Processed | 3 | 3 |
| Rows Allocated | 12 | 12 |
| Source Rows | 7 | 7 |

## Allocated Amounts (Both Systems Match)

| Target | Account | Amount |
|--------|---------|--------|
| ENG | 6000 | $7,500 x2 |
| ENG | 6100 | $10,000 x2 |
| ENG | 9000 | $5,000 |
| SALES | 6000 | $40,000 + $7,500 x2 |
| SALES | 6100 | $55,000 + $10,000 x2 |
| SALES | 9000 | $5,000 |

## Allocation Rules

| Rule | Source CC | Target CC | % |
|------|-----------|-----------|---|
| CORP-ENG-SAL | CORP | ENG | 50% |
| CORP-SALES-SAL | CORP | SALES | 50% |
| MKT-SALES-OPEX | MKT | SALES | 100% |

## Bugs Fixed

### SQL Server (_fixed.sql versions created)

1. **usp_ExecuteCostAllocation_fixed.sql**
   - OUTPUT clause inserted `RemainingAmount` (e.g. $20,000) into `AllocationPercentage` column (DECIMAL 8,6, max 99.999999)
   - Caused arithmetic overflow error
   - Fix: Removed buggy OUTPUT clause (real allocation happens in subsequent INSERT)

2. **fn_GetAllocationFactor_fixed.sql**
   - Missing handler for 'FIXED' allocation basis
   - Function returned 0, causing $0 allocations
   - Fix: Added FIXED case that looks up target percentage from vw_AllocationRuleTargets

3. **Schema fixes** (columns added to test tables)
   - `CostCenter.AllocationWeight`
   - `BudgetLineItem.IsAllocated`
   - `BudgetLineItem.AllocationSourceLineID`
   - `BudgetLineItem.LastModifiedDateTime`
   - Renamed `AllocationPercent` → `AllocationPercentage`

### Snowflake

1. **View vw_AllocationRuleTargets**
   - Was using hierarchy-based target lookup (children of source)
   - Fix: Added `TARGETCOSTCENTERID` column to AllocationRule, recreated view to use explicit targets

2. **Procedure usp_ExecuteCostAllocation**
   - Was querying `WHERE PARENTCOSTCENTERID = source` for targets
   - Fix: Changed to use `rule.targetCostCenterId` from AllocationRule table

3. **Data alignment**
   - Test data had different source amounts
   - Fix: Synced BudgetLineItem data to match SQL Server

## Key Differences

| Aspect | SQL Server | Snowflake |
|--------|-----------|-----------|
| Target specification | XML in TargetSpecification column | TARGETCOSTCENTERID column |
| View implementation | XML parsing with .nodes() | Simple JOIN |
| Account filtering | Pattern matching (LIKE) | Explicit ID or NULL |

## Files Modified

- `src/StoredProcedures/usp_ExecuteCostAllocation_fixed.sql` - Bug fixes
- `src/Functions/fn_GetAllocationFactor_fixed.sql` - Added FIXED basis
- `snowflake/procedures/usp_ExecuteCostAllocation.sql` - Target lookup fix
- `snowflake/views/vw_AllocationRuleTargets.sql` - Recreated with explicit targets
