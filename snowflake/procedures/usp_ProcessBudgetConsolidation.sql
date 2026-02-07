/*
    usp_ProcessBudgetConsolidation - Complex budget consolidation with hierarchy rollup
    SNOWFLAKE JAVASCRIPT STORED PROCEDURE
    
    Translation from SQL Server:
    - Cursors → JavaScript loops with result sets
    - Table variables → TEMPORARY TABLES
    - TRY/CATCH → JavaScript try/catch
    - OUTPUT parameters → VARIANT return object
    - XML → JSON (VARIANT)
    - sp_executesql → snowflake.execute()
    - @@ROWCOUNT → stmt.getNumRowsAffected()
    - NEWID() → UUID_STRING()
    - SYSUTCDATETIME() → CURRENT_TIMESTAMP()
    
    Dependencies: 
        - Tables: BudgetHeader, BudgetLineItem, GLAccount, CostCenter, FiscalPeriod, ConsolidationJournal
        - Views: vw_BudgetConsolidationSummary
        - Functions: fn_GetHierarchyPath, tvf_ExplodeCostCenterHierarchy
*/

CREATE OR REPLACE PROCEDURE FINANCIAL_PLANNING.Planning.usp_ProcessBudgetConsolidation(
    SOURCE_BUDGET_HEADER_ID FLOAT,
    TARGET_BUDGET_HEADER_ID FLOAT,
    CONSOLIDATION_TYPE VARCHAR,
    INCLUDE_ELIMINATIONS BOOLEAN,
    RECALCULATE_ALLOCATIONS BOOLEAN,
    PROCESSING_OPTIONS VARIANT,
    USER_ID FLOAT,
    DEBUG_MODE BOOLEAN
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    // =========================================================================
    // JavaScript Stored Procedure - Complex budget consolidation
    // =========================================================================
    
    var result = {
        TARGET_BUDGET_HEADER_ID: null,
        ROWS_PROCESSED: 0,
        ERROR_MESSAGE: null,
        PROCESSING_LOG: []
    };
    
    var procStartTime = new Date();
    var currentStep = '';
    var totalRowsProcessed = 0;
    var batchSize = 5000;
    var currentBatch = 0;
    var maxIterations = 1000;
    var consolidationRunID = '';
    var targetBudgetHeaderID = TARGET_BUDGET_HEADER_ID;
    
    // Helper function to log processing steps
    function logStep(stepName, startTime, rowsAffected, status, message) {
        var endTime = new Date();
        result.PROCESSING_LOG.push({
            STEP_NAME: stepName,
            START_TIME: startTime.toISOString(),
            END_TIME: endTime.toISOString(),
            ROWS_AFFECTED: rowsAffected,
            STATUS_CODE: status,
            MESSAGE: message || null
        });
    }
    
    // Helper function to execute SQL and return statement
    function executeSQL(sql, binds) {
        try {
            var stmt = snowflake.createStatement({
                sqlText: sql,
                binds: binds || []
            });
            stmt.execute();
            return stmt;
        } catch (err) {
            throw new Error('SQL execution failed: ' + err.message + '\nSQL: ' + sql);
        }
    }
    
    try {
        // =====================================================================
        // Parameter Validation
        // =====================================================================
        currentStep = 'Parameter Validation';
        var stepStartTime = new Date();
        
        // Generate consolidation run ID
        var uuidStmt = executeSQL('SELECT UUID_STRING() AS RUN_ID');
        uuidStmt.next();
        consolidationRunID = uuidStmt.getColumnValue(1);
        
        // Check if source budget exists
        var checkSourceSQL = `
            SELECT COUNT(*) AS CNT
            FROM FINANCIAL_PLANNING.Planning.BudgetHeader
            WHERE BudgetHeaderID = ?
        `;
        var checkStmt = executeSQL(checkSourceSQL, [SOURCE_BUDGET_HEADER_ID]);
        checkStmt.next();
        if (checkStmt.getColumnValue(1) == 0) {
            throw new Error('Source budget header not found: ' + SOURCE_BUDGET_HEADER_ID);
        }
        
        // Check if source is approved/locked
        var statusSQL = `
            SELECT StatusCode
            FROM FINANCIAL_PLANNING.Planning.BudgetHeader
            WHERE BudgetHeaderID = ?
        `;
        var statusStmt = executeSQL(statusSQL, [SOURCE_BUDGET_HEADER_ID]);
        statusStmt.next();
        var statusCode = statusStmt.getColumnValue(1);
        if (statusCode !== 'APPROVED' && statusCode !== 'LOCKED') {
            throw new Error('Source budget must be in APPROVED or LOCKED status for consolidation');
        }
        
        logStep(currentStep, stepStartTime, 0, 'COMPLETED', null);
        
        // =====================================================================
        // Create temporary tables (replacing SQL Server table variables)
        // =====================================================================
        currentStep = 'Create Temporary Tables';
        stepStartTime = new Date();
        
        // Processing log temp table (we'll use JavaScript array instead)
        
        // Hierarchy nodes temp table
        executeSQL(`
            CREATE TEMPORARY TABLE IF NOT EXISTS TEMP_HIERARCHY_NODES (
                NodeID FLOAT PRIMARY KEY,
                ParentNodeID FLOAT,
                NodeLevel FLOAT,
                ProcessingOrder FLOAT,
                IsProcessed BOOLEAN DEFAULT FALSE,
                SubtotalAmount FLOAT DEFAULT 0
            )
        `);
        executeSQL('DELETE FROM TEMP_HIERARCHY_NODES');
        
        // Consolidated amounts temp table
        executeSQL(`
            CREATE TEMPORARY TABLE IF NOT EXISTS TEMP_CONSOLIDATED_AMOUNTS (
                GLAccountID FLOAT NOT NULL,
                CostCenterID FLOAT NOT NULL,
                FiscalPeriodID FLOAT NOT NULL,
                ConsolidatedAmount FLOAT DEFAULT 0,
                EliminationAmount FLOAT DEFAULT 0,
                FinalAmount FLOAT,
                SourceCount FLOAT DEFAULT 0,
                PRIMARY KEY (GLAccountID, CostCenterID, FiscalPeriodID)
            )
        `);
        executeSQL('DELETE FROM TEMP_CONSOLIDATED_AMOUNTS');
        
        logStep(currentStep, stepStartTime, 0, 'COMPLETED', null);
        
        // =====================================================================
        // Begin transaction
        // =====================================================================
        executeSQL('BEGIN TRANSACTION');
        
        // =====================================================================
        // Create or update target budget header
        // =====================================================================
        currentStep = 'Create Target Budget';
        stepStartTime = new Date();
        
        if (targetBudgetHeaderID === null || targetBudgetHeaderID === undefined) {
            // Create new consolidated budget header
            var createHeaderSQL = `
                INSERT INTO FINANCIAL_PLANNING.Planning.BudgetHeader (
                    BudgetCode, BudgetName, BudgetType, ScenarioType, FiscalYear,
                    StartPeriodID, EndPeriodID, BaseBudgetHeaderID, StatusCode,
                    VersionNumber, ExtendedProperties
                )
                SELECT 
                    BudgetCode || '_CONSOL_' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD'),
                    BudgetName || ' - Consolidated',
                    'CONSOLIDATED',
                    ScenarioType,
                    FiscalYear,
                    StartPeriodID,
                    EndPeriodID,
                    BudgetHeaderID,
                    'DRAFT',
                    1,
                    OBJECT_CONSTRUCT(
                        'ConsolidationRun', OBJECT_CONSTRUCT(
                            'RunID', ?,
                            'SourceID', ?,
                            'Timestamp', ?
                        ),
                        'OriginalProperties', ExtendedProperties
                    )
                FROM FINANCIAL_PLANNING.Planning.BudgetHeader
                WHERE BudgetHeaderID = ?
            `;
            
            var insertStmt = executeSQL(createHeaderSQL, [
                consolidationRunID,
                SOURCE_BUDGET_HEADER_ID,
                procStartTime.toISOString(),
                SOURCE_BUDGET_HEADER_ID
            ]);
            
            // Get the inserted ID using LAST_INSERT_ID pattern
            var getIdSQL = `
                SELECT BudgetHeaderID
                FROM FINANCIAL_PLANNING.Planning.BudgetHeader
                WHERE BudgetCode LIKE '%_CONSOL_%'
                  AND BaseBudgetHeaderID = ?
                ORDER BY BudgetHeaderID DESC
                LIMIT 1
            `;
            var idStmt = executeSQL(getIdSQL, [SOURCE_BUDGET_HEADER_ID]);
            idStmt.next();
            targetBudgetHeaderID = idStmt.getColumnValue(1);
            
            if (targetBudgetHeaderID === null) {
                throw new Error('Failed to create target budget header');
            }
            
            result.TARGET_BUDGET_HEADER_ID = targetBudgetHeaderID;
        }
        
        logStep(currentStep, stepStartTime, 1, 'COMPLETED', null);
        
        // =====================================================================
        // Build hierarchy for bottom-up rollup
        // =====================================================================
        currentStep = 'Build Hierarchy';
        stepStartTime = new Date();
        
        var buildHierarchySQL = `
            INSERT INTO TEMP_HIERARCHY_NODES (NodeID, ParentNodeID, NodeLevel, ProcessingOrder)
            SELECT 
                h.CostCenterID,
                h.ParentCostCenterID,
                h.HierarchyLevel,
                ROW_NUMBER() OVER (ORDER BY h.HierarchyLevel DESC, h.CostCenterID) AS ProcessingOrder
            FROM TABLE(FINANCIAL_PLANNING.Planning.tvf_ExplodeCostCenterHierarchy(NULL, 10, 0, CURRENT_TIMESTAMP())) h
        `;
        var hierStmt = executeSQL(buildHierarchySQL);
        var hierRowCount = hierStmt.getNumRowsAffected();
        
        logStep(currentStep, stepStartTime, hierRowCount, 'COMPLETED', null);
        
        // =====================================================================
        // Process consolidation using JavaScript loop (replacing cursor)
        // =====================================================================
        currentStep = 'Hierarchy Consolidation';
        stepStartTime = new Date();
        
        // Fetch all hierarchy nodes ordered for bottom-up processing
        var fetchNodesSQL = `
            SELECT NodeID, NodeLevel, ParentNodeID
            FROM TEMP_HIERARCHY_NODES
            ORDER BY NodeLevel DESC, NodeID
        `;
        var nodesStmt = executeSQL(fetchNodesSQL);
        
        // Process each node (JavaScript loop replacing CURSOR)
        while (nodesStmt.next() && currentBatch < maxIterations) {
            currentBatch++;
            
            var cursorCostCenterID = nodesStmt.getColumnValue(1);
            var cursorLevel = nodesStmt.getColumnValue(2);
            var cursorParentID = nodesStmt.getColumnValue(3);
            
            // Calculate subtotal for this node
            var subtotalSQL = `
                SELECT COALESCE(SUM(bli.FinalAmount), 0) AS SUBTOTAL
                FROM FINANCIAL_PLANNING.Planning.BudgetLineItem bli
                WHERE bli.BudgetHeaderID = ?
                  AND bli.CostCenterID = ?
            `;
            var subtotalStmt = executeSQL(subtotalSQL, [SOURCE_BUDGET_HEADER_ID, cursorCostCenterID]);
            subtotalStmt.next();
            var cursorSubtotal = subtotalStmt.getColumnValue(1);
            
            // Add child subtotals (already processed due to bottom-up order)
            var childSQL = `
                SELECT COALESCE(SUM(h.SubtotalAmount), 0) AS CHILD_TOTAL
                FROM TEMP_HIERARCHY_NODES h
                WHERE h.ParentNodeID = ?
                  AND h.IsProcessed = TRUE
            `;
            var childStmt = executeSQL(childSQL, [cursorCostCenterID]);
            childStmt.next();
            cursorSubtotal = cursorSubtotal + childStmt.getColumnValue(1);
            
            // Update node
            var updateNodeSQL = `
                UPDATE TEMP_HIERARCHY_NODES
                SET SubtotalAmount = ?,
                    IsProcessed = TRUE
                WHERE NodeID = ?
            `;
            executeSQL(updateNodeSQL, [cursorSubtotal, cursorCostCenterID]);
            
            // MERGE to update or insert consolidated amounts
            var mergeSQL = `
                MERGE INTO TEMP_CONSOLIDATED_AMOUNTS AS target
                USING (
                    SELECT 
                        bli.GLAccountID,
                        ? AS CostCenterID,
                        bli.FiscalPeriodID,
                        SUM(bli.FinalAmount) AS Amount,
                        COUNT(*) AS SourceCnt
                    FROM FINANCIAL_PLANNING.Planning.BudgetLineItem bli
                    WHERE bli.BudgetHeaderID = ?
                      AND bli.CostCenterID = ?
                    GROUP BY bli.GLAccountID, bli.FiscalPeriodID
                ) AS source
                ON target.GLAccountID = source.GLAccountID
                   AND target.CostCenterID = source.CostCenterID
                   AND target.FiscalPeriodID = source.FiscalPeriodID
                WHEN MATCHED THEN
                    UPDATE SET 
                        ConsolidatedAmount = target.ConsolidatedAmount + source.Amount,
                        SourceCount = target.SourceCount + source.SourceCnt
                WHEN NOT MATCHED THEN
                    INSERT (GLAccountID, CostCenterID, FiscalPeriodID, ConsolidatedAmount, SourceCount)
                    VALUES (source.GLAccountID, source.CostCenterID, source.FiscalPeriodID, source.Amount, source.SourceCnt)
            `;
            var mergeStmt = executeSQL(mergeSQL, [cursorCostCenterID, SOURCE_BUDGET_HEADER_ID, cursorCostCenterID]);
            totalRowsProcessed += mergeStmt.getNumRowsAffected();
        }
        
        logStep(currentStep, stepStartTime, totalRowsProcessed, 'COMPLETED', null);
        
        // =====================================================================
        // Process intercompany eliminations using JavaScript loop
        // =====================================================================
        if (INCLUDE_ELIMINATIONS === true) {
            currentStep = 'Intercompany Eliminations';
            stepStartTime = new Date();
            var eliminationCount = 0;
            
            // Fetch elimination candidates
            var elimSQL = `
                SELECT 
                    bli.GLAccountID,
                    bli.CostCenterID,
                    bli.FinalAmount,
                    gla.StatutoryAccountCode
                FROM FINANCIAL_PLANNING.Planning.BudgetLineItem bli
                INNER JOIN FINANCIAL_PLANNING.Planning.GLAccount gla ON bli.GLAccountID = gla.GLAccountID
                WHERE bli.BudgetHeaderID = ?
                  AND gla.IntercompanyFlag = TRUE
                ORDER BY bli.GLAccountID, bli.CostCenterID
            `;
            var elimStmt = executeSQL(elimSQL, [SOURCE_BUDGET_HEADER_ID]);
            
            // Store elimination entries in array for offset matching
            var eliminations = [];
            while (elimStmt.next()) {
                eliminations.push({
                    accountID: elimStmt.getColumnValue(1),
                    costCenterID: elimStmt.getColumnValue(2),
                    amount: elimStmt.getColumnValue(3),
                    partnerCode: elimStmt.getColumnValue(4),
                    processed: false
                });
            }
            
            // Process eliminations with offset matching
            for (var i = 0; i < eliminations.length; i++) {
                if (eliminations[i].processed || eliminations[i].amount === 0) {
                    continue;
                }
                
                // Look for offsetting entry in remaining items
                for (var j = i + 1; j < eliminations.length; j++) {
                    if (!eliminations[j].processed && 
                        Math.abs(eliminations[i].amount + eliminations[j].amount) < 0.01) {
                        
                        // Found offset - create elimination
                        var updateElimSQL = `
                            UPDATE TEMP_CONSOLIDATED_AMOUNTS
                            SET EliminationAmount = EliminationAmount + ?
                            WHERE GLAccountID = ?
                              AND CostCenterID = ?
                        `;
                        executeSQL(updateElimSQL, [
                            eliminations[i].amount,
                            eliminations[i].accountID,
                            eliminations[i].costCenterID
                        ]);
                        
                        eliminations[i].processed = true;
                        eliminations[j].processed = true;
                        eliminationCount++;
                        break;
                    }
                }
            }
            
            logStep(currentStep, stepStartTime, eliminationCount, 'COMPLETED', null);
        }
        
        // =====================================================================
        // Recalculate allocations with dynamic SQL
        // =====================================================================
        if (RECALCULATE_ALLOCATIONS === true) {
            currentStep = 'Recalculate Allocations';
            stepStartTime = new Date();
            
            // Base dynamic SQL
            var dynamicSQL = `
                UPDATE TEMP_CONSOLIDATED_AMOUNTS
                SET FinalAmount = ConsolidatedAmount - EliminationAmount
                WHERE ConsolidatedAmount <> 0
                   OR EliminationAmount <> 0
            `;
            
            // Extract options from VARIANT if provided
            if (PROCESSING_OPTIONS !== null && PROCESSING_OPTIONS !== undefined) {
                var includeZeroBalances = true;
                var roundingPrecision = null;
                
                try {
                    if (PROCESSING_OPTIONS.IncludeZeroBalances !== undefined) {
                        includeZeroBalances = PROCESSING_OPTIONS.IncludeZeroBalances;
                    }
                    if (PROCESSING_OPTIONS.RoundingPrecision !== undefined) {
                        roundingPrecision = PROCESSING_OPTIONS.RoundingPrecision;
                    }
                } catch (e) {
                    // Options parsing failed, use defaults
                }
                
                // Modify SQL based on options
                if (!includeZeroBalances) {
                    dynamicSQL = dynamicSQL.replace(
                        'WHERE ConsolidatedAmount <> 0',
                        'WHERE ConsolidatedAmount <> 0 AND (ConsolidatedAmount - EliminationAmount) <> 0'
                    );
                }
                
                if (roundingPrecision !== null) {
                    dynamicSQL = dynamicSQL.replace(
                        'ConsolidatedAmount - EliminationAmount',
                        'ROUND(ConsolidatedAmount - EliminationAmount, ' + roundingPrecision + ')'
                    );
                }
            }
            
            var allocStmt = executeSQL(dynamicSQL);
            var allocationRowCount = allocStmt.getNumRowsAffected();
            
            logStep(currentStep, stepStartTime, allocationRowCount, 'COMPLETED', null);
        }
        
        // =====================================================================
        // Insert final results
        // =====================================================================
        currentStep = 'Insert Results';
        stepStartTime = new Date();
        
        var insertResultsSQL = `
            INSERT INTO FINANCIAL_PLANNING.Planning.BudgetLineItem (
                BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
                OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, SourceReference,
                IsAllocated, LastModifiedByUserID, LastModifiedDateTime
            )
            SELECT 
                ?,
                ca.GLAccountID,
                ca.CostCenterID,
                ca.FiscalPeriodID,
                ca.FinalAmount,
                0,
                'CONSOLIDATED',
                'CONSOLIDATION_PROC',
                ?,
                FALSE,
                ?,
                CURRENT_TIMESTAMP()
            FROM TEMP_CONSOLIDATED_AMOUNTS ca
            WHERE ca.FinalAmount IS NOT NULL
        `;
        
        var insertStmt = executeSQL(insertResultsSQL, [
            targetBudgetHeaderID,
            consolidationRunID,
            USER_ID
        ]);
        var insertedRows = insertStmt.getNumRowsAffected();
        totalRowsProcessed += insertedRows;
        
        logStep(currentStep, stepStartTime, insertedRows, 'COMPLETED', null);
        
        // =====================================================================
        // Commit transaction
        // =====================================================================
        executeSQL('COMMIT');
        
        result.ROWS_PROCESSED = totalRowsProcessed;
        
        // Debug output
        if (DEBUG_MODE === true) {
            result.DEBUG_INFO = {
                CONSOLIDATION_RUN_ID: consolidationRunID,
                BATCHES_PROCESSED: currentBatch,
                PROC_DURATION_MS: new Date() - procStartTime
            };
        }
        
        return result;
        
    } catch (err) {
        // =====================================================================
        // Error handling
        // =====================================================================
        result.ERROR_MESSAGE = err.message;
        
        // Rollback transaction if active
        try {
            executeSQL('ROLLBACK');
        } catch (rollbackErr) {
            // Transaction may not be active
        }
        
        // Log the error
        logStep(currentStep, stepStartTime || new Date(), 0, 'ERROR', err.message);
        
        // Return error result
        return result;
    }
$$;

-- Grant execute permissions
GRANT USAGE ON PROCEDURE FINANCIAL_PLANNING.Planning.usp_ProcessBudgetConsolidation(FLOAT, FLOAT, VARCHAR, BOOLEAN, BOOLEAN, VARIANT, FLOAT, BOOLEAN) 
TO ROLE ACCOUNTADMIN;

-- Usage example:
-- CALL FINANCIAL_PLANNING.Planning.usp_ProcessBudgetConsolidation(
--     1001,                           -- SOURCE_BUDGET_HEADER_ID
--     NULL,                           -- TARGET_BUDGET_HEADER_ID (will be created)
--     'FULL',                         -- CONSOLIDATION_TYPE
--     TRUE,                           -- INCLUDE_ELIMINATIONS
--     TRUE,                           -- RECALCULATE_ALLOCATIONS
--     PARSE_JSON('{"IncludeZeroBalances": false, "RoundingPrecision": 2}'), -- PROCESSING_OPTIONS
--     100,                            -- USER_ID
--     TRUE                            -- DEBUG_MODE
-- );
