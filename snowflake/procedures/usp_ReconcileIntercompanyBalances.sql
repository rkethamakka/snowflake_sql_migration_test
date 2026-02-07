-- usp_ReconcileIntercompanyBalances - Intercompany reconciliation
-- Translated from SQL Server to Snowflake JavaScript stored procedure

CREATE OR REPLACE PROCEDURE FINANCIAL_PLANNING.PLANNING.USP_RECONCILEINTERCOMPANYBALANCES(
    BUDGET_HEADER_ID FLOAT,
    TOLERANCE_AMOUNT FLOAT,
    TOLERANCE_PERCENT FLOAT,
    AUTO_CREATE_ADJUSTMENTS BOOLEAN
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var result = {
        UNRECONCILED_COUNT: 0,
        TOTAL_VARIANCE_AMOUNT: 0,
        RECONCILED_PAIRS: 0,
        ADJUSTMENTS_CREATED: 0,
        RECONCILIATION_DETAILS: [],
        PROCESSING_LOG: []
    };
    
    var toleranceAmt = TOLERANCE_AMOUNT || 0.01;
    var tolerancePct = TOLERANCE_PERCENT || 0.001;
    
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
    
    function logStep(step, rows, status, msg) {
        result.PROCESSING_LOG.push({
            STEP: step, ROWS: rows, STATUS: status, MESSAGE: msg
        });
    }
    
    try {
        executeSQL('USE DATABASE FINANCIAL_PLANNING');
        executeSQL('USE SCHEMA PLANNING');
        
        // Create temp table for IC pairs
        executeSQL(`
            CREATE TEMPORARY TABLE IF NOT EXISTS TEMP_IC_PAIRS (
                PairID FLOAT,
                Entity1ID FLOAT,
                Entity2ID FLOAT,
                GLAccountID FLOAT,
                FiscalPeriodID FLOAT,
                Entity1Amount FLOAT,
                Entity2Amount FLOAT,
                Variance FLOAT,
                IsReconciled BOOLEAN,
                ReconciliationStatus VARCHAR
            )
        `);
        executeSQL('DELETE FROM TEMP_IC_PAIRS');
        
        logStep('Create Temp Tables', 0, 'COMPLETED', null);
        
        // Find intercompany account entries
        var icSQL = `
            SELECT 
                bli1.COSTCENTERID AS Entity1ID,
                bli2.COSTCENTERID AS Entity2ID,
                bli1.GLACCOUNTID,
                bli1.FISCALPERIODID,
                bli1.FINALAMOUNT AS Entity1Amount,
                bli2.FINALAMOUNT AS Entity2Amount,
                bli1.FINALAMOUNT + bli2.FINALAMOUNT AS Variance
            FROM PLANNING.BUDGETLINEITEM bli1
            INNER JOIN PLANNING.GLACCOUNT gla ON bli1.GLACCOUNTID = gla.GLACCOUNTID
            INNER JOIN PLANNING.BUDGETLINEITEM bli2 
                ON bli1.GLACCOUNTID = bli2.GLACCOUNTID
                AND bli1.FISCALPERIODID = bli2.FISCALPERIODID
                AND bli1.BUDGETHEADERID = bli2.BUDGETHEADERID
                AND bli1.COSTCENTERID < bli2.COSTCENTERID
            WHERE bli1.BUDGETHEADERID = ?
              AND gla.INTERCOMPANYFLAG = TRUE
        `;
        
        var icRS = executeSQL(icSQL, [BUDGET_HEADER_ID]);
        
        var pairId = 0;
        var totalVariance = 0;
        var unreconciledCount = 0;
        var reconciledCount = 0;
        
        while (icRS.next()) {
            pairId++;
            var entity1 = icRS.getColumnValue(1);
            var entity2 = icRS.getColumnValue(2);
            var glAcct = icRS.getColumnValue(3);
            var period = icRS.getColumnValue(4);
            var amt1 = icRS.getColumnValue(5);
            var amt2 = icRS.getColumnValue(6);
            var variance = icRS.getColumnValue(7);
            
            var isReconciled = Math.abs(variance) <= toleranceAmt;
            var status = isReconciled ? 'RECONCILED' : 'UNRECONCILED';
            
            if (!isReconciled) {
                unreconciledCount++;
                totalVariance += Math.abs(variance);
            } else {
                reconciledCount++;
            }
            
            executeSQL(`
                INSERT INTO TEMP_IC_PAIRS VALUES (?,?,?,?,?,?,?,?,?,?)
            `, [pairId, entity1, entity2, glAcct, period, amt1, amt2, variance, isReconciled, status]);
            
            result.RECONCILIATION_DETAILS.push({
                Entity1: entity1,
                Entity2: entity2,
                GLAccount: glAcct,
                Period: period,
                Amount1: amt1,
                Amount2: amt2,
                Variance: variance,
                Status: status
            });
        }
        
        result.UNRECONCILED_COUNT = unreconciledCount;
        result.TOTAL_VARIANCE_AMOUNT = totalVariance;
        result.RECONCILED_PAIRS = reconciledCount;
        
        logStep('Find IC Pairs', pairId, 'COMPLETED', 
                'Reconciled: ' + reconciledCount + ', Unreconciled: ' + unreconciledCount);
        
        // Auto-create adjustments if requested
        if (AUTO_CREATE_ADJUSTMENTS && unreconciledCount > 0) {
            executeSQL('BEGIN TRANSACTION');
            
            var adjSQL = `
                INSERT INTO PLANNING.BUDGETLINEITEM (
                    BUDGETHEADERID, GLACCOUNTID, COSTCENTERID, FISCALPERIODID,
                    ORIGINALAMOUNT, ADJUSTEDAMOUNT, FINALAMOUNT, ENTRYTYPE,
                    ISELIMINATED, ALLOCATIONPERCENT
                )
                SELECT 
                    ?,
                    p.GLAccountID,
                    p.Entity1ID,
                    p.FiscalPeriodID,
                    -p.Variance / 2,
                    0,
                    -p.Variance / 2,
                    'IC_ADJUSTMENT',
                    FALSE,
                    100
                FROM TEMP_IC_PAIRS p
                WHERE p.IsReconciled = FALSE
            `;
            
            var adjRS = executeSQL(adjSQL, [BUDGET_HEADER_ID]);
            result.ADJUSTMENTS_CREATED = adjRS.getNumRowsAffected();
            
            executeSQL('COMMIT');
            
            logStep('Create Adjustments', result.ADJUSTMENTS_CREATED, 'COMPLETED', null);
        }
        
        return result;
        
    } catch (err) {
        try { executeSQL('ROLLBACK'); } catch(e) {}
        logStep('Error', 0, 'ERROR', err.message);
        result.ERROR_MESSAGE = err.message;
        return result;
    }
$$;
