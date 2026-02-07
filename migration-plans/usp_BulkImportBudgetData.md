# Migration Plan: usp_BulkImportBudgetData

## Dependencies

| Name | Status | Notes |
|------|--------|-------|
| BudgetHeader | ✅ EXISTS | |
| BudgetLineItem | ✅ EXISTS | |
| GLAccount | ✅ EXISTS | |
| CostCenter | ✅ EXISTS | |
| FiscalPeriod | ✅ EXISTS | |

## Complexity Analysis

- Lines: 519
- BULK INSERT: Yes (file-based)
- TVP input: Yes
- Dynamic SQL: Yes
- OUTPUT params: 3

**Approach:** JavaScript stored procedure with COPY INTO pattern

## Key Translations

| SQL Server | Snowflake |
|------------|-----------|
| BULK INSERT | COPY INTO from stage |
| TVP parameter | Temp table input |
| FORMAT FILE | FILE_FORMAT object |
| IDENTITY_INSERT | Explicit sequence |
