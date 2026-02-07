/*
    vw_BudgetConsolidationSummary - Consolidated view of budget data with hierarchy rollups
    Dependencies: BudgetHeader, BudgetLineItem, GLAccount, CostCenter, FiscalPeriod
    
    Migration notes:
    - Removed SCHEMABINDING (not supported in Snowflake)
    - Changed COUNT_BIG() to COUNT()
    - Changed ISNULL() to COALESCE()
    - Schema changed from Planning to FINANCIAL_PLANNING.PLANNING
    - Removed indexed view indexes (Snowflake uses materialized views differently)
*/
CREATE OR REPLACE VIEW FINANCIAL_PLANNING.PLANNING.vw_BudgetConsolidationSummary
AS
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
    SUM(COALESCE(bli.LocalCurrencyAmount, 0)) AS TotalLocalCurrency,
    SUM(COALESCE(bli.ReportingCurrencyAmount, 0)) AS TotalReportingCurrency,
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
