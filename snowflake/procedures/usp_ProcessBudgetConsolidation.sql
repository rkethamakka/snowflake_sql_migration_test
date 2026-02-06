/*
    usp_ProcessBudgetConsolidation - Budget consolidation with hierarchy rollup

    Using JavaScript for flexibility since SQL Scripting has severe limitations

    CRITICAL FIX: Elimination logic runs BEFORE hierarchy rollup (order-of-operations fix)
*/

CREATE OR REPLACE PROCEDURE FINANCIAL_PLANNING.PLANNING.usp_ProcessBudgetConsolidation(
    SOURCE_BUDGET_HEADER_ID FLOAT,
    CONSOLIDATION_TYPE STRING,
    INCLUDE_ELIMINATIONS BOOLEAN,
    RECALCULATE_ALLOCATIONS BOOLEAN,
    PROCESSING_OPTIONS VARIANT,
    USER_ID FLOAT,
    DEBUG_MODE BOOLEAN
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
AS
$$
try {
    // Generate unique run ID
    var runId = 'RUN_' + Date.now();
    var targetBudgetId = null;
    var rowsProcessed = 0;

    // Create target budget header
    var createBudgetSql = `
        INSERT INTO FINANCIAL_PLANNING.PLANNING.BudgetHeader (
            BudgetCode, BudgetName, BudgetType, ScenarioType, FiscalYear,
            StartPeriodID, EndPeriodID, BaseBudgetHeaderID, StatusCode,
            VersionNumber, ExtendedProperties
        )
        SELECT
            SUBSTRING(BudgetCode, 1, 13) || '_C_' || TO_VARCHAR(CURRENT_DATE(), 'YYMMDD'),
            BudgetName || ' - Consolidated',
            'CONSOL',
            ScenarioType,
            FiscalYear,
            StartPeriodID,
            EndPeriodID,
            BudgetHeaderID,
            'DRAFT',
            1,
            PARSE_JSON('{"ConsolidationRun": {"RunID": "` + runId + `"}}')
        FROM FINANCIAL_PLANNING.PLANNING.BudgetHeader
        WHERE BudgetHeaderID = ?
    `;
    snowflake.execute({sqlText: createBudgetSql, binds: [SOURCE_BUDGET_HEADER_ID]});

    // Get the new budget header ID
    var getIdSql = "SELECT MAX(BudgetHeaderID) as id FROM FINANCIAL_PLANNING.PLANNING.BudgetHeader WHERE BudgetCode LIKE '%_C_%'";
    var idResult = snowflake.execute({sqlText: getIdSql});
    if (idResult.next()) {
        targetBudgetId = idResult.getColumnValue(1);
    }

    // Create temp table for direct amounts
    snowflake.execute({sqlText: `
        CREATE TEMPORARY TABLE temp_direct_amounts AS
        SELECT
            CostCenterID,
            GLAccountID,
            FiscalPeriodID,
            SUM(OriginalAmount + AdjustedAmount) AS direct_amount
        FROM FINANCIAL_PLANNING.PLANNING.BudgetLineItem
        WHERE BudgetHeaderID = ?
        GROUP BY CostCenterID, GLAccountID, FiscalPeriodID
    `, binds: [SOURCE_BUDGET_HEADER_ID]});

    // CRITICAL: Process eliminations BEFORE hierarchy rollup (order-of-operations fix)
    if (INCLUDE_ELIMINATIONS) {
        // Find and mark matched IC pairs at DIRECT level
        snowflake.execute({sqlText: `
            CREATE TEMPORARY TABLE temp_elimination_pairs AS
            SELECT
                da1.CostCenterID AS cost_center_1,
                da2.CostCenterID AS cost_center_2,
                da1.GLAccountID,
                da1.FiscalPeriodID,
                da1.direct_amount AS amount_1,
                da2.direct_amount AS amount_2
            FROM temp_direct_amounts da1
            JOIN temp_direct_amounts da2
                ON da1.GLAccountID = da2.GLAccountID
                AND da1.FiscalPeriodID = da2.FiscalPeriodID
                AND da1.CostCenterID < da2.CostCenterID  -- Avoid duplicates
            JOIN FINANCIAL_PLANNING.PLANNING.GLAccount gla
                ON da1.GLAccountID = gla.GLAccountID
            WHERE gla.IntercompanyFlag = TRUE
              AND da1.direct_amount = -da2.direct_amount
              AND da1.direct_amount <> 0
        `});

        // Apply eliminations: Set matched pairs to 0
        snowflake.execute({sqlText: `
            UPDATE temp_direct_amounts da
            SET direct_amount = 0
            WHERE EXISTS (
                SELECT 1
                FROM temp_elimination_pairs ep
                WHERE (
                    (da.CostCenterID = ep.cost_center_1 AND da.GLAccountID = ep.GLAccountID AND da.FiscalPeriodID = ep.FiscalPeriodID)
                    OR
                    (da.CostCenterID = ep.cost_center_2 AND da.GLAccountID = ep.GLAccountID AND da.FiscalPeriodID = ep.FiscalPeriodID)
                )
            )
        `});
    }

    // Build hierarchy closure table
    snowflake.execute({sqlText: `
        CREATE TEMPORARY TABLE temp_hierarchy_paths AS
        WITH RECURSIVE hierarchy_tree AS (
            SELECT
                CostCenterID,
                ParentCostCenterID,
                CostCenterID AS descendant_id,
                0 AS distance
            FROM FINANCIAL_PLANNING.PLANNING.CostCenter

            UNION ALL

            SELECT
                cc.CostCenterID,
                cc.ParentCostCenterID,
                ht.descendant_id,
                ht.distance + 1
            FROM FINANCIAL_PLANNING.PLANNING.CostCenter cc
            JOIN hierarchy_tree ht
                ON cc.CostCenterID = ht.ParentCostCenterID
        )
        SELECT * FROM hierarchy_tree
    `});

    // Create consolidated amounts table (with eliminations already applied)
    snowflake.execute({sqlText: `
        CREATE TEMPORARY TABLE temp_consolidated_amounts AS
        SELECT
            da.GLAccountID as gl_account_id,
            hp.CostCenterID as cost_center_id,
            da.FiscalPeriodID as fiscal_period_id,
            SUM(da.direct_amount) AS final_amount,
            COUNT(*) AS source_count
        FROM temp_hierarchy_paths hp
        JOIN temp_direct_amounts da
            ON hp.descendant_id = da.CostCenterID
        GROUP BY da.GLAccountID, hp.CostCenterID, da.FiscalPeriodID
    `});

    // Insert final results
    var insertSql = `
        INSERT INTO FINANCIAL_PLANNING.PLANNING.BudgetLineItem (
            BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
            OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem,
            IsAllocated, LastModifiedByUserID, LastModifiedDateTime
        )
        SELECT
            ?,
            ca.gl_account_id,
            ca.cost_center_id,
            ca.fiscal_period_id,
            ca.final_amount,
            0,
            'CONSOL',
            'CONSOLIDATION_PROC',
            FALSE,
            ?,
            SYSDATE()
        FROM temp_consolidated_amounts ca
        WHERE ca.final_amount IS NOT NULL
    `;
    var insertResult = snowflake.execute({sqlText: insertSql, binds: [targetBudgetId, USER_ID]});
    rowsProcessed = insertResult.getNumRowsAffected();

    // Return success
    return {
        TARGET_BUDGET_HEADER_ID: targetBudgetId,
        ROWS_PROCESSED: rowsProcessed,
        ERROR_MESSAGE: ''
    };

} catch (err) {
    return {
        TARGET_BUDGET_HEADER_ID: null,
        ROWS_PROCESSED: 0,
        ERROR_MESSAGE: err.message
    };
}
$$;
