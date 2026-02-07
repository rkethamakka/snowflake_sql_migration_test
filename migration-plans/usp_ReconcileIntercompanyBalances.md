# Migration Plan: usp_ReconcileIntercompanyBalances

## Summary

| Attribute | Value |
|-----------|-------|
| Lines | 373 |
| Complexity | COMPLEX |
| Approach | JavaScript stored procedure |
| Cursors | 0 |
| Dynamic SQL | No |

## Dependencies (in order)

### Tables
| Name | Status | Notes |
|------|--------|-------|
| BudgetLineItem | EXISTS | |
| GLAccount | EXISTS | |
| CostCenter | EXISTS | |
| ConsolidationJournal | EXISTS | |
| ConsolidationJournalLine | TO_CHECK | May need migration |
| FiscalPeriod | EXISTS | |

### Functions
| Name | Status | Notes |
|------|--------|-------|
| fn_GetHierarchyPath | EXISTS | |

### Views
| Name | Status | Notes |
|------|--------|-------|
| vw_BudgetConsolidationSummary | EXISTS | |

## Complexity Analysis

### SQL Server Features Used
| Feature | Lines | Snowflake Equivalent |
|---------|-------|---------------------|
| OPENXML / sp_xml_preparedocument | 77-95 | PARSE_JSON or XMLGET |
| sp_xml_removedocument | 95 | Not needed |
| FOR XML PATH (complex nested) | 246-315 | OBJECT_CONSTRUCT + arrays |
| HASHBYTES SHA2_256 | 140 | SHA2(text, 256) |
| FORMAT function | 195-200 | TO_CHAR |
| CROSS APPLY | 108-110, 125-127 | LATERAL |
| Table variables with indexes | 47-63 | Temp tables |
| SCOPE_IDENTITY() | 243 | lastval() or RETURNING |
| OUTPUT parameters | 31-33 | Returns VARIANT |

### Key Patterns

1. **XML Input Parsing** (lines 77-95)
   - Uses legacy OPENXML with sp_xml_preparedocument
   - Snowflake: Convert to JSON input + PARSE_JSON, or use XMLGET if keeping XML

2. **XML Report Output** (lines 246-315)
   - Complex nested FOR XML PATH with attributes
   - Snowflake: Return as VARIANT with nested objects/arrays

3. **Intercompany Matching** (lines 100-145)
   - CROSS APPLY for entity extraction from CostCenterCode
   - Hash-based matching with HASHBYTES
   - Snowflake: Use LATERAL + SHA2 function

4. **Auto-adjustment Creation** (lines 210-250)
   - Creates journal entries for unreconciled pairs
   - Uses SCOPE_IDENTITY for JournalID
   - Snowflake: Use RETURNING clause or sequence

## Migration Approach

### Simplifications
1. Convert XML input to JSON (more Snowflake-native)
2. Return VARIANT object instead of XML output
3. Use temp tables instead of table variables
4. Replace OPENXML with PARSE_JSON + LATERAL FLATTEN

### JavaScript Structure
```javascript
// 1. Parse entity list from JSON input (or use all if null)
// 2. Create temp tables for intercompany pairs and details
// 3. Identify intercompany pairs with variance calculation
// 4. Perform detailed matching (EXACT, PARTIAL, UNMATCHED)
// 5. Update reconciliation status
// 6. Auto-create adjustments if requested
// 7. Build result object with statistics and details
// 8. Return VARIANT with full reconciliation report
```

### Parameters Mapping
| SQL Server | Snowflake |
|------------|-----------|
| @BudgetHeaderID | BUDGET_HEADER_ID |
| @ReconciliationDate | RECONCILIATION_DATE |
| @EntityCodes XML | ENTITY_CODES_JSON VARCHAR |
| @ToleranceAmount | TOLERANCE_AMOUNT |
| @TolerancePercent | TOLERANCE_PERCENT |
| @AutoCreateAdjustments | AUTO_CREATE_ADJUSTMENTS |
| @ReconciliationReportXML OUTPUT | Returns in VARIANT |
| @UnreconciledCount OUTPUT | Returns in VARIANT |
| @TotalVarianceAmount OUTPUT | Returns in VARIANT |

## Estimated Effort

| Task | Hours |
|------|-------|
| Dependencies | 0.5 (ConsolidationJournalLine check) |
| Procedure translation | 6-8 |
| Testing | 2-3 |
| **Total** | **8-12 hours** |

## Verification Strategy

1. Create test data with known intercompany pairs
2. Include pairs within tolerance and outside tolerance
3. Compare:
   - Number of pairs identified
   - Reconciliation status distribution
   - Total variance amounts
   - Auto-adjustment counts (if enabled)
