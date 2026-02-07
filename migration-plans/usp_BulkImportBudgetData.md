# Migration Plan: usp_BulkImportBudgetData

## Summary

| Attribute | Value |
|-----------|-------|
| Lines | 519 |
| Complexity | COMPLEX |
| Approach | JavaScript stored procedure |
| Cursors | 0 |
| Dynamic SQL | Yes (BULK INSERT, OPENQUERY, staging tables) |

## Dependencies (in order)

### Tables
| Name | Status | Notes |
|------|--------|-------|
| BudgetHeader | EXISTS | Base table |
| BudgetLineItem | EXISTS | Target table for imports |
| GLAccount | EXISTS | Lookup for AccountNumber |
| CostCenter | EXISTS | Lookup for CostCenterCode |
| FiscalPeriod | EXISTS | Lookup for Year/Month |

### Types
| Name | Status | Notes |
|------|--------|-------|
| BudgetLineItemTableType | NO_MIGRATE | TVP → temp table or stage |

### Functions
| Name | Status | Notes |
|------|--------|-------|
| fn_GetHierarchyPath | EXISTS | Not used in this procedure |

### Procedure
| Name | Complexity | Approach |
|------|------------|----------|
| usp_BulkImportBudgetData | COMPLEX | JavaScript |

## Complexity Analysis

### SQL Server Features Used
| Feature | Lines | Snowflake Equivalent |
|---------|-------|---------------------|
| BULK INSERT | 95-120 | COPY INTO from stage |
| FORMAT FILE | 99 | File format objects |
| OPENQUERY (linked server) | 148-157 | External tables or Data Sharing |
| Table-valued parameter | 127-135 | Temp table input |
| MERGE upsert | 303-340 | Snowflake MERGE |
| OUTPUT clause | 335-339, 360-365 | Separate SELECT after INSERT |
| Dynamic SQL (sp_executesql) | Multiple | snowflake.execute() |
| XML output | 420-465 | OBJECT_CONSTRUCT (VARIANT) |
| STRING_AGG | 285 | LISTAGG |
| @@ROWCOUNT | Multiple | getNumRowsAffected() |

### Import Modes
| Mode | SQL Server | Snowflake Approach |
|------|------------|-------------------|
| FILE | BULK INSERT | COPY INTO from @stage |
| TVP | From table-valued parameter | From temp table |
| STAGING_TABLE | Dynamic SQL SELECT | Direct SELECT |
| LINKED_SERVER | OPENQUERY | External table or skip |

## Patterns Detected

1. **Multi-source import** (lines 80-160)
   - 4 different import sources (FILE, TVP, STAGING_TABLE, LINKED_SERVER)
   - Each requires different Snowflake handling
   - Recommend: Focus on STAGING_TABLE mode (most portable)

2. **Lookup resolution** (lines 165-195)
   - Resolves codes to IDs (AccountNumber → GLAccountID, etc.)
   - Pattern works in Snowflake with UPDATE...FROM

3. **Validation with error tracking** (lines 200-295)
   - Inserts errors into temp table
   - Aggregates with STRING_AGG
   - Pattern works with minor syntax changes

4. **Batch processing loop** (lines 300-395)
   - TOP (@BatchSize) for chunked processing
   - MERGE for upsert
   - OUTPUT clause for tracking
   - Recommend: Snowflake MERGE, remove OUTPUT (not supported same way)

5. **XML result output** (lines 420-465)
   - FOR XML PATH patterns
   - Recommend: OBJECT_CONSTRUCT to build VARIANT

## Migration Approach

### Simplifications
1. **Remove LINKED_SERVER mode** - No Snowflake equivalent without external tables
2. **Convert FILE mode** - Use Snowflake stage (assume data already staged)
3. **Remove TVP** - Accept temp table name instead
4. **Remove OUTPUT clause** - Use INSERT...RETURNING or separate tracking

### JavaScript Structure
```javascript
// Main sections:
// 1. Load data into staging (based on mode)
// 2. Resolve lookups
// 3. Validate
// 4. Process in batches with MERGE
// 5. Return VARIANT result
```

### Parameters Mapping
| SQL Server | Snowflake | Notes |
|------------|-----------|-------|
| @ImportSource | IMPORT_SOURCE | FILE, STAGING_TABLE only |
| @FilePath | STAGE_PATH | @stage/file.csv format |
| @BudgetData (TVP) | STAGING_TABLE_NAME | Use temp table |
| @StagingTableName | STAGING_TABLE_NAME | Same |
| @TargetBudgetHeaderID | TARGET_BUDGET_HEADER_ID | Same |
| @ValidationMode | VALIDATION_MODE | STRICT, LENIENT, NONE |
| @DuplicateHandling | DUPLICATE_HANDLING | REJECT, UPDATE, SKIP |
| @BatchSize | BATCH_SIZE | Same |
| @ImportResults (XML) | RETURNS VARIANT | JSON output |

## Estimated Effort

| Task | Hours |
|------|-------|
| Dependencies | 0 (all exist) |
| Procedure translation | 6-8 |
| Testing | 2-3 |
| **Total** | **8-11 hours** |

## Verification Strategy

1. Create test CSV data with valid and invalid rows
2. Stage file in Snowflake
3. Run import with STRICT validation
4. Verify:
   - Correct rows imported
   - Invalid rows rejected with proper error messages
   - Duplicate handling works
   - Result object contains summary

## Notes

- LINKED_SERVER mode will not be supported (no equivalent)
- FILE mode requires pre-staged data
- Consider adding STAGE_NAME parameter for Snowflake flexibility
