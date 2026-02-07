# Migration Plan: usp_GenerateRollingForecast

## Dependencies

| Name | Status | Notes |
|------|--------|-------|
| BudgetHeader | ✅ EXISTS | |
| BudgetLineItem | ✅ EXISTS | |
| FiscalPeriod | ✅ EXISTS | |
| fn_GetAllocationFactor | ✅ EXISTS | |

## Complexity Analysis

- Lines: 440
- Dynamic PIVOT: Yes
- Statistical functions: Yes (PERCENTILE_CONT)
- JSON parsing: Yes
- Window functions: Complex

**Approach:** JavaScript stored procedure

## Key Translations

| SQL Server | Snowflake |
|------------|-----------|
| FOR XML PATH | LISTAGG |
| ##GlobalTemp | Session temp table |
| OPENJSON | PARSE_JSON |
| Dynamic PIVOT | PIVOT or conditional agg |
