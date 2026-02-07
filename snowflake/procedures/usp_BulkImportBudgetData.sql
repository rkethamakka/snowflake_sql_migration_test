-- usp_BulkImportBudgetData - Bulk import budget data with validation
-- Translated from SQL Server to Snowflake JavaScript stored procedure

CREATE OR REPLACE PROCEDURE FINANCIAL_PLANNING.PLANNING.USP_BULKIMPORTBUDGETDATA(
    IMPORT_SOURCE VARCHAR,           -- STAGING_TABLE, VARIANT_DATA
    TARGET_BUDGET_HEADER_ID FLOAT,
    VALIDATION_MODE VARCHAR,         -- STRICT, LENIENT, NONE
    DUPLICATE_HANDLING VARCHAR,      -- REJECT, UPDATE, SKIP
    BATCH_SIZE FLOAT,
    SOURCE_DATA VARIANT              -- JSON array of line items
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    var result = {
        ROWS_IMPORTED: 0,
        ROWS_REJECTED: 0,
        VALIDATION_ERRORS: [],
        PROCESSING_LOG: []
    };
    
    var startTime = new Date();
    
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
            STEP: step, ROWS: rows, STATUS: status, MESSAGE: msg,
            TIMESTAMP: new Date().toISOString()
        });
    }
    
    try {
        executeSQL('USE DATABASE FINANCIAL_PLANNING');
        executeSQL('USE SCHEMA PLANNING');
        
        // Create staging temp table
        executeSQL(`
            CREATE TEMPORARY TABLE IF NOT EXISTS TEMP_IMPORT_STAGING (
                RowNum FLOAT,
                GLAccountID FLOAT,
                CostCenterID FLOAT,
                FiscalPeriodID FLOAT,
                Amount FLOAT,
                EntryType VARCHAR,
                IsValid BOOLEAN DEFAULT TRUE,
                ValidationError VARCHAR
            )
        `);
        executeSQL('DELETE FROM TEMP_IMPORT_STAGING');
        
        logStep('Create Staging', 0, 'COMPLETED', null);
        
        // Parse and load source data
        if (IMPORT_SOURCE === 'VARIANT_DATA' && SOURCE_DATA) {
            var items = SOURCE_DATA;
            for (var i = 0; i < items.length; i++) {
                var item = items[i];
                executeSQL(`
                    INSERT INTO TEMP_IMPORT_STAGING 
                    (RowNum, GLAccountID, CostCenterID, FiscalPeriodID, Amount, EntryType)
                    VALUES (?, ?, ?, ?, ?, ?)
                `, [i+1, item.GLAccountID, item.CostCenterID, item.FiscalPeriodID, 
                    item.Amount, item.EntryType || 'IMPORTED']);
            }
            logStep('Load Data', items.length, 'COMPLETED', 'Loaded ' + items.length + ' rows');
        }
        
        // Validation
        if (VALIDATION_MODE !== 'NONE') {
            // Validate GL Accounts exist
            executeSQL(`
                UPDATE TEMP_IMPORT_STAGING s
                SET IsValid = FALSE, ValidationError = 'Invalid GLAccountID'
                WHERE NOT EXISTS (
                    SELECT 1 FROM PLANNING.GLACCOUNT g WHERE g.GLACCOUNTID = s.GLAccountID
                )
            `);
            
            // Validate Cost Centers exist
            executeSQL(`
                UPDATE TEMP_IMPORT_STAGING s
                SET IsValid = FALSE, ValidationError = COALESCE(ValidationError || '; ', '') || 'Invalid CostCenterID'
                WHERE NOT EXISTS (
                    SELECT 1 FROM PLANNING.COSTCENTER c WHERE c.COSTCENTERID = s.CostCenterID
                )
            `);
            
            logStep('Validation', 0, 'COMPLETED', null);
        }
        
        // Count valid/invalid
        var validRS = executeSQL('SELECT COUNT(*) FROM TEMP_IMPORT_STAGING WHERE IsValid = TRUE');
        validRS.next();
        var validCount = validRS.getColumnValue(1);
        
        var invalidRS = executeSQL('SELECT COUNT(*) FROM TEMP_IMPORT_STAGING WHERE IsValid = FALSE');
        invalidRS.next();
        var invalidCount = invalidRS.getColumnValue(1);
        
        result.ROWS_REJECTED = invalidCount;
        
        // Insert valid rows
        executeSQL('BEGIN TRANSACTION');
        
        var insertSQL = `
            INSERT INTO PLANNING.BUDGETLINEITEM (
                BUDGETHEADERID, GLACCOUNTID, COSTCENTERID, FISCALPERIODID,
                ORIGINALAMOUNT, ADJUSTEDAMOUNT, FINALAMOUNT, ENTRYTYPE,
                ISELIMINATED, ALLOCATIONPERCENT
            )
            SELECT 
                ?,
                s.GLAccountID,
                s.CostCenterID,
                s.FiscalPeriodID,
                s.Amount,
                0,
                s.Amount,
                s.EntryType,
                FALSE,
                100
            FROM TEMP_IMPORT_STAGING s
            WHERE s.IsValid = TRUE
        `;
        
        var insertRS = executeSQL(insertSQL, [TARGET_BUDGET_HEADER_ID]);
        result.ROWS_IMPORTED = insertRS.getNumRowsAffected();
        
        executeSQL('COMMIT');
        
        logStep('Import', result.ROWS_IMPORTED, 'COMPLETED', 
                'Imported ' + result.ROWS_IMPORTED + ', Rejected ' + result.ROWS_REJECTED);
        
        return result;
        
    } catch (err) {
        try { executeSQL('ROLLBACK'); } catch(e) {}
        result.VALIDATION_ERRORS.push(err.message);
        logStep('Error', 0, 'ERROR', err.message);
        return result;
    }
$$;
