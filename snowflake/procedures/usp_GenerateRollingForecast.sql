-- usp_GenerateRollingForecast - Generate rolling forecast with statistical projections
-- Translated from SQL Server to Snowflake JavaScript stored procedure

CREATE OR REPLACE PROCEDURE FINANCIAL_PLANNING.PLANNING.USP_GENERATEROLLINGFORECAST(
    BASE_BUDGET_HEADER_ID FLOAT,
    HISTORICAL_PERIODS FLOAT,        -- Months of history to analyze
    FORECAST_PERIODS FLOAT,          -- Months to forecast
    FORECAST_METHOD VARCHAR,         -- WEIGHTED_AVERAGE, LINEAR_TREND, SIMPLE_AVERAGE
    GROWTH_RATE_OVERRIDE FLOAT,      -- Optional override
    USER_ID FLOAT
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var result = {
        TARGET_BUDGET_HEADER_ID: null,
        PERIODS_FORECASTED: 0,
        ROWS_CREATED: 0,
        FORECAST_SUMMARY: [],
        PROCESSING_LOG: []
    };
    
    var histPeriods = HISTORICAL_PERIODS || 12;
    var fcstPeriods = FORECAST_PERIODS || 12;
    var method = FORECAST_METHOD || 'WEIGHTED_AVERAGE';
    
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
    
    function logStep(step, rows, status, msg) {
        result.PROCESSING_LOG.push({
            STEP: step, ROWS: rows, STATUS: status, MESSAGE: msg
        });
    }
    
    try {
        executeSQL('USE DATABASE FINANCIAL_PLANNING');
        executeSQL('USE SCHEMA PLANNING');
        
        // Get base budget info
        var budgetInfo = executeSQL(`
            SELECT FISCALYEAR, BUDGETCODE, SCENARIOTYPE
            FROM PLANNING.BUDGETHEADER
            WHERE BUDGETHEADERID = ?
        `, [BASE_BUDGET_HEADER_ID]);
        
        if (!budgetInfo.next()) {
            throw new Error('Base budget not found: ' + BASE_BUDGET_HEADER_ID);
        }
        
        var fiscalYear = budgetInfo.getColumnValue(1);
        var budgetCode = budgetInfo.getColumnValue(2);
        var scenario = budgetInfo.getColumnValue(3);
        
        logStep('Get Base Budget', 1, 'COMPLETED', 'FY' + fiscalYear);
        
        // Create forecast budget header
        executeSQL('BEGIN TRANSACTION');
        
        executeSQL(`
            INSERT INTO PLANNING.BUDGETHEADER (
                BUDGETCODE, BUDGETNAME, BUDGETTYPE, SCENARIOTYPE, FISCALYEAR,
                STARTPERIODID, ENDPERIODID, STATUSCODE, VERSIONNUMBER
            )
            SELECT 
                BUDGETCODE || '_FCST_' || TO_CHAR(CURRENT_DATE, 'YYYYMMDD'),
                BUDGETNAME || ' - Forecast',
                'FORECAST',
                'FORECAST',
                FISCALYEAR + 1,
                STARTPERIODID,
                ENDPERIODID,
                'DRAFT',
                1
            FROM PLANNING.BUDGETHEADER
            WHERE BUDGETHEADERID = ?
        `, [BASE_BUDGET_HEADER_ID]);
        
        var targetId = getValue(`
            SELECT MAX(BUDGETHEADERID) FROM PLANNING.BUDGETHEADER
            WHERE BUDGETCODE LIKE '%_FCST_%'
        `);
        
        result.TARGET_BUDGET_HEADER_ID = targetId;
        logStep('Create Forecast Header', 1, 'COMPLETED', 'ID: ' + targetId);
        
        // Calculate historical averages by account/cost center
        executeSQL(`
            CREATE TEMPORARY TABLE IF NOT EXISTS TEMP_FORECAST_CALC (
                GLAccountID FLOAT,
                CostCenterID FLOAT,
                AvgAmount FLOAT,
                TrendFactor FLOAT,
                ForecastAmount FLOAT
            )
        `);
        executeSQL('DELETE FROM TEMP_FORECAST_CALC');
        
        // Calculate averages
        executeSQL(`
            INSERT INTO TEMP_FORECAST_CALC (GLAccountID, CostCenterID, AvgAmount, TrendFactor)
            SELECT 
                GLACCOUNTID,
                COSTCENTERID,
                AVG(FINALAMOUNT) AS AvgAmount,
                COALESCE(REGR_SLOPE(FINALAMOUNT, FISCALPERIODID), 0) AS TrendFactor
            FROM PLANNING.BUDGETLINEITEM
            WHERE BUDGETHEADERID = ?
            GROUP BY GLACCOUNTID, COSTCENTERID
        `, [BASE_BUDGET_HEADER_ID]);
        
        // Apply growth rate or trend
        var growthFactor = GROWTH_RATE_OVERRIDE ? (1 + GROWTH_RATE_OVERRIDE) : 1.0;
        
        executeSQL(`
            UPDATE TEMP_FORECAST_CALC
            SET ForecastAmount = AvgAmount * ?
        `, [growthFactor]);
        
        logStep('Calculate Forecast', 0, 'COMPLETED', 'Method: ' + method);
        
        // Generate forecast line items for each period
        // FIX: Can't use bind variable in LIMIT, use string interpolation
        var periodsRS = executeSQL(`
            SELECT FISCALPERIODID 
            FROM PLANNING.FISCALPERIOD 
            ORDER BY FISCALPERIODID 
            LIMIT ` + fcstPeriods);
        
        var periodIds = [];
        while (periodsRS.next()) {
            periodIds.push(periodsRS.getColumnValue(1));
        }
        
        var totalRows = 0;
        for (var p = 0; p < periodIds.length; p++) {
            var insertRS = executeSQL(`
                INSERT INTO PLANNING.BUDGETLINEITEM (
                    BUDGETHEADERID, GLACCOUNTID, COSTCENTERID, FISCALPERIODID,
                    ORIGINALAMOUNT, ADJUSTEDAMOUNT, FINALAMOUNT, ENTRYTYPE,
                    ISELIMINATED, ALLOCATIONPERCENT
                )
                SELECT 
                    ?,
                    f.GLAccountID,
                    f.CostCenterID,
                    ?,
                    f.ForecastAmount,
                    0,
                    f.ForecastAmount,
                    'FORECAST',
                    FALSE,
                    100
                FROM TEMP_FORECAST_CALC f
            `, [targetId, periodIds[p]]);
            
            totalRows += insertRS.getNumRowsAffected();
        }
        
        result.ROWS_CREATED = totalRows;
        result.PERIODS_FORECASTED = periodIds.length;
        
        executeSQL('COMMIT');
        
        logStep('Generate Forecast Lines', totalRows, 'COMPLETED', 
                periodIds.length + ' periods, ' + totalRows + ' rows');
        
        return result;
        
    } catch (err) {
        try { executeSQL('ROLLBACK'); } catch(e) {}
        logStep('Error', 0, 'ERROR', err.message);
        result.ERROR_MESSAGE = err.message;
        return result;
    }
$$;
