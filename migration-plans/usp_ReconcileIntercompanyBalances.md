# Migration Plan: usp_ReconcileIntercompanyBalances

## Dependencies

| Name | Status | Notes |
|------|--------|-------|
| BudgetLineItem | ✅ EXISTS | |
| GLAccount | ✅ EXISTS | |
| CostCenter | ✅ EXISTS | |
| fn_GetHierarchyPath | ✅ EXISTS | |

## Complexity Analysis

- Lines: 373
- XML operations: Heavy (OPENXML, FOR XML PATH)
- HASHBYTES: Yes
- Temp tables: 2

**Approach:** JavaScript stored procedure

## Key Translations

| SQL Server | Snowflake |
|------------|-----------|
| OPENXML | PARSE_XML / XMLGET |
| FOR XML PATH | OBJECT_CONSTRUCT |
| HASHBYTES | SHA2 |
| sp_xml_preparedocument | Not needed |
