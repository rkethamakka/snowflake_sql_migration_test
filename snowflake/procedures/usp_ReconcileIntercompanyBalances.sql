-- usp_ReconcileIntercompanyBalances - Intercompany reconciliation with JSON reporting
-- Translated from SQL Server to Snowflake JavaScript stored procedure
-- Key changes: XML input/output → JSON, OPENXML → PARSE_JSON, HASHBYTES → SHA2

CREATE OR REPLACE PROCEDURE FINANCIAL_PLANNING.PLANNING.USP_RECONCILEINTERCOMPANYBALANCES(
    BUDGET_HEADER_ID FLOAT,
    RECONCILIATION_DATE DATE,
    ENTITY_CODES_JSON VARCHAR,         -- JSON array instead of XML
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
        RECONCILIATION_ID: null,
        RECONCILIATION_DATE: null,
        STATISTICS: {
            TOTAL_PAIRS: 0,
            RECONCILED: 0,
            UNRECONCILED: 0,
            PARTIAL_MATCH: 0,
            TOTAL_VARIANCE: 0,
            OUT_OF_TOLERANCE_VARIANCE: 0
        },
        ENTITIES: [],
        INTERCOMPANY_PAIRS: [],
        ADJUSTMENTS_CREATED: 0,
        PROCESSING_LOG: []
    };
    
    var toleranceAmt = TOLERANCE_AMOUNT || 0.01;
    var tolerancePct = TOLERANCE_PERCENT || 0.001;
    var effectiveDate = RECONCILIATION_DATE || new Date().toISOString().split('T')[0];
    
    function executeSQL(sql, binds) {
        try {
            var stmt = snowflake.createStatement({sqlText: sql, binds: binds || []});
            var rs = stmt.execute();
            rs.getNumRowsAffected = function() { return stmt.getNumRowsAffected(); };
            return rs;
        } catch (err) {
            throw new Error('SQL failed: ' + err.message + ' | SQL: ' + sql.substring(0, 200));
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
        
        // Generate reconciliation ID
        result.RECONCILIATION_ID = getValue("SELECT UUID_STRING()");
        result.RECONCILIATION_DATE = effectiveDate;
        
        // Create temp tables
        executeSQL(`
            CREATE OR REPLACE TEMPORARY TABLE TEMP_ENTITY_LIST (
                ENTITY_CODE VARCHAR(20),
                ENTITY_NAME VARCHAR(100),
                INCLUDE_FLAG BOOLEAN DEFAULT TRUE
            )
        `);
        
        executeSQL(`
            CREATE OR REPLACE TEMPORARY TABLE TEMP_IC_PAIRS (
                PAIR_ID NUMBER AUTOINCREMENT,
                ENTITY1_CODE VARCHAR(20),
                ENTITY2_CODE VARCHAR(20),
                GL_ACCOUNT_ID NUMBER,
                PARTNER_ACCOUNT_ID NUMBER,
                ENTITY1_AMOUNT NUMBER(19,4),
                ENTITY2_AMOUNT NUMBER(19,4),
                VARIANCE NUMBER(19,4),
                VARIANCE_PERCENT NUMBER(8,6),
                IS_WITHIN_TOLERANCE BOOLEAN,
                RECONCILIATION_STATUS VARCHAR(20),
                MATCH_HASH VARCHAR(64)
            )
        `);
        
        executeSQL(`
            CREATE OR REPLACE TEMPORARY TABLE TEMP_RECON_DETAILS (
                DETAIL_ID NUMBER AUTOINCREMENT,
                PAIR_ID NUMBER,
                SOURCE_LINE_ITEM_ID NUMBER,
                TARGET_LINE_ITEM_ID NUMBER,
                MATCH_TYPE VARCHAR(20),
                MATCH_SCORE NUMBER(5,4),
                MATCH_DETAILS VARCHAR(500)
            )
        `);
        
        // Parse entity list from JSON or get all entities
        var hasEntityJson = false;
        if (ENTITY_CODES_JSON != null && ENTITY_CODES_JSON != undefined) {
            var jsonStr = String(ENTITY_CODES_JSON);
            hasEntityJson = jsonStr.trim() !== '';
        }
        if (hasEntityJson) {
            executeSQL(`
                INSERT INTO TEMP_ENTITY_LIST (ENTITY_CODE, ENTITY_NAME, INCLUDE_FLAG)
                SELECT 
                    f.value:code::VARCHAR,
                    f.value:name::VARCHAR,
                    COALESCE(f.value:include::BOOLEAN, TRUE)
                FROM TABLE(FLATTEN(PARSE_JSON(?))) f
            `, [ENTITY_CODES_JSON]);
        } else {
            // Get all distinct entities from budget data
            executeSQL(`
                INSERT INTO TEMP_ENTITY_LIST (ENTITY_CODE)
                SELECT DISTINCT 
                    SPLIT_PART(cc.COSTCENTERCODE, '-', 1)
                FROM PLANNING.BUDGETLINEITEM bli
                INNER JOIN PLANNING.COSTCENTER cc ON bli.COSTCENTERID = cc.COSTCENTERID
                WHERE bli.BUDGETHEADERID = ?
            `, [BUDGET_HEADER_ID]);
        }
        
        var entityCount = getValue("SELECT COUNT(*) FROM TEMP_ENTITY_LIST");
        logStep('Parse Entity List', entityCount, 'COMPLETED', entityCount + ' entities');
        
        // Identify intercompany pairs and calculate variances
        var pairInsertSql = `
            INSERT INTO TEMP_IC_PAIRS (
                ENTITY1_CODE, ENTITY2_CODE, GL_ACCOUNT_ID, PARTNER_ACCOUNT_ID,
                ENTITY1_AMOUNT, ENTITY2_AMOUNT, VARIANCE, VARIANCE_PERCENT,
                IS_WITHIN_TOLERANCE, RECONCILIATION_STATUS, MATCH_HASH
            )
            SELECT 
                SPLIT_PART(cc1.COSTCENTERCODE, '-', 1) AS E1_CODE,
                COALESCE(SPLIT_PART(cc2.COSTCENTERCODE, '-', 1), '') AS E2_CODE,
                bli1.GLACCOUNTID,
                gla1.CONSOLIDATIONACCOUNTID,
                SUM(bli1.FINALAMOUNT),
                -SUM(COALESCE(bli2.FINALAMOUNT, 0)),
                SUM(bli1.FINALAMOUNT) + SUM(COALESCE(bli2.FINALAMOUNT, 0)),
                CASE 
                    WHEN ABS(SUM(bli1.FINALAMOUNT)) > 0 
                    THEN (SUM(bli1.FINALAMOUNT) + SUM(COALESCE(bli2.FINALAMOUNT, 0))) / ABS(SUM(bli1.FINALAMOUNT))
                    ELSE NULL 
                END,
                CASE 
                    WHEN ABS(SUM(bli1.FINALAMOUNT) + SUM(COALESCE(bli2.FINALAMOUNT, 0))) <= ? THEN TRUE
                    WHEN ABS(SUM(bli1.FINALAMOUNT)) > 0 
                         AND ABS((SUM(bli1.FINALAMOUNT) + SUM(COALESCE(bli2.FINALAMOUNT, 0))) / SUM(bli1.FINALAMOUNT)) <= ? THEN TRUE
                    ELSE FALSE
                END,
                'PENDING',
                SHA2(CONCAT(
                    SPLIT_PART(cc1.COSTCENTERCODE, '-', 1), '|',
                    COALESCE(SPLIT_PART(cc2.COSTCENTERCODE, '-', 1), ''), '|',
                    bli1.GLACCOUNTID::VARCHAR, '|',
                    ABS(ROUND(SUM(bli1.FINALAMOUNT), 0))::VARCHAR
                ), 256)
            FROM PLANNING.BUDGETLINEITEM bli1
            INNER JOIN PLANNING.GLACCOUNT gla1 ON bli1.GLACCOUNTID = gla1.GLACCOUNTID
            INNER JOIN PLANNING.COSTCENTER cc1 ON bli1.COSTCENTERID = cc1.COSTCENTERID
            INNER JOIN TEMP_ENTITY_LIST el1 ON SPLIT_PART(cc1.COSTCENTERCODE, '-', 1) = el1.ENTITY_CODE 
                AND el1.INCLUDE_FLAG = TRUE
            LEFT JOIN PLANNING.BUDGETLINEITEM bli2 
                ON bli2.BUDGETHEADERID = ?
                AND bli2.GLACCOUNTID = gla1.CONSOLIDATIONACCOUNTID
            LEFT JOIN PLANNING.COSTCENTER cc2 ON bli2.COSTCENTERID = cc2.COSTCENTERID
            WHERE bli1.BUDGETHEADERID = ?
              AND gla1.INTERCOMPANYFLAG = TRUE
              AND gla1.CONSOLIDATIONACCOUNTID IS NOT NULL
            GROUP BY 
                SPLIT_PART(cc1.COSTCENTERCODE, '-', 1),
                SPLIT_PART(cc2.COSTCENTERCODE, '-', 1),
                bli1.GLACCOUNTID,
                gla1.CONSOLIDATIONACCOUNTID
            HAVING SUM(bli1.FINALAMOUNT) <> 0 OR SUM(COALESCE(bli2.FINALAMOUNT, 0)) <> 0
        `;
        
        var pairsRs = executeSQL(pairInsertSql, [toleranceAmt, tolerancePct, BUDGET_HEADER_ID, BUDGET_HEADER_ID]);
        var pairCount = pairsRs.getNumRowsAffected();
        logStep('Identify IC Pairs', pairCount, 'COMPLETED', pairCount + ' pairs found');
        
        // Perform detailed matching
        executeSQL(`
            INSERT INTO TEMP_RECON_DETAILS (
                PAIR_ID, SOURCE_LINE_ITEM_ID, TARGET_LINE_ITEM_ID, 
                MATCH_TYPE, MATCH_SCORE, MATCH_DETAILS
            )
            SELECT 
                ip.PAIR_ID,
                bli1.BUDGETLINEITEMID,
                bli2.BUDGETLINEITEMID,
                CASE 
                    WHEN bli1.FINALAMOUNT = -bli2.FINALAMOUNT THEN 'EXACT'
                    WHEN ABS(bli1.FINALAMOUNT + COALESCE(bli2.FINALAMOUNT, 0)) <= ? THEN 'TOLERANCE'
                    WHEN bli2.BUDGETLINEITEMID IS NULL THEN 'UNMATCHED_SOURCE'
                    ELSE 'PARTIAL'
                END,
                CASE 
                    WHEN bli1.FINALAMOUNT = -bli2.FINALAMOUNT THEN 1.0
                    WHEN ABS(bli1.FINALAMOUNT) > 0 
                    THEN 1.0 - ABS((bli1.FINALAMOUNT + COALESCE(bli2.FINALAMOUNT, 0)) / bli1.FINALAMOUNT)
                    ELSE 0
                END,
                CONCAT(
                    'Source: ', TO_CHAR(bli1.FINALAMOUNT, '999,999,999.99'),
                    ' | Target: ', TO_CHAR(COALESCE(bli2.FINALAMOUNT, 0), '999,999,999.99'),
                    ' | Diff: ', TO_CHAR(bli1.FINALAMOUNT + COALESCE(bli2.FINALAMOUNT, 0), '999,999,999.99')
                )
            FROM TEMP_IC_PAIRS ip
            INNER JOIN PLANNING.BUDGETLINEITEM bli1 
                ON bli1.BUDGETHEADERID = ?
                AND bli1.GLACCOUNTID = ip.GL_ACCOUNT_ID
            LEFT JOIN PLANNING.BUDGETLINEITEM bli2
                ON bli2.BUDGETHEADERID = ?
                AND bli2.GLACCOUNTID = ip.PARTNER_ACCOUNT_ID
        `, [toleranceAmt, BUDGET_HEADER_ID, BUDGET_HEADER_ID]);
        
        logStep('Detailed Matching', 0, 'COMPLETED', 'Match details populated');
        
        // Update reconciliation status
        executeSQL(`
            UPDATE TEMP_IC_PAIRS ip
            SET RECONCILIATION_STATUS = 
                CASE 
                    WHEN ip.IS_WITHIN_TOLERANCE = TRUE THEN 'RECONCILED'
                    WHEN EXISTS (
                        SELECT 1 FROM TEMP_RECON_DETAILS rd 
                        WHERE rd.PAIR_ID = ip.PAIR_ID AND rd.MATCH_TYPE = 'EXACT'
                    ) THEN 'MATCHED'
                    WHEN EXISTS (
                        SELECT 1 FROM TEMP_RECON_DETAILS rd 
                        WHERE rd.PAIR_ID = ip.PAIR_ID AND rd.MATCH_TYPE = 'PARTIAL'
                    ) THEN 'PARTIAL_MATCH'
                    ELSE 'UNRECONCILED'
                END
        `);
        
        // Calculate statistics
        var statsRs = executeSQL(`
            SELECT 
                COUNT(*) AS TOTAL_PAIRS,
                SUM(CASE WHEN RECONCILIATION_STATUS = 'RECONCILED' THEN 1 ELSE 0 END) AS RECONCILED,
                SUM(CASE WHEN RECONCILIATION_STATUS = 'UNRECONCILED' THEN 1 ELSE 0 END) AS UNRECONCILED,
                SUM(CASE WHEN RECONCILIATION_STATUS = 'PARTIAL_MATCH' THEN 1 ELSE 0 END) AS PARTIAL_MATCH,
                SUM(ABS(VARIANCE)) AS TOTAL_VARIANCE,
                SUM(CASE WHEN IS_WITHIN_TOLERANCE = FALSE THEN ABS(VARIANCE) ELSE 0 END) AS OOT_VARIANCE
            FROM TEMP_IC_PAIRS
        `);
        
        if (statsRs.next()) {
            result.STATISTICS.TOTAL_PAIRS = statsRs.getColumnValue(1);
            result.STATISTICS.RECONCILED = statsRs.getColumnValue(2);
            result.STATISTICS.UNRECONCILED = statsRs.getColumnValue(3);
            result.STATISTICS.PARTIAL_MATCH = statsRs.getColumnValue(4);
            result.STATISTICS.TOTAL_VARIANCE = statsRs.getColumnValue(5);
            result.STATISTICS.OUT_OF_TOLERANCE_VARIANCE = statsRs.getColumnValue(6);
        }
        
        logStep('Calculate Stats', 0, 'COMPLETED', 
            'Reconciled: ' + result.STATISTICS.RECONCILED + '/' + result.STATISTICS.TOTAL_PAIRS);
        
        // Get entity summary
        var entityRs = executeSQL(`
            SELECT 
                el.ENTITY_CODE,
                el.ENTITY_NAME,
                COUNT(ip.PAIR_ID) AS PAIR_COUNT,
                SUM(ABS(ip.VARIANCE)) AS TOTAL_VARIANCE
            FROM TEMP_ENTITY_LIST el
            LEFT JOIN TEMP_IC_PAIRS ip 
                ON ip.ENTITY1_CODE = el.ENTITY_CODE OR ip.ENTITY2_CODE = el.ENTITY_CODE
            WHERE el.INCLUDE_FLAG = TRUE
            GROUP BY el.ENTITY_CODE, el.ENTITY_NAME
        `);
        
        while (entityRs.next()) {
            result.ENTITIES.push({
                CODE: entityRs.getColumnValue(1),
                NAME: entityRs.getColumnValue(2),
                PAIR_COUNT: entityRs.getColumnValue(3),
                TOTAL_VARIANCE: entityRs.getColumnValue(4)
            });
        }
        
        // Get detailed pairs
        var pairsRs = executeSQL(`
            SELECT 
                ip.PAIR_ID, ip.ENTITY1_CODE, ip.ENTITY2_CODE, ip.RECONCILIATION_STATUS,
                gla.ACCOUNTNUMBER, ip.ENTITY1_AMOUNT, ip.ENTITY2_AMOUNT,
                ip.VARIANCE, ip.VARIANCE_PERCENT, ip.IS_WITHIN_TOLERANCE
            FROM TEMP_IC_PAIRS ip
            INNER JOIN PLANNING.GLACCOUNT gla ON ip.GL_ACCOUNT_ID = gla.GLACCOUNTID
            ORDER BY 
                CASE ip.RECONCILIATION_STATUS 
                    WHEN 'UNRECONCILED' THEN 1 
                    WHEN 'PARTIAL_MATCH' THEN 2 
                    ELSE 3 
                END,
                ABS(ip.VARIANCE) DESC
        `);
        
        while (pairsRs.next()) {
            result.INTERCOMPANY_PAIRS.push({
                PAIR_ID: pairsRs.getColumnValue(1),
                ENTITY1: pairsRs.getColumnValue(2),
                ENTITY2: pairsRs.getColumnValue(3),
                STATUS: pairsRs.getColumnValue(4),
                ACCOUNT: pairsRs.getColumnValue(5),
                AMOUNT1: pairsRs.getColumnValue(6),
                AMOUNT2: pairsRs.getColumnValue(7),
                VARIANCE: pairsRs.getColumnValue(8),
                VARIANCE_PERCENT: pairsRs.getColumnValue(9),
                WITHIN_TOLERANCE: pairsRs.getColumnValue(10)
            });
        }
        
        // Auto-create adjustments if requested
        if (AUTO_CREATE_ADJUSTMENTS) {
            // Note: ConsolidationJournalLine table not available
            // Would insert adjustment entries here
            logStep('Auto Adjustments', 0, 'SKIPPED', 'ConsolidationJournalLine table not available');
        }
        
        // Cleanup temp tables
        executeSQL('DROP TABLE IF EXISTS TEMP_ENTITY_LIST');
        executeSQL('DROP TABLE IF EXISTS TEMP_IC_PAIRS');
        executeSQL('DROP TABLE IF EXISTS TEMP_RECON_DETAILS');
        
        logStep('Cleanup', 0, 'COMPLETED', 'Temp tables dropped');
        
    } catch (err) {
        result.ERROR = {
            MESSAGE: err.message,
            STACK: err.stack
        };
        logStep('Error', 0, 'FAILED', err.message);
    }
    
    return result;
$$;
