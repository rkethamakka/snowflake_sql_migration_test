# Migration Plan: usp_PerformFinancialClose

## Summary

| Attribute | Value |
|-----------|-------|
| Lines | 521 |
| Complexity | COMPLEX |
| Type | Orchestration/Workflow |
| Approach | JavaScript stored procedure |
| Nested Procs | 3 (Consolidation, Allocation, Reconciliation) |

## Dependencies (in order)

### Tables
| Name | Status | Notes |
|------|--------|-------|
| FiscalPeriod | EXISTS | |
| BudgetHeader | EXISTS | |
| BudgetLineItem | EXISTS | |
| ConsolidationJournal | EXISTS | |
| CostCenter | EXISTS | |

### Procedures (Called)
| Name | Status | Notes |
|------|--------|-------|
| usp_ProcessBudgetConsolidation | EXISTS | Already migrated |
| usp_ExecuteCostAllocation | EXISTS | Already migrated |
| usp_ReconcileIntercompanyBalances | EXISTS | Already migrated |

## Complexity Analysis

### SQL Server Features Used
| Feature | Lines | Snowflake Equivalent |
|---------|-------|---------------------|
| Nested EXEC with OUTPUT | 187-200, 225-240 | CALL with VARIANT return |
| Named transactions | 295-330 | BEGIN/COMMIT (no names) |
| DISABLE/ENABLE TRIGGER | 302, 330 | Not applicable |
| sp_send_dbmail | 365-380 | External notification (skip) |
| FOR SYSTEM_TIME | 160-170 | Time Travel (different syntax) |
| GOTO statement | 140, 390 | Control flow refactor |
| Table variables with OUTPUT | 56-65 | Temp tables |
| @@TRANCOUNT checks | 315 | Not needed |
| FOR XML PATH (complex) | 400-450 | OBJECT_CONSTRUCT |

### Workflow Steps
1. **Period Validation** - Check period exists, not closed, prior closed
2. **Create Snapshot** - Temporal query for cost centers
3. **Budget Consolidation** - Call usp_ProcessBudgetConsolidation
4. **Cost Allocations** - Call usp_ExecuteCostAllocation
5. **IC Reconciliation** - Call usp_ReconcileIntercompanyBalances
6. **Lock Period** - Update FiscalPeriod.IsClosed, lock budgets
7. **Notifications** - Send email (skip in Snowflake)

## Migration Approach

### Simplifications
1. Remove GOTO - use structured control flow
2. Remove trigger disable/enable - not applicable
3. Skip email notifications - external system
4. Replace temporal query with regular snapshot
5. Nested proc calls return VARIANT - extract values

### JavaScript Structure
```javascript
// 1. Initialize result tracking
// 2. Validate period (exists, not closed, prior closed)
// 3. Find active budget for period
// 4. Call consolidation if requested
// 5. Call allocations if requested
// 6. Call reconciliation if requested
// 7. Lock period (update FiscalPeriod, BudgetHeader)
// 8. Build and return result VARIANT
```

### Parameters Mapping
| SQL Server | Snowflake |
|------------|-----------|
| @FiscalPeriodID | FISCAL_PERIOD_ID |
| @CloseType | CLOSE_TYPE |
| @RunConsolidation | RUN_CONSOLIDATION |
| @RunAllocations | RUN_ALLOCATIONS |
| @RunReconciliation | RUN_RECONCILIATION |
| @SendNotifications | (removed) |
| @NotificationRecipients | (removed) |
| @ForceClose | FORCE_CLOSE |
| @ClosingUserID | CLOSING_USER_ID |
| @CloseResults OUTPUT | Returns VARIANT |
| @OverallStatus OUTPUT | Returns in VARIANT |

## Estimated Effort

| Task | Hours |
|------|-------|
| Dependencies | 0 (all migrated) |
| Procedure translation | 6-8 |
| Testing | 2-3 |
| **Total** | **8-11 hours** |

## Verification Strategy

1. Create test period (not closed)
2. Create test budget for that period
3. Run with all steps enabled
4. Verify:
   - Period marked as closed
   - Budget marked as locked
   - All sub-procedures called successfully
   - Result contains step summaries
