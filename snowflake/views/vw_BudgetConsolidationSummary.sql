/*
    vw_BudgetConsolidationSummary - Consolidated view of budget data with hierarchy rollups
    Dependencies: BudgetHeader, BudgetLineItem, GLAccount, CostCenter, FiscalPeriod

    Translation notes:
    - SCHEMABINDING removed (not supported in Snowflake)
    - COUNT_BIG() → COUNT()
    - ISNULL() → COALESCE() or IFNULL()
    - Indexed view → Regular view (indexes removed)
    - Note: Can be converted to MATERIALIZED VIEW for performance if needed

    For materialized view, change to:
    CREATE OR REPLACE MATERIALIZED VIEW ...
*/

USE DATABASE FINANCIAL_PLANNING;
USE SCHEMA PLANNING;

CREATE OR REPLACE VIEW PLANNING.vw_BudgetConsolidationSummary
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
FROM PLANNING.BudgetLineItem bli
INNER JOIN PLANNING.BudgetHeader bh ON bli.BudgetHeaderID = bh.BudgetHeaderID
INNER JOIN PLANNING.GLAccount gla ON bli.GLAccountID = gla.GLAccountID
INNER JOIN PLANNING.CostCenter cc ON bli.CostCenterID = cc.CostCenterID
INNER JOIN PLANNING.FiscalPeriod fp ON bli.FiscalPeriodID = fp.FiscalPeriodID
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

-- Note: Indexes on views not supported in Snowflake
-- Snowflake uses automatic query optimization instead
