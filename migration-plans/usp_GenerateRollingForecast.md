# Migration Plan: usp_GenerateRollingForecast

## Summary

| Attribute | Value |
|-----------|-------|
| Lines | 440 |
| Complexity | COMPLEX |
| Approach | JavaScript stored procedure |
| Cursors | 0 |
| Dynamic SQL | Yes (PIVOT) |

## Dependencies (in order)

### Tables
| Name | Status | Notes |
|------|--------|-------|
| BudgetHeader | EXISTS | |
| BudgetLineItem | EXISTS | |
| FiscalPeriod | EXISTS | |
| CostCenter | EXISTS | |
| GLAccount | EXISTS | |

### Functions
| Name | Status | Notes |
|------|--------|-------|
| fn_GetAllocationFactor | EXISTS | Not directly used |
| tvf_GetBudgetVariance | TO_CHECK | May need migration |

### Views
| Name | Status | Notes |
|------|--------|-------|
| vw_BudgetConsolidationSummary | TO_CHECK | May need migration |

## Complexity Analysis

### SQL Server Features Used
| Feature | Lines | Snowflake Equivalent |
|---------|-------|---------------------|
| Global temp table (##) | 42-60 | Regular temp table |
| OPENJSON | 79-86 | PARSE_JSON + LATERAL FLATTEN |
| PERCENTILE_CONT window | 175-181 | Same syntax |
| FOR XML PATH string concat | 353-360 | LISTAGG |
| Dynamic PIVOT | 350-380 | Snowflake PIVOT or JavaScript |
| FOR JSON | 395-405 | OBJECT_CONSTRUCT |
| SCOPE_IDENTITY() | 335 | lastval() or RETURNING |
| LAG/LEAD | 165-171 | Same syntax |
| Complex window frames | 130-165 | Same syntax |

### Forecast Methods
| Method | Description |
|--------|-------------|
| WEIGHTED_AVERAGE | Exponential decay weights |
| LINEAR_TREND | Regression-based trend |
| EXPONENTIAL | Compound growth |
| SEASONAL | Factor-based seasonal |

## Patterns Detected

1. **Global temp table workspace** (lines 42-60)
   - Uses ##ForecastWorkspace for cross-session visibility
   - Snowflake: Use regular temporary table (session-scoped)

2. **JSON parsing with OPENJSON** (lines 79-86)
   - Parses seasonality factors from JSON array
   - Snowflake: PARSE_JSON + LATERAL FLATTEN

3. **Statistical window functions** (lines 130-185)
   - Moving averages, percentiles, LAG/LEAD
   - Works similarly in Snowflake

4. **Dynamic PIVOT** (lines 350-380)
   - Builds column list dynamically
   - Snowflake: Use conditional aggregation or JavaScript

5. **FOR JSON output** (lines 395-405)
   - Returns accuracy metrics as JSON
   - Snowflake: OBJECT_CONSTRUCT

## Migration Approach

### Simplifications
1. Remove dynamic PIVOT - use fixed output format
2. Replace OPENJSON with PARSE_JSON + LATERAL FLATTEN
3. Use OBJECT_CONSTRUCT for JSON output
4. Use regular temp tables instead of global

### JavaScript Structure
```javascript
// 1. Parse parameters and seasonality JSON
// 2. Create temp table for workspace
// 3. Load historical data with window calculations
// 4. Calculate trend components
// 5. Generate forecast periods
// 6. Create target budget header
// 7. Insert forecast line items
// 8. Return result with accuracy metrics
```

### Parameters Mapping
| SQL Server | Snowflake |
|------------|-----------|
| @BaseBudgetHeaderID | BASE_BUDGET_HEADER_ID |
| @HistoricalPeriods | HISTORICAL_PERIODS |
| @ForecastPeriods | FORECAST_PERIODS |
| @ForecastMethod | FORECAST_METHOD |
| @SeasonalityJSON | SEASONALITY_JSON |
| @GrowthRateOverride | GROWTH_RATE_OVERRIDE |
| @ConfidenceLevel | CONFIDENCE_LEVEL |
| @OutputFormat | OUTPUT_FORMAT |
| @TargetBudgetHeaderID OUTPUT | Returns in VARIANT |
| @ForecastAccuracyMetrics OUTPUT | Returns in VARIANT |

## Estimated Effort

| Task | Hours |
|------|-------|
| Dependencies | 1 (verify existing) |
| Procedure translation | 8-10 |
| Testing | 3-4 |
| **Total** | **12-15 hours** |

## Verification Strategy

1. Create base budget with 12 months of historical data
2. Run forecast with WEIGHTED_AVERAGE method
3. Compare:
   - Target budget header created
   - Forecast line items count
   - Total forecast amounts
   - Accuracy metrics structure
