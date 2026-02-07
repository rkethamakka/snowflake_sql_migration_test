CREATE OR REPLACE VIEW FINANCIAL_PLANNING.PLANNING.vw_BudgetConsolidationSummary AS
SELECT 
    bh.BudgetHeaderID,
    bh.BudgetCode,
    bh.BudgetName,
    bh.FiscalYear,
    cc.CostCenterCode,
    cc.CostCenterName,
    gla.AccountNumber,
    gla.AccountName,
    fp.PeriodName,
    SUM(bli.OriginalAmount) as TotalOriginalAmount,
    SUM(bli.AdjustedAmount) as TotalAdjustedAmount,
    SUM(bli.OriginalAmount + bli.AdjustedAmount) as TotalAmount,
    COUNT(*) as LineItemCount
FROM FINANCIAL_PLANNING.PLANNING.BudgetHeader bh
JOIN FINANCIAL_PLANNING.PLANNING.BudgetLineItem bli ON bh.BudgetHeaderID = bli.BudgetHeaderID
JOIN FINANCIAL_PLANNING.PLANNING.CostCenter cc ON bli.CostCenterID = cc.CostCenterID
JOIN FINANCIAL_PLANNING.PLANNING.GLAccount gla ON bli.GLAccountID = gla.GLAccountID
JOIN FINANCIAL_PLANNING.PLANNING.FiscalPeriod fp ON bli.FiscalPeriodID = fp.FiscalPeriodID
GROUP BY 
    bh.BudgetHeaderID, bh.BudgetCode, bh.BudgetName, bh.FiscalYear,
    cc.CostCenterCode, cc.CostCenterName,
    gla.AccountNumber, gla.AccountName,
    fp.PeriodName;
