/*
    vw_BudgetConsolidationSummary - Consolidated view of budget data with hierarchy rollups
    Dependencies: BudgetHeader, BudgetLineItem, GLAccount, CostCenter, FiscalPeriod

    Snowflake Migration Notes:
    - WITH SCHEMABINDING → Not supported in Snowflake
    - COUNT_BIG() → COUNT() (Snowflake COUNT returns BIGINT automatically)
    - ISNULL() → COALESCE() or NVL()
    - Indexed view → Regular view (Snowflake doesn't support indexed views, but has auto-optimization)
    - Materialized views available but require separate CREATE MATERIALIZED VIEW syntax
    - Note: LocalCurrencyAmount and ReportingCurrencyAmount columns not in current schema
*/
CREATE OR REPLACE VIEW FINANCIAL_PLANNING.PLANNING.vw_BudgetConsolidationSummary AS
SELECT
    bh.BudgetHeaderID,
    bh.BudgetCode,
    bh.BudgetName,
    bh.BudgetType,
    bh.ScenarioType,
    bh.FiscalYear,
    fp.FiscalPeriodID,
    fp.FiscalQuarter,
    fp.FiscalMonth,
    fp.PeriodName,
    gla.GLAccountID,
    gla.AccountNumber,
    gla.AccountName,
    gla.AccountType,
    cc.CostCenterID,
    cc.CostCenterCode,
    cc.CostCenterName,
    cc.ParentCostCenterID,
    -- Aggregations
    SUM(bli.OriginalAmount) AS TotalOriginalAmount,
    SUM(bli.AdjustedAmount) AS TotalAdjustedAmount,
    SUM(bli.OriginalAmount + bli.AdjustedAmount) AS TotalFinalAmount,
    COUNT(*) AS LineItemCount
FROM FINANCIAL_PLANNING.PLANNING.BudgetLineItem bli
INNER JOIN FINANCIAL_PLANNING.PLANNING.BudgetHeader bh ON bli.BudgetHeaderID = bh.BudgetHeaderID
INNER JOIN FINANCIAL_PLANNING.PLANNING.GLAccount gla ON bli.GLAccountID = gla.GLAccountID
INNER JOIN FINANCIAL_PLANNING.PLANNING.CostCenter cc ON bli.CostCenterID = cc.CostCenterID
INNER JOIN FINANCIAL_PLANNING.PLANNING.FiscalPeriod fp ON bli.FiscalPeriodID = fp.FiscalPeriodID
GROUP BY
    bh.BudgetHeaderID,
    bh.BudgetCode,
    bh.BudgetName,
    bh.BudgetType,
    bh.ScenarioType,
    bh.FiscalYear,
    fp.FiscalPeriodID,
    fp.FiscalQuarter,
    fp.FiscalMonth,
    fp.PeriodName,
    gla.GLAccountID,
    gla.AccountNumber,
    gla.AccountName,
    gla.AccountType,
    cc.CostCenterID,
    cc.CostCenterCode,
    cc.CostCenterName,
    cc.ParentCostCenterID;

-- Note: Snowflake does not support indexed views
-- Original SQL Server had clustered index: IX_vw_BudgetConsolidationSummary
-- Snowflake auto-optimizes queries based on usage patterns
-- If performance is critical, consider CREATE MATERIALIZED VIEW instead
