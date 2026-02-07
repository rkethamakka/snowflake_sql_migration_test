CREATE OR REPLACE PROCEDURE FINANCIAL_PLANNING.PLANNING.usp_ProcessBudgetConsolidation(
    SOURCE_BUDGET_HEADER_ID FLOAT,
    CONSOLIDATION_TYPE STRING DEFAULT 'FULL',
    INCLUDE_HIERARCHY BOOLEAN DEFAULT TRUE,
    INCLUDE_ELIMINATIONS BOOLEAN DEFAULT TRUE,
    TARGET_COST_CENTER_ID VARIANT DEFAULT NULL,
    ALLOCATION_THRESHOLD FLOAT DEFAULT 100,
    CREATE_NEW_VERSION BOOLEAN DEFAULT FALSE
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
try {
    var getBudget = snowflake.createStatement({
        sqlText: `SELECT BudgetCode, BudgetName, BudgetType, ScenarioType, FiscalYear, 
                         StartPeriodID, EndPeriodID, VersionNumber
                  FROM FINANCIAL_PLANNING.PLANNING.BudgetHeader WHERE BudgetHeaderID = ?`,
        binds: [SOURCE_BUDGET_HEADER_ID]
    });
    var budgetResult = getBudget.execute();
    if (!budgetResult.next()) {
        return {ERROR_MESSAGE: "Source budget not found", TARGET_BUDGET_HEADER_ID: null, ROWS_PROCESSED: 0};
    }
    
    var budgetCode = budgetResult.getColumnValue(1);
    var budgetName = budgetResult.getColumnValue(2);
    var budgetType = budgetResult.getColumnValue(3);
    var scenarioType = budgetResult.getColumnValue(4);
    var fiscalYear = budgetResult.getColumnValue(5);
    var startPeriodID = budgetResult.getColumnValue(6);
    var endPeriodID = budgetResult.getColumnValue(7);
    var versionNumber = budgetResult.getColumnValue(8);
    
    var newVersion = CREATE_NEW_VERSION ? versionNumber + 1 : versionNumber;
    var consolidatedCode = budgetCode + "_CONS_" + new Date().toISOString().slice(0,10).replace(/-/g,'');
    
    var createHeader = snowflake.createStatement({
        sqlText: `INSERT INTO FINANCIAL_PLANNING.PLANNING.BudgetHeader 
                  (BudgetCode, BudgetName, BudgetType, ScenarioType, FiscalYear, 
                   StartPeriodID, EndPeriodID, StatusCode, VersionNumber)
                  SELECT ?, ? || ' (Consolidated)', ?, ?, ?, ?, ?, 'DRAFT', ?`,
        binds: [consolidatedCode, budgetName, budgetType, scenarioType, fiscalYear, 
                startPeriodID, endPeriodID, newVersion]
    });
    createHeader.execute();
    
    var getNewID = snowflake.createStatement({
        sqlText: `SELECT MAX(BudgetHeaderID) FROM FINANCIAL_PLANNING.PLANNING.BudgetHeader WHERE BudgetCode = ?`,
        binds: [consolidatedCode]
    });
    var idResult = getNewID.execute();
    idResult.next();
    var targetHeaderID = idResult.getColumnValue(1);
    
    var consolidateSQL = `
    INSERT INTO FINANCIAL_PLANNING.PLANNING.BudgetLineItem 
        (BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID, OriginalAmount, AdjustedAmount, SpreadMethodCode, EntryType)
    WITH RECURSIVE hierarchy AS (
        SELECT cc.CostCenterID, cc.ParentCostCenterID, cc.CostCenterCode, 1 as Level
        FROM FINANCIAL_PLANNING.PLANNING.CostCenter cc
        WHERE cc.IsActive = TRUE AND NOT EXISTS (
            SELECT 1 FROM FINANCIAL_PLANNING.PLANNING.CostCenter child WHERE child.ParentCostCenterID = cc.CostCenterID)
        UNION ALL
        SELECT cc.CostCenterID, cc.ParentCostCenterID, cc.CostCenterCode, h.Level + 1
        FROM FINANCIAL_PLANNING.PLANNING.CostCenter cc
        JOIN hierarchy h ON cc.CostCenterID = h.ParentCostCenterID
    ),
    consolidated_amounts AS (
        SELECT bli.GLAccountID, h.CostCenterID as RollupCostCenterID, bli.FiscalPeriodID,
               SUM(bli.OriginalAmount) as TotalOriginal, SUM(bli.AdjustedAmount) as TotalAdjusted
        FROM FINANCIAL_PLANNING.PLANNING.BudgetLineItem bli
        JOIN hierarchy h ON bli.CostCenterID = h.CostCenterID 
             OR bli.CostCenterID IN (SELECT CostCenterID FROM hierarchy WHERE ParentCostCenterID = h.CostCenterID)
        WHERE bli.BudgetHeaderID = ?
        GROUP BY bli.GLAccountID, h.CostCenterID, bli.FiscalPeriodID
    ),
    with_eliminations AS (
        SELECT ca.GLAccountID, ca.RollupCostCenterID, ca.FiscalPeriodID,
            CASE WHEN gla.IntercompanyFlag = TRUE AND EXISTS (
                SELECT 1 FROM consolidated_amounts ca2
                JOIN FINANCIAL_PLANNING.PLANNING.GLAccount gla2 ON ca2.GLAccountID = gla2.GLAccountID
                WHERE gla2.IntercompanyFlag = TRUE AND ca2.FiscalPeriodID = ca.FiscalPeriodID
                  AND ca2.RollupCostCenterID != ca.RollupCostCenterID
                  AND ca2.TotalOriginal + ca2.TotalAdjusted = -(ca.TotalOriginal + ca.TotalAdjusted))
            THEN 0 ELSE ca.TotalOriginal END as FinalOriginal,
            CASE WHEN gla.IntercompanyFlag = TRUE AND EXISTS (
                SELECT 1 FROM consolidated_amounts ca2
                JOIN FINANCIAL_PLANNING.PLANNING.GLAccount gla2 ON ca2.GLAccountID = gla2.GLAccountID
                WHERE gla2.IntercompanyFlag = TRUE AND ca2.FiscalPeriodID = ca.FiscalPeriodID
                  AND ca2.RollupCostCenterID != ca.RollupCostCenterID
                  AND ca2.TotalOriginal + ca2.TotalAdjusted = -(ca.TotalOriginal + ca.TotalAdjusted))
            THEN 0 ELSE ca.TotalAdjusted END as FinalAdjusted
        FROM consolidated_amounts ca
        JOIN FINANCIAL_PLANNING.PLANNING.GLAccount gla ON ca.GLAccountID = gla.GLAccountID
    )
    SELECT ?, GLAccountID, RollupCostCenterID, FiscalPeriodID, FinalOriginal, FinalAdjusted, 'CONSOLIDATED', 'ROLLUP'
    FROM with_eliminations WHERE FinalOriginal != 0 OR FinalAdjusted != 0`;
    
    var consolidate = snowflake.createStatement({sqlText: consolidateSQL, binds: [SOURCE_BUDGET_HEADER_ID, targetHeaderID]});
    consolidate.execute();
    
    var countRows = snowflake.createStatement({
        sqlText: `SELECT COUNT(*) FROM FINANCIAL_PLANNING.PLANNING.BudgetLineItem WHERE BudgetHeaderID = ?`,
        binds: [targetHeaderID]
    });
    var countResult = countRows.execute();
    countResult.next();
    var rowsProcessed = countResult.getColumnValue(1);
    
    return {TARGET_BUDGET_HEADER_ID: targetHeaderID, ROWS_PROCESSED: rowsProcessed, ERROR_MESSAGE: ""};
} catch (err) {
    return {TARGET_BUDGET_HEADER_ID: null, ROWS_PROCESSED: 0, ERROR_MESSAGE: err.message};
}
$$;
