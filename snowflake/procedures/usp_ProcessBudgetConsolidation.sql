CREATE OR REPLACE PROCEDURE FINANCIAL_PLANNING.PLANNING.USP_PROCESSBUDGETCONSOLIDATION(
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
    // JavaScript Stored Procedure - Complex budget consolidation (FIXED)
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

    // FIXED: Helper function to execute SQL and return result set wrapper
    function executeSQL(sql, binds) {
        try {
            var stmt = snowflake.createStatement({
                sqlText: sql,
                binds: binds || []
            });
            var rs = stmt.execute();  // execute() returns ResultSet
            // Wrap result set with statement's getNumRowsAffected
            rs.getNumRowsAffected = function() { return stmt.getNumRowsAffected(); };
            return rs;
        } catch (err) {
            throw new Error('SQL execution failed: ' + err.message + '\nSQL: ' + sql);
        }
    }

    try {
        // =====================================================================
        // Set database context
        // =====================================================================
        executeSQL('USE DATABASE FINANCIAL_PLANNING');
        executeSQL('USE SCHEMA PLANNING');

        // =====================================================================
        // Parameter Validation
        // =====================================================================
        currentStep = 'Parameter Validation';
        var stepStartTime = new Date();

        // Generate consolidation run ID
        var uuidRS = executeSQL('SELECT UUID_STRING() AS RUN_ID');
        uuidRS.next();
        consolidationRunID = uuidRS.getColumnValue(1);

        // Check if source budget exists
        var checkSourceSQL = `
            SELECT COUNT(*) AS CNT
            FROM FINANCIAL_PLANNING.PLANNING.BUDGETHEADER
            WHERE BUDGETHEADERID = ?
        `;
        var checkRS = executeSQL(checkSourceSQL, [SOURCE_BUDGET_HEADER_ID]);
        checkRS.next();
        if (checkRS.getColumnValue(1) == 0) {
            throw new Error('Source budget header not found: ' + SOURCE_BUDGET_HEADER_ID);
        }

        // Check if source is approved/locked
        var statusSQL = `
            SELECT STATUSCODE
            FROM FINANCIAL_PLANNING.PLANNING.BUDGETHEADER
            WHERE BUDGETHEADERID = ?
        `;
        var statusRS = executeSQL(statusSQL, [SOURCE_BUDGET_HEADER_ID]);
        statusRS.next();
        var statusCode = statusRS.getColumnValue(1);
        if (statusCode !== 'APPROVED' && statusCode !== 'LOCKED') {
            throw new Error('Source budget must be in APPROVED or LOCKED status for consolidation. Current: ' + statusCode);
        }

        logStep(currentStep, stepStartTime, 0, 'COMPLETED', null);

        // =====================================================================
        // Create temporary tables
        // =====================================================================
        currentStep = 'Create Temporary Tables';
        stepStartTime = new Date();

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
        // Create target budget header
        // =====================================================================
        currentStep = 'Create Target Budget';
        stepStartTime = new Date();

        if (targetBudgetHeaderID === null || targetBudgetHeaderID === undefined) {
            var createHeaderSQL = `
                INSERT INTO FINANCIAL_PLANNING.PLANNING.BUDGETHEADER (
                    BUDGETCODE, BUDGETNAME, BUDGETTYPE, SCENARIOTYPE, FISCALYEAR,
                    STARTPERIODID, ENDPERIODID, STATUSCODE, VERSIONNUMBER
                )
                SELECT
                    BUDGETCODE || '_CONSOL_' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD'),
                    BUDGETNAME || ' - Consolidated',
                    'CONSOLIDATED',
                    SCENARIOTYPE,
                    FISCALYEAR,
                    STARTPERIODID,
                    ENDPERIODID,
                    'DRAFT',
                    1
                FROM FINANCIAL_PLANNING.PLANNING.BUDGETHEADER
                WHERE BUDGETHEADERID = ?
            `;
            executeSQL(createHeaderSQL, [SOURCE_BUDGET_HEADER_ID]);

            var getIdSQL = `
                SELECT BUDGETHEADERID
                FROM FINANCIAL_PLANNING.PLANNING.BUDGETHEADER
                WHERE BUDGETCODE LIKE '%_CONSOL_%'
                ORDER BY BUDGETHEADERID DESC
                LIMIT 1
            `;
            var idRS = executeSQL(getIdSQL);
            idRS.next();
            targetBudgetHeaderID = idRS.getColumnValue(1);

            if (targetBudgetHeaderID === null) {
                throw new Error('Failed to create target budget header');
            }

            result.TARGET_BUDGET_HEADER_ID = targetBudgetHeaderID;
        }

        logStep(currentStep, stepStartTime, 1, 'COMPLETED', null);

        // =====================================================================
        // Build hierarchy (use CostCenter table directly)
        // =====================================================================
        currentStep = 'Build Hierarchy';
        stepStartTime = new Date();

        var buildHierarchySQL = `
            INSERT INTO TEMP_HIERARCHY_NODES (NodeID, ParentNodeID, NodeLevel, ProcessingOrder)
            SELECT
                COSTCENTERID,
                PARENTCOSTCENTERID,
                HIERARCHYLEVEL,
                ROW_NUMBER() OVER (ORDER BY HIERARCHYLEVEL DESC, COSTCENTERID) AS ProcessingOrder
            FROM FINANCIAL_PLANNING.PLANNING.COSTCENTER
            WHERE ISACTIVE = TRUE
        `;
        var hierRS = executeSQL(buildHierarchySQL);
        var hierRowCount = hierRS.getNumRowsAffected();

        logStep(currentStep, stepStartTime, hierRowCount, 'COMPLETED', null);

        // =====================================================================
        // Process consolidation (JavaScript loop replacing cursor)
        // =====================================================================
        currentStep = 'Hierarchy Consolidation';
        stepStartTime = new Date();

        var fetchNodesSQL = `
            SELECT NodeID, NodeLevel, ParentNodeID
            FROM TEMP_HIERARCHY_NODES
            ORDER BY NodeLevel DESC, NodeID
        `;
        var nodesRS = executeSQL(fetchNodesSQL);

        while (nodesRS.next() && currentBatch < maxIterations) {
            currentBatch++;

            var cursorCostCenterID = nodesRS.getColumnValue(1);
            var cursorLevel = nodesRS.getColumnValue(2);
            var cursorParentID = nodesRS.getColumnValue(3);

            // Calculate subtotal for this node
            var subtotalSQL = `
                SELECT COALESCE(SUM(FINALAMOUNT), 0) AS SUBTOTAL
                FROM FINANCIAL_PLANNING.PLANNING.BUDGETLINEITEM
                WHERE BUDGETHEADERID = ?
                  AND COSTCENTERID = ?
            `;
            var subtotalRS = executeSQL(subtotalSQL, [SOURCE_BUDGET_HEADER_ID, cursorCostCenterID]);
            subtotalRS.next();
            var cursorSubtotal = subtotalRS.getColumnValue(1);

            // Add child subtotals
            var childSQL = `
                SELECT COALESCE(SUM(SubtotalAmount), 0) AS CHILD_TOTAL
                FROM TEMP_HIERARCHY_NODES
                WHERE ParentNodeID = ?
                  AND IsProcessed = TRUE
            `;
            var childRS = executeSQL(childSQL, [cursorCostCenterID]);
            childRS.next();
            cursorSubtotal = cursorSubtotal + childRS.getColumnValue(1);

            // Update node
            var updateNodeSQL = `
                UPDATE TEMP_HIERARCHY_NODES
                SET SubtotalAmount = ?,
                    IsProcessed = TRUE
                WHERE NodeID = ?
            `;
            executeSQL(updateNodeSQL, [cursorSubtotal, cursorCostCenterID]);

            // MERGE consolidated amounts
            var mergeSQL = `
                MERGE INTO TEMP_CONSOLIDATED_AMOUNTS AS target
                USING (
                    SELECT
                        GLACCOUNTID,
                        ? AS CostCenterID,
                        FISCALPERIODID,
                        SUM(FINALAMOUNT) AS Amount,
                        COUNT(*) AS SourceCnt
                    FROM FINANCIAL_PLANNING.PLANNING.BUDGETLINEITEM
                    WHERE BUDGETHEADERID = ?
                      AND COSTCENTERID = ?
                    GROUP BY GLACCOUNTID, FISCALPERIODID
                ) AS source
                ON target.GLAccountID = source.GLACCOUNTID
                   AND target.CostCenterID = source.CostCenterID
                   AND target.FiscalPeriodID = source.FISCALPERIODID
                WHEN MATCHED THEN
                    UPDATE SET
                        ConsolidatedAmount = target.ConsolidatedAmount + source.Amount,
                        SourceCount = target.SourceCount + source.SourceCnt
                WHEN NOT MATCHED THEN
                    INSERT (GLAccountID, CostCenterID, FiscalPeriodID, ConsolidatedAmount, SourceCount)
                    VALUES (source.GLACCOUNTID, source.CostCenterID, source.FISCALPERIODID, source.Amount, source.SourceCnt)
            `;
            var mergeRS = executeSQL(mergeSQL, [cursorCostCenterID, SOURCE_BUDGET_HEADER_ID, cursorCostCenterID]);
            totalRowsProcessed += mergeRS.getNumRowsAffected();
        }

        logStep(currentStep, stepStartTime, totalRowsProcessed, 'COMPLETED', null);

        // =====================================================================
        // Process intercompany eliminations
        // =====================================================================
        if (INCLUDE_ELIMINATIONS) {
            currentStep = 'Intercompany Eliminations';
            stepStartTime = new Date();
            var eliminationCount = 0;

            var elimSQL = `
                SELECT
                    bli.GLACCOUNTID,
                    bli.COSTCENTERID,
                    bli.FINALAMOUNT
                FROM FINANCIAL_PLANNING.PLANNING.BUDGETLINEITEM bli
                INNER JOIN FINANCIAL_PLANNING.PLANNING.GLACCOUNT gla ON bli.GLACCOUNTID = gla.GLACCOUNTID
                WHERE bli.BUDGETHEADERID = ?
                  AND gla.INTERCOMPANYFLAG = TRUE
                ORDER BY bli.GLACCOUNTID, bli.COSTCENTERID
            `;
            var elimRS = executeSQL(elimSQL, [SOURCE_BUDGET_HEADER_ID]);

            var eliminations = [];
            while (elimRS.next()) {
                eliminations.push({
                    accountID: elimRS.getColumnValue(1),
                    costCenterID: elimRS.getColumnValue(2),
                    amount: elimRS.getColumnValue(3),
                    processed: false
                });
            }

            for (var i = 0; i < eliminations.length; i++) {
                if (eliminations[i].processed || eliminations[i].amount === 0) {
                    continue;
                }

                for (var j = i + 1; j < eliminations.length; j++) {
                    if (!eliminations[j].processed &&
                        Math.abs(eliminations[i].amount + eliminations[j].amount) < 0.01) {

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
        // Calculate final amounts
        // =====================================================================
        if (RECALCULATE_ALLOCATIONS) {
            currentStep = 'Calculate Final Amounts';
            stepStartTime = new Date();

            var dynamicSQL = `
                UPDATE TEMP_CONSOLIDATED_AMOUNTS
                SET FinalAmount = ConsolidatedAmount - EliminationAmount
                WHERE ConsolidatedAmount <> 0
                   OR EliminationAmount <> 0
            `;

            var allocRS = executeSQL(dynamicSQL);
            var allocationRowCount = allocRS.getNumRowsAffected();

            logStep(currentStep, stepStartTime, allocationRowCount, 'COMPLETED', null);
        }

        // =====================================================================
        // Insert final results
        // =====================================================================
        currentStep = 'Insert Results';
        stepStartTime = new Date();

        var insertResultsSQL = `
            INSERT INTO FINANCIAL_PLANNING.PLANNING.BUDGETLINEITEM (
                BUDGETHEADERID, GLACCOUNTID, COSTCENTERID, FISCALPERIODID,
                ORIGINALAMOUNT, ADJUSTEDAMOUNT, FINALAMOUNT, ENTRYTYPE, ISELIMINATED, ALLOCATIONPERCENT
            )
            SELECT
                ?,
                ca.GLAccountID,
                ca.CostCenterID,
                ca.FiscalPeriodID,
                ca.FinalAmount,
                0,
                ca.FinalAmount,
                'CONSOLIDATED',
                FALSE,
                100
            FROM TEMP_CONSOLIDATED_AMOUNTS ca
            WHERE ca.FinalAmount IS NOT NULL
        `;

        var insertRS = executeSQL(insertResultsSQL, [targetBudgetHeaderID]);
        var insertedRows = insertRS.getNumRowsAffected();
        totalRowsProcessed += insertedRows;

        logStep(currentStep, stepStartTime, insertedRows, 'COMPLETED', null);

        // =====================================================================
        // Commit transaction
        // =====================================================================
        executeSQL('COMMIT');

        result.ROWS_PROCESSED = totalRowsProcessed;

        if (DEBUG_MODE) {
            result.DEBUG_INFO = {
                CONSOLIDATION_RUN_ID: consolidationRunID,
                BATCHES_PROCESSED: currentBatch,
                PROC_DURATION_MS: new Date() - procStartTime
            };
        }

        return result;

    } catch (err) {
        result.ERROR_MESSAGE = err.message;

        try {
            executeSQL('ROLLBACK');
        } catch (rollbackErr) {
            // Transaction may not be active
        }

        logStep(currentStep, stepStartTime || new Date(), 0, 'ERROR', err.message);

        return result;
    }
$$;
