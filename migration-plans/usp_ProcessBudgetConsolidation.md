# Migration Plan: usp_ProcessBudgetConsolidation

**Generated:** 2026-02-06
**Source:** `src/StoredProcedures/usp_ProcessBudgetConsolidation.sql`
**Target:** Snowflake `FINANCIAL_PLANNING.PLANNING` schema

---

## Executive Summary

**Complexity:** COMPLEX
**Lines of Code:** 510
**Recommended Approach:** JavaScript stored procedure
**Estimated Effort:** 28-39 hours

**Key Challenges:**
- 2 cursors (FAST_FORWARD and SCROLL KEYSET)
- 3 table variables with indexes
- Dynamic SQL with sp_executesql
- XML processing → JSON/VARIANT

---

## Dependencies (in order)

### Tables (6)

| Name | Status | Notes |
|------|--------|-------|
| FiscalPeriod | TO_MIGRATE | Reference data |
| GLAccount | TO_MIGRATE | SPARSE column |
| CostCenter | TO_MIGRATE | Self-referencing hierarchy |
| BudgetHeader | TO_MIGRATE | XML → VARIANT |
| BudgetLineItem | TO_MIGRATE | All FKs |
| ConsolidationJournal | TO_MIGRATE | Audit table |

### Functions (2)

| Name | Type | Status |
|------|------|--------|
| fn_GetHierarchyPath | Scalar | TO_MIGRATE |
| tvf_ExplodeCostCenterHierarchy | TVF | TO_MIGRATE |

### Views (1)

| Name | Status |
|------|--------|
| vw_BudgetConsolidationSummary | TO_MIGRATE |

### Procedure (1)

| Name | Complexity | Approach |
|------|------------|----------|
| usp_ProcessBudgetConsolidation | COMPLEX | JavaScript |

---

## Complexity: COMPLEX

- Lines: 510
- Cursors: 2 (FAST_FORWARD + SCROLL KEYSET)
- Table variables: 3 (with indexes)
- Dynamic SQL: Yes
- Patterns: Hierarchy rollup + IC elimination

---

## Estimated Effort

| Phase | Hours |
|-------|-------|
| Tables (6) | 6-8 |
| Functions (2) | 4-6 |
| View (1) | 2-3 |
| Procedure | 10-14 |
| Testing | 6-8 |
| **Total** | **28-39** |

---

## Next Steps

1. `/sql-migration usp_ProcessBudgetConsolidation`
2. `/test-data-generator usp_ProcessBudgetConsolidation`
3. `/sql-migration-verify usp_ProcessBudgetConsolidation`

**Status:** Ready for migration
