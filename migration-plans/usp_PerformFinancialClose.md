# Migration Plan: usp_PerformFinancialClose

## Dependencies

| Name | Status | Notes |
|------|--------|-------|
| All Planning tables | ✅ EXISTS | |
| usp_ProcessBudgetConsolidation | ✅ DEPLOYED | |
| usp_ExecuteCostAllocation | ✅ DEPLOYED | |
| usp_ReconcileIntercompanyBalances | TO_DEPLOY | |

## Complexity Analysis

- Lines: 521
- Nested procedure calls: 3
- Transaction management: Complex
- Email notifications: Yes (sp_send_dbmail)
- Service broker: Yes (commented)

**Approach:** JavaScript orchestration procedure

## Key Translations

| SQL Server | Snowflake |
|------------|-----------|
| EXEC nested proc | CALL in JavaScript |
| sp_send_dbmail | External notification |
| @@TRANCOUNT | Transaction management |
| Service Broker | Task/Stream or external |
