-- usp_ExecuteCostAllocation - Step-down cost allocation with rule dependencies
-- Translated from SQL Server to Snowflake JavaScript stored procedure

CREATE OR REPLACE PROCEDURE FINANCIAL_PLANNING.PLANNING.USP_EXECUTECOSTALLOCATION(
    BUDGET_HEADER_ID FLOAT,
    ALLOCATION_RULE_IDS VARCHAR,      -- Comma-separated list, NULL = all active rules
    FISCAL_PERIOD_ID FLOAT,           -- NULL = all periods in budget
    DRY_RUN BOOLEAN,
    MAX_ITERATIONS FLOAT,
    USER_ID FLOAT
)
RETURNS VARIANT
LANGUAGE JAVASCRIPT
EXECUTE AS CALLER
AS
$$
    // =========================================================================
    // JavaScript Stored Procedure - Cost Allocation
    // =========================================================================

    var result = {
        ROWS_ALLOCATED: 0,
        RULES_PROCESSED: 0,
        WARNING_MESSAGES: null,
        PROCESSING_LOG: []
    };

    var procStartTime = new Date();
    var currentStep = '';
    var iterationCount = 0;
    var maxIter = MAX_ITERATIONS || 100;

    // Helper function to log steps
    function logStep(stepName, startTime, rowsAffected, status, message) {
        result.PROCESSING_LOG.push({
            STEP_NAME: stepName,
            START_TIME: startTime.toISOString(),
            END_TIME: new Date().toISOString(),
            ROWS_AFFECTED: rowsAffected,
            STATUS_CODE: status,
            MESSAGE: message || null
        });
    }

    // Helper to execute SQL and return result set
    function executeSQL(sql, binds) {
        try {
            var stmt = snowflake.createStatement({
                sqlText: sql,
                binds: binds || []
            });
            var rs = stmt.execute();
            rs.getNumRowsAffected = function() { return stmt.getNumRowsAffected(); };
            return rs;
        } catch (err) {
            throw new Error('SQL failed: ' + err.message + '\nSQL: ' + sql.substring(0, 200));
        }
    }

    // Helper to get single value
    function getValue(sql, binds) {
        var rs = executeSQL(sql, binds);
        if (rs.next()) {
            return rs.getColumnValue(1);
        }
        return null;
    }

    try {
        // Set database context
        executeSQL('USE DATABASE FINANCIAL_PLANNING');
        executeSQL('USE SCHEMA PLANNING');

        // =====================================================================
        // Step 1: Get allocation rules
        // =====================================================================
        currentStep = 'Get Allocation Rules';
        var stepStartTime = new Date();

        var rulesSQL;
        if (ALLOCATION_RULE_IDS) {
            // Parse comma-separated list
            rulesSQL = `
                SELECT ar.ALLOCATIONRULEID, ar.RULENAME, ar.SOURCECOSTCENTERID,
                       ar.SOURCEGLACCOUNTID, ar.ALLOCATIONMETHOD, ar.ALLOCATIONBASIS,
                       ar.ALLOCATIONPERCENT, ar.PRIORITY, ar.TARGETCOSTCENTERID
                FROM PLANNING.ALLOCATIONRULE ar
                WHERE ar.ISACTIVE = TRUE
                  AND ar.ALLOCATIONRULEID IN (
                      SELECT TRY_TO_NUMBER(TRIM(value)) 
                      FROM TABLE(SPLIT_TO_TABLE('${ALLOCATION_RULE_IDS}', ','))
                  )
                ORDER BY ar.PRIORITY, ar.ALLOCATIONRULEID
            `;
        } else {
            rulesSQL = `
                SELECT ar.ALLOCATIONRULEID, ar.RULENAME, ar.SOURCECOSTCENTERID,
                       ar.SOURCEGLACCOUNTID, ar.ALLOCATIONMETHOD, ar.ALLOCATIONBASIS,
                       ar.ALLOCATIONPERCENT, ar.PRIORITY, ar.TARGETCOSTCENTERID
                FROM PLANNING.ALLOCATIONRULE ar
                WHERE ar.ISACTIVE = TRUE
                  AND CURRENT_DATE BETWEEN ar.EFFECTIVEFROMDATE 
                      AND COALESCE(ar.EFFECTIVETODATE, '9999-12-31')
                ORDER BY ar.PRIORITY, ar.ALLOCATIONRULEID
            `;
        }

        var rulesRS = executeSQL(rulesSQL);
        var rules = [];
        while (rulesRS.next()) {
            rules.push({
                ruleId: rulesRS.getColumnValue(1),
                ruleName: rulesRS.getColumnValue(2),
                sourceCostCenterId: rulesRS.getColumnValue(3),
                sourceGLAccountId: rulesRS.getColumnValue(4),
                method: rulesRS.getColumnValue(5),
                basis: rulesRS.getColumnValue(6),
                percent: rulesRS.getColumnValue(7),
                priority: rulesRS.getColumnValue(8),
                targetCostCenterId: rulesRS.getColumnValue(9)  // FIX: Added explicit target
            });
        }

        logStep(currentStep, stepStartTime, rules.length, 'COMPLETED', 'Found ' + rules.length + ' rules');

        if (rules.length === 0) {
            result.WARNING_MESSAGES = 'No active allocation rules found';
            return result;
        }

        // =====================================================================
        // Step 2: Create temp tables
        // =====================================================================
        currentStep = 'Create Temp Tables';
        stepStartTime = new Date();

        executeSQL(`
            CREATE TEMPORARY TABLE IF NOT EXISTS TEMP_ALLOCATION_QUEUE (
                QueueID FLOAT,
                AllocationRuleID FLOAT,
                SourceBudgetLineItemID FLOAT,
                SourceAmount FLOAT,
                TargetCostCenterID FLOAT,
                AllocationPercent FLOAT,
                AllocatedAmount FLOAT,
                IsProcessed BOOLEAN DEFAULT FALSE
            )
        `);
        executeSQL('DELETE FROM TEMP_ALLOCATION_QUEUE');

        executeSQL(`
            CREATE TEMPORARY TABLE IF NOT EXISTS TEMP_ALLOCATION_RESULTS (
                ResultID FLOAT,
                SourceBudgetLineItemID FLOAT,
                TargetCostCenterID FLOAT,
                TargetGLAccountID FLOAT,
                AllocatedAmount FLOAT,
                AllocationRuleID FLOAT
            )
        `);
        executeSQL('DELETE FROM TEMP_ALLOCATION_RESULTS');

        logStep(currentStep, stepStartTime, 0, 'COMPLETED', null);

        // =====================================================================
        // Step 3: Build allocation queue
        // =====================================================================
        currentStep = 'Build Allocation Queue';
        stepStartTime = new Date();

        var queueId = 0;
        var totalQueued = 0;

        for (var r = 0; r < rules.length; r++) {
            var rule = rules[r];

            // Find matching budget line items for this rule
            var periodFilter = FISCAL_PERIOD_ID ? 'AND bli.FISCALPERIODID = ' + FISCAL_PERIOD_ID : '';
            var ccFilter = rule.sourceCostCenterId ? 'AND bli.COSTCENTERID = ' + rule.sourceCostCenterId : '';
            var acctFilter = rule.sourceGLAccountId ? 'AND bli.GLACCOUNTID = ' + rule.sourceGLAccountId : '';

            var matchSQL = `
                SELECT bli.BUDGETLINEITEMID, bli.FINALAMOUNT, bli.COSTCENTERID, bli.GLACCOUNTID
                FROM PLANNING.BUDGETLINEITEM bli
                WHERE bli.BUDGETHEADERID = ${BUDGET_HEADER_ID}
                  AND bli.FINALAMOUNT <> 0
                  AND COALESCE(bli.ISELIMINATED, FALSE) = FALSE
                  ${periodFilter}
                  ${ccFilter}
                  ${acctFilter}
            `;

            var matchRS = executeSQL(matchSQL);

            while (matchRS.next()) {
                queueId++;
                var lineItemId = matchRS.getColumnValue(1);
                var amount = matchRS.getColumnValue(2);
                var sourceCCId = matchRS.getColumnValue(3);

                // FIX: Use explicit TARGETCOSTCENTERID from rule (not hierarchy)
                // This matches SQL Server behavior using vw_AllocationRuleTargets
                var targetCCId = rule.targetCostCenterId;
                var allocPct = rule.percent / 100.0;
                var allocAmt = amount * allocPct;

                if (targetCCId) {

                    executeSQL(`
                        INSERT INTO TEMP_ALLOCATION_QUEUE
                        (QueueID, AllocationRuleID, SourceBudgetLineItemID, SourceAmount,
                         TargetCostCenterID, AllocationPercent, AllocatedAmount, IsProcessed)
                        VALUES (?, ?, ?, ?, ?, ?, ?, FALSE)
                    `, [queueId, rule.ruleId, lineItemId, amount, targetCCId, allocPct, allocAmt]);

                    totalQueued++;
                }
            }
        }

        logStep(currentStep, stepStartTime, totalQueued, 'COMPLETED', 'Queued ' + totalQueued + ' allocations');

        // =====================================================================
        // Step 4: Process allocations
        // =====================================================================
        currentStep = 'Process Allocations';
        stepStartTime = new Date();

        // Begin transaction
        executeSQL('BEGIN TRANSACTION');

        if (!DRY_RUN) {
            // Insert allocated amounts as new budget line items
            var insertSQL = `
                INSERT INTO PLANNING.BUDGETLINEITEM (
                    BUDGETHEADERID, GLACCOUNTID, COSTCENTERID, FISCALPERIODID,
                    ORIGINALAMOUNT, ADJUSTEDAMOUNT, FINALAMOUNT,
                    ENTRYTYPE, ISELIMINATED, ALLOCATIONPERCENT
                )
                SELECT
                    ${BUDGET_HEADER_ID},
                    bli.GLACCOUNTID,
                    q.TargetCostCenterID,
                    bli.FISCALPERIODID,
                    q.AllocatedAmount,
                    0,
                    q.AllocatedAmount,
                    'ALLOCATED',
                    FALSE,
                    q.AllocationPercent * 100
                FROM TEMP_ALLOCATION_QUEUE q
                INNER JOIN PLANNING.BUDGETLINEITEM bli
                    ON q.SourceBudgetLineItemID = bli.BUDGETLINEITEMID
                WHERE q.IsProcessed = FALSE
            `;

            var insertRS = executeSQL(insertSQL);
            result.ROWS_ALLOCATED = insertRS.getNumRowsAffected();

            // Mark queue items as processed
            executeSQL('UPDATE TEMP_ALLOCATION_QUEUE SET IsProcessed = TRUE');
        } else {
            // Dry run - just count
            result.ROWS_ALLOCATED = getValue('SELECT COUNT(*) FROM TEMP_ALLOCATION_QUEUE');
        }

        result.RULES_PROCESSED = rules.length;

        // Commit
        executeSQL('COMMIT');

        logStep(currentStep, stepStartTime, result.ROWS_ALLOCATED, 'COMPLETED',
                'Allocated ' + result.ROWS_ALLOCATED + ' rows');

        return result;

    } catch (err) {
        result.WARNING_MESSAGES = err.message;

        try {
            executeSQL('ROLLBACK');
        } catch (e) {}

        logStep(currentStep, stepStartTime || new Date(), 0, 'ERROR', err.message);

        return result;
    }
$$;
