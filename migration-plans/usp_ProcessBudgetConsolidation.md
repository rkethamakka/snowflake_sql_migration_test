# Migration Plan: usp_ProcessBudgetConsolidation

## Dependencies (in order)

### Tables
| Name | Status | Notes |
|------|--------|-------|
| FiscalPeriod | TO_MIGRATE | Reference data |
| GLAccount | TO_MIGRATE | Reference data |
| CostCenter | TO_MIGRATE | Hierarchical structure |
| BudgetHeader | TO_MIGRATE | Transaction header |
| BudgetLineItem | TO_MIGRATE | Transaction detail |
| ConsolidationJournal | TO_MIGRATE | Audit log |

### Functions
| Name | Status | Notes |
|------|--------|-------|
| fn_GetHierarchyPath | TO_MIGRATE | Scalar UDF |
| tvf_ExplodeCostCenterHierarchy | TO_MIGRATE | Table-valued function |

### Views
| Name | Status | Notes |
|------|--------|-------|
| vw_BudgetConsolidationSummary | TO_MIGRATE | Reporting view |

### Procedure
| Name | Complexity | Approach |
|------|------------|----------|
| usp_ProcessBudgetConsolidation | COMPLEX | JavaScript |

## Complexity Analysis

- Lines: 510
- Cursors: 2 (FAST_FORWARD, SCROLL KEYSET)
- Dynamic SQL: Yes (sp_executesql with OUTPUT)
- OUTPUT clauses: 11
- TRY/CATCH: 2 blocks
- Recommended approach: JavaScript stored procedure

## Patterns Detected

1. **Bottom-up hierarchy cursor** (lines 229-286)
   - Traverses cost center hierarchy from leaves to root
   - Recommended: Closure table + recursive CTE

2. **SCROLL cursor for IC matching** (lines 303-345)
   - Pairs intercompany entries for elimination
   - Recommended: Self-join pattern

3. **Dynamic SQL with options** (lines 364-399)
   - Runtime SQL building based on parameters
   - Recommended: JavaScript with conditional logic

## Estimated Effort

- Dependencies: 8-12 hours
- Procedure: 12-16 hours
- Testing: 3-4 hours
- **Total:** 23-32 hours
