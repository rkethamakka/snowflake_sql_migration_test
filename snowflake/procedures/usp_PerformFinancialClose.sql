-- usp_PerformFinancialClose - Period-end close orchestration
-- Translated from SQL Server to Snowflake JavaScript stored procedure
-- Calls: usp_ProcessBudgetConsolidation, usp_ExecuteCostAllocation, usp_ReconcileIntercompanyBalances

CREATE OR REPLACE PROCEDURE FINANCIAL_PLANNING.PLANNING.USP_PERFORMFINANCIALCLOSE(
    FISCAL_PERIOD_ID FLOAT,
    CLOSE_TYPE VARCHAR,              -- SOFT, HARD, FINAL
    RUN_CONSOLIDATION BOOLEAN,
    RUN_ALLOCATIONS BOOLEAN,
    RUN_RECONCILIATION BOOLEAN,
    FORCE_CLOSE BOOLEAN,
    CLOSING_USER_ID FLOAT
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var startTime = new Date();
    var result = {
        RUN_ID: null,
        FISCAL_PERIOD_ID: FISCAL_PERIOD_ID,
        CLOSE_TYPE: CLOSE_TYPE || 'SOFT',
        OVERALL_STATUS: null,
        TOTAL_DURATION_MS: 0,
        PERIOD_INFO: {},
        VALIDATION_ERRORS: [],
        PROCESSING_STEPS: [],
        SUMMARY: {
            COMPLETED_STEPS: 0,
            FAILED_STEPS: 0,
            WARNING_STEPS: 0,
            CONSOLIDATED_BUDGET_ID: null,
            ALLOCATION_ROWS: 0,
            UNRECONCILED_COUNT: 0
        }
    };
    
    var closeType = CLOSE_TYPE || 'SOFT';
    var runConsolidation = RUN_CONSOLIDATION !== false;
    var runAllocations = RUN_ALLOCATIONS !== false;
    var runRecon = RUN_RECONCILIATION !== false;
    var forceClose = FORCE_CLOSE === true;
    
    var activeBudgetId = null;
    var consolidatedBudgetId = null;
    
    function executeSQL(sql, binds) {
        try {
            var stmt = snowflake.createStatement({sqlText: sql, binds: binds || []});
            var rs = stmt.execute();
            rs.getNumRowsAffected = function() { return stmt.getNumRowsAffected(); };
            return rs;
        } catch (err) {
            throw new Error('SQL failed: ' + err.message);
        }
    }
    
    function getValue(sql, binds) {
        var rs = executeSQL(sql, binds);
        if (rs.next()) return rs.getColumnValue(1);
        return null;
    }
    
    function getRow(sql, binds) {
        var rs = executeSQL(sql, binds);
        if (rs.next()) {
            var row = {};
            for (var i = 1; i <= rs.getColumnCount(); i++) {
                row[rs.getColumnName(i)] = rs.getColumnValue(i);
            }
            return row;
        }
        return null;
    }
    
    function logStep(stepName, status, durationMs, rowsAffected, errorMessage) {
        result.PROCESSING_STEPS.push({
            STEP_NUMBER: result.PROCESSING_STEPS.length + 1,
            STEP_NAME: stepName,
            STATUS: status,
            DURATION_MS: durationMs,
            ROWS_AFFECTED: rowsAffected,
            ERROR_MESSAGE: errorMessage
        });
        if (status === 'COMPLETED') result.SUMMARY.COMPLETED_STEPS++;
        else if (status === 'FAILED') result.SUMMARY.FAILED_STEPS++;
        else if (status === 'WARNING') result.SUMMARY.WARNING_STEPS++;
    }
    
    function addValidationError(code, message, severity, blocksClose) {
        result.VALIDATION_ERRORS.push({
            ERROR_CODE: code,
            ERROR_MESSAGE: message,
            SEVERITY: severity,
            BLOCKS_CLOSE: blocksClose
        });
    }
    
    try {
        executeSQL('USE DATABASE FINANCIAL_PLANNING');
        executeSQL('USE SCHEMA PLANNING');
        
        // Generate run ID
        result.RUN_ID = getValue("SELECT UUID_STRING()");
        
        // =====================================================================
        // Step 1: Validate period
        // =====================================================================
        var stepStart = new Date();
        
        var periodInfo = getRow(`
            SELECT FISCALYEAR, FISCALMONTH, PERIODNAME, ISCLOSED
            FROM PLANNING.FISCALPERIOD
            WHERE FISCALPERIODID = ?
        `, [FISCAL_PERIOD_ID]);
        
        if (!periodInfo) {
            addValidationError('INVALID_PERIOD', 'Fiscal period not found: ' + FISCAL_PERIOD_ID, 'ERROR', true);
        } else {
            result.PERIOD_INFO = {
                FISCAL_YEAR: periodInfo.FISCALYEAR,
                FISCAL_MONTH: periodInfo.FISCALMONTH,
                PERIOD_NAME: periodInfo.PERIODNAME,
                IS_CLOSED: periodInfo.ISCLOSED
            };
            
            if (periodInfo.ISCLOSED && !forceClose) {
                addValidationError('ALREADY_CLOSED', 'Period is already closed. Use FORCE_CLOSE=TRUE to reprocess.', 'ERROR', true);
            }
        }
        
        // Check prior periods for HARD/FINAL close
        if (closeType === 'HARD' || closeType === 'FINAL') {
            var priorOpen = getValue(`
                SELECT COUNT(*) FROM PLANNING.FISCALPERIOD
                WHERE FISCALYEAR = ? AND FISCALMONTH < ? AND ISCLOSED = FALSE
                AND COALESCE(ISADJUSTMENTPERIOD, FALSE) = FALSE
            `, [periodInfo ? periodInfo.FISCALYEAR : 0, periodInfo ? periodInfo.FISCALMONTH : 0]);
            
            if (priorOpen > 0) {
                addValidationError('PRIOR_OPEN', 'Prior periods must be closed before ' + closeType + ' close', 'ERROR', true);
            }
        }
        
        // Check pending journals
        var pendingJournals = getValue(`
            SELECT COUNT(*) FROM PLANNING.CONSOLIDATIONJOURNAL
            WHERE FISCALPERIODID = ? AND STATUSCODE IN ('DRAFT', 'SUBMITTED')
        `, [FISCAL_PERIOD_ID]);
        
        if (pendingJournals > 0) {
            var severity = closeType === 'FINAL' ? 'ERROR' : 'WARNING';
            var blocks = closeType === 'FINAL';
            addValidationError('PENDING_JOURNALS', pendingJournals + ' pending journal(s) must be posted or rejected', severity, blocks);
        }
        
        var stepDuration = new Date() - stepStart;
        var hasBlockingErrors = result.VALIDATION_ERRORS.some(function(e) { return e.BLOCKS_CLOSE; });
        logStep('Period Validation', hasBlockingErrors ? 'FAILED' : 'COMPLETED', stepDuration, result.VALIDATION_ERRORS.length, null);
        
        if (hasBlockingErrors) {
            result.OVERALL_STATUS = 'VALIDATION_FAILED';
            result.TOTAL_DURATION_MS = new Date() - startTime;
            return result;
        }
        
        // =====================================================================
        // Step 2: Find active budget for period
        // =====================================================================
        stepStart = new Date();
        
        activeBudgetId = getValue(`
            SELECT BUDGETHEADERID FROM PLANNING.BUDGETHEADER bh
            WHERE EXISTS (
                SELECT 1 FROM PLANNING.FISCALPERIOD fp
                WHERE fp.FISCALPERIODID = ?
                AND fp.FISCALPERIODID BETWEEN bh.STARTPERIODID AND bh.ENDPERIODID
            )
            AND bh.STATUSCODE IN ('APPROVED', 'LOCKED')
            ORDER BY bh.VERSIONNUMBER DESC
            LIMIT 1
        `, [FISCAL_PERIOD_ID]);
        
        logStep('Find Active Budget', activeBudgetId ? 'COMPLETED' : 'WARNING', 
                new Date() - stepStart, activeBudgetId ? 1 : 0,
                activeBudgetId ? null : 'No active budget found');
        
        // =====================================================================
        // Step 3: Run Consolidation
        // =====================================================================
        if (runConsolidation && activeBudgetId) {
            stepStart = new Date();
            try {
                var consolResult = getRow(`
                    SELECT * FROM TABLE(RESULT_SCAN(LAST_QUERY_ID(-1)))
                `);
                
                // Call consolidation procedure
                var consolRs = executeSQL(`
                    CALL PLANNING.USP_PROCESSBUDGETCONSOLIDATION(?, 'FULL', TRUE, FALSE, ?)
                `, [activeBudgetId, CLOSING_USER_ID]);
                
                if (consolRs.next()) {
                    var consolOutput = consolRs.getColumnValue(1);
                    if (consolOutput && consolOutput.TARGET_BUDGET_ID) {
                        consolidatedBudgetId = consolOutput.TARGET_BUDGET_ID;
                        result.SUMMARY.CONSOLIDATED_BUDGET_ID = consolidatedBudgetId;
                    }
                }
                
                logStep('Budget Consolidation', 'COMPLETED', new Date() - stepStart, 
                        consolidatedBudgetId ? 1 : 0, null);
            } catch (err) {
                logStep('Budget Consolidation', closeType === 'FINAL' ? 'FAILED' : 'WARNING',
                        new Date() - stepStart, 0, err.message);
                if (closeType === 'FINAL') throw err;
            }
        }
        
        // =====================================================================
        // Step 4: Run Cost Allocations
        // =====================================================================
        var effectiveBudgetId = consolidatedBudgetId || activeBudgetId;
        
        if (runAllocations && effectiveBudgetId) {
            stepStart = new Date();
            try {
                var allocRs = executeSQL(`
                    CALL PLANNING.USP_EXECUTECOSTALLOCATION(?, NULL, ?, FALSE, 100, ?)
                `, [effectiveBudgetId, FISCAL_PERIOD_ID, CLOSING_USER_ID]);
                
                var allocRows = 0;
                if (allocRs.next()) {
                    var allocOutput = allocRs.getColumnValue(1);
                    if (allocOutput && allocOutput.ROWS_ALLOCATED) {
                        allocRows = allocOutput.ROWS_ALLOCATED;
                        result.SUMMARY.ALLOCATION_ROWS = allocRows;
                    }
                }
                
                logStep('Cost Allocations', 'COMPLETED', new Date() - stepStart, allocRows, null);
            } catch (err) {
                logStep('Cost Allocations', closeType === 'FINAL' ? 'FAILED' : 'WARNING',
                        new Date() - stepStart, 0, err.message);
                if (closeType === 'FINAL') throw err;
            }
        }
        
        // =====================================================================
        // Step 5: Run Intercompany Reconciliation
        // =====================================================================
        if (runRecon && effectiveBudgetId) {
            stepStart = new Date();
            try {
                var reconRs = executeSQL(`
                    CALL PLANNING.USP_RECONCILEINTERCOMPANYBALANCES(?, NULL, NULL, 0.01, 0.001, ?)
                `, [effectiveBudgetId, closeType !== 'FINAL']);
                
                var unreconCount = 0;
                if (reconRs.next()) {
                    var reconOutput = reconRs.getColumnValue(1);
                    if (reconOutput && reconOutput.STATISTICS) {
                        unreconCount = reconOutput.STATISTICS.UNRECONCILED || 0;
                        result.SUMMARY.UNRECONCILED_COUNT = unreconCount;
                    }
                }
                
                var reconStatus = 'COMPLETED';
                if (unreconCount > 0) {
                    reconStatus = closeType === 'FINAL' ? 'FAILED' : 'WARNING';
                }
                
                logStep('Intercompany Reconciliation', reconStatus, new Date() - stepStart, 
                        unreconCount, unreconCount > 0 ? unreconCount + ' unreconciled items' : null);
                
                if (closeType === 'FINAL' && unreconCount > 0) {
                    throw new Error('Cannot perform FINAL close with unreconciled intercompany balances');
                }
            } catch (err) {
                logStep('Intercompany Reconciliation', 'FAILED', new Date() - stepStart, 0, err.message);
                if (closeType === 'FINAL') throw err;
            }
        }
        
        // =====================================================================
        // Step 6: Lock the period
        // =====================================================================
        stepStart = new Date();
        
        executeSQL('BEGIN TRANSACTION');
        
        try {
            // Update period to closed
            var periodUpdate = executeSQL(`
                UPDATE PLANNING.FISCALPERIOD
                SET ISCLOSED = TRUE,
                    CLOSEDBYUSERID = ?,
                    CLOSEDDATETIME = CURRENT_TIMESTAMP(),
                    MODIFIEDDATETIME = CURRENT_TIMESTAMP()
                WHERE FISCALPERIODID = ?
            `, [CLOSING_USER_ID, FISCAL_PERIOD_ID]);
            
            // Lock all approved budgets in this period
            var budgetUpdate = executeSQL(`
                UPDATE PLANNING.BUDGETHEADER
                SET STATUSCODE = 'LOCKED',
                    MODIFIEDDATETIME = CURRENT_TIMESTAMP()
                WHERE STATUSCODE = 'APPROVED'
                AND ? BETWEEN STARTPERIODID AND ENDPERIODID
            `, [FISCAL_PERIOD_ID]);
            
            executeSQL('COMMIT');
            
            logStep('Lock Period', 'COMPLETED', new Date() - stepStart, 
                    periodUpdate.getNumRowsAffected() + budgetUpdate.getNumRowsAffected(), null);
        } catch (err) {
            executeSQL('ROLLBACK');
            logStep('Lock Period', 'FAILED', new Date() - stepStart, 0, err.message);
            throw err;
        }
        
        result.OVERALL_STATUS = 'COMPLETED';
        
    } catch (err) {
        result.OVERALL_STATUS = 'FAILED';
        logStep('Error Handler', 'ERROR', 0, 0, err.message);
    }
    
    result.TOTAL_DURATION_MS = new Date() - startTime;
    return result;
$$;
