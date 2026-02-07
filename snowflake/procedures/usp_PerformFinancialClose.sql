-- usp_PerformFinancialClose - Period-end close orchestration
-- Translated from SQL Server to Snowflake JavaScript stored procedure

CREATE OR REPLACE PROCEDURE FINANCIAL_PLANNING.PLANNING.USP_PERFORMFINANCIALCLOSE(
    FISCAL_PERIOD_ID FLOAT,
    CLOSE_TYPE VARCHAR,              -- SOFT, HARD, FINAL
    RUN_CONSOLIDATION BOOLEAN,
    RUN_ALLOCATIONS BOOLEAN,
    RUN_RECONCILIATION BOOLEAN,
    CLOSING_USER_ID FLOAT
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var result = {
        OVERALL_STATUS: 'PENDING',
        CONSOLIDATION_RESULT: null,
        ALLOCATION_RESULT: null,
        RECONCILIATION_RESULT: null,
        CLOSE_STEPS: [],
        ERROR_MESSAGE: null
    };
    
    var closeType = CLOSE_TYPE || 'SOFT';
    
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
    
    function callProcedure(procName, params) {
        var paramStr = params.map(function(p) {
            if (p === null) return 'NULL';
            if (typeof p === 'boolean') return p ? 'TRUE' : 'FALSE';
            if (typeof p === 'string') return "'" + p + "'";
            return p;
        }).join(', ');
        
        var sql = 'CALL PLANNING.' + procName + '(' + paramStr + ')';
        var rs = executeSQL(sql);
        if (rs.next()) {
            return rs.getColumnValue(1);
        }
        return null;
    }
    
    function logStep(step, status, details) {
        result.CLOSE_STEPS.push({
            STEP_NAME: step,
            STATUS: status,
            DETAILS: details,
            TIMESTAMP: new Date().toISOString()
        });
    }
    
    try {
        executeSQL('USE DATABASE FINANCIAL_PLANNING');
        executeSQL('USE SCHEMA PLANNING');
        
        // Validate period exists and is open
        var periodInfo = executeSQL(`
            SELECT FISCALYEAR, PERIODNAME, ISCLOSED
            FROM PLANNING.FISCALPERIOD
            WHERE FISCALPERIODID = ?
        `, [FISCAL_PERIOD_ID]);
        
        if (!periodInfo.next()) {
            throw new Error('Fiscal period not found: ' + FISCAL_PERIOD_ID);
        }
        
        var fiscalYear = periodInfo.getColumnValue(1);
        var periodName = periodInfo.getColumnValue(2);
        var isClosed = periodInfo.getColumnValue(3);
        
        if (isClosed && closeType !== 'SOFT') {
            throw new Error('Period is already closed');
        }
        
        logStep('Validate Period', 'COMPLETED', 'Period: ' + periodName);
        
        // Find budget for this period
        var budgetId = getValue(`
            SELECT BUDGETHEADERID 
            FROM PLANNING.BUDGETHEADER 
            WHERE FISCALYEAR = ? AND STATUSCODE = 'APPROVED'
            ORDER BY BUDGETHEADERID DESC LIMIT 1
        `, [fiscalYear]);
        
        if (!budgetId) {
            throw new Error('No approved budget found for FY' + fiscalYear);
        }
        
        logStep('Find Budget', 'COMPLETED', 'Budget ID: ' + budgetId);
        
        // Step 1: Run Consolidation
        if (RUN_CONSOLIDATION) {
            logStep('Consolidation', 'RUNNING', null);
            
            var consolResult = callProcedure('USP_PROCESSBUDGETCONSOLIDATION', 
                [budgetId, null, 'FULL', true, true, null, CLOSING_USER_ID, false]);
            
            result.CONSOLIDATION_RESULT = consolResult;
            
            if (consolResult && consolResult.ERROR_MESSAGE) {
                logStep('Consolidation', 'FAILED', consolResult.ERROR_MESSAGE);
            } else {
                logStep('Consolidation', 'COMPLETED', 
                    'Rows: ' + (consolResult ? consolResult.ROWS_PROCESSED : 0));
            }
        }
        
        // Step 2: Run Allocations
        if (RUN_ALLOCATIONS) {
            logStep('Allocations', 'RUNNING', null);
            
            var allocResult = callProcedure('USP_EXECUTECOSTALLOCATION',
                [budgetId, null, FISCAL_PERIOD_ID, false, 100, CLOSING_USER_ID]);
            
            result.ALLOCATION_RESULT = allocResult;
            
            if (allocResult && allocResult.WARNING_MESSAGES) {
                logStep('Allocations', 'WARNING', allocResult.WARNING_MESSAGES);
            } else {
                logStep('Allocations', 'COMPLETED', 
                    'Rows: ' + (allocResult ? allocResult.ROWS_ALLOCATED : 0));
            }
        }
        
        // Step 3: Run Reconciliation
        if (RUN_RECONCILIATION) {
            logStep('Reconciliation', 'RUNNING', null);
            
            var reconResult = callProcedure('USP_RECONCILEINTERCOMPANYBALANCES',
                [budgetId, 0.01, 0.001, false]);
            
            result.RECONCILIATION_RESULT = reconResult;
            
            if (reconResult && reconResult.UNRECONCILED_COUNT > 0) {
                logStep('Reconciliation', 'WARNING', 
                    'Unreconciled: ' + reconResult.UNRECONCILED_COUNT);
            } else {
                logStep('Reconciliation', 'COMPLETED', 'All balanced');
            }
        }
        
        // Mark period as closed (for HARD/FINAL close)
        if (closeType === 'HARD' || closeType === 'FINAL') {
            executeSQL(`
                UPDATE PLANNING.FISCALPERIOD
                SET ISCLOSED = TRUE
                WHERE FISCALPERIODID = ?
            `, [FISCAL_PERIOD_ID]);
            
            logStep('Close Period', 'COMPLETED', 'Type: ' + closeType);
        }
        
        result.OVERALL_STATUS = 'SUCCESS';
        
        return result;
        
    } catch (err) {
        logStep('Error', 'FAILED', err.message);
        result.OVERALL_STATUS = 'FAILED';
        result.ERROR_MESSAGE = err.message;
        return result;
    }
$$;
