-- fn_GetAllocationFactor - Calculates allocation factor based on various drivers
-- Translated from SQL Server to Snowflake JavaScript UDF

CREATE OR REPLACE FUNCTION FINANCIAL_PLANNING.PLANNING.FN_GETALLOCATIONFACTOR(
    SOURCE_COST_CENTER_ID FLOAT,
    TARGET_COST_CENTER_ID FLOAT,
    ALLOCATION_BASIS VARCHAR,
    FISCAL_PERIOD_ID FLOAT,
    BUDGET_HEADER_ID FLOAT
)
RETURNS FLOAT
LANGUAGE JAVASCRIPT
AS
$$
    // Helper to execute SQL and get single value
    function getValue(sql) {
        try {
            var stmt = snowflake.createStatement({sqlText: sql});
            var rs = stmt.execute();
            if (rs.next()) {
                return rs.getColumnValue(1);
            }
            return null;
        } catch (e) {
            return null;
        }
    }
    
    var factor = 0;
    var sourceTotal = null;
    var targetValue = null;
    
    if (ALLOCATION_BASIS === 'HEADCOUNT') {
        // Get headcount from cost center attributes
        sourceTotal = getValue(`
            SELECT SUM(ALLOCATIONWEIGHT)
            FROM FINANCIAL_PLANNING.PLANNING.COSTCENTER
            WHERE PARENTCOSTCENTERID = ${SOURCE_COST_CENTER_ID}
              AND ISACTIVE = TRUE
        `);
        
        targetValue = getValue(`
            SELECT ALLOCATIONWEIGHT
            FROM FINANCIAL_PLANNING.PLANNING.COSTCENTER
            WHERE COSTCENTERID = ${TARGET_COST_CENTER_ID}
              AND ISACTIVE = TRUE
        `);
    }
    else if (ALLOCATION_BASIS === 'REVENUE') {
        // Revenue-based allocation
        var budgetFilter = BUDGET_HEADER_ID ? `AND bli.BUDGETHEADERID = ${BUDGET_HEADER_ID}` : '';
        
        sourceTotal = getValue(`
            SELECT SUM(bli.FINALAMOUNT)
            FROM FINANCIAL_PLANNING.PLANNING.BUDGETLINEITEM bli
            INNER JOIN FINANCIAL_PLANNING.PLANNING.GLACCOUNT gla ON bli.GLACCOUNTID = gla.GLACCOUNTID
            INNER JOIN FINANCIAL_PLANNING.PLANNING.COSTCENTER cc ON bli.COSTCENTERID = cc.COSTCENTERID
            WHERE (cc.PARENTCOSTCENTERID = ${SOURCE_COST_CENTER_ID} OR cc.COSTCENTERID = ${SOURCE_COST_CENTER_ID})
              AND gla.ACCOUNTTYPE = 'R'
              AND bli.FISCALPERIODID = ${FISCAL_PERIOD_ID}
              ${budgetFilter}
        `);
        
        targetValue = getValue(`
            SELECT SUM(bli.FINALAMOUNT)
            FROM FINANCIAL_PLANNING.PLANNING.BUDGETLINEITEM bli
            INNER JOIN FINANCIAL_PLANNING.PLANNING.GLACCOUNT gla ON bli.GLACCOUNTID = gla.GLACCOUNTID
            WHERE bli.COSTCENTERID = ${TARGET_COST_CENTER_ID}
              AND gla.ACCOUNTTYPE = 'R'
              AND bli.FISCALPERIODID = ${FISCAL_PERIOD_ID}
              ${budgetFilter}
        `);
    }
    else if (ALLOCATION_BASIS === 'EXPENSE') {
        var budgetFilter = BUDGET_HEADER_ID ? `AND bli.BUDGETHEADERID = ${BUDGET_HEADER_ID}` : '';
        
        sourceTotal = getValue(`
            SELECT SUM(bli.FINALAMOUNT)
            FROM FINANCIAL_PLANNING.PLANNING.BUDGETLINEITEM bli
            INNER JOIN FINANCIAL_PLANNING.PLANNING.GLACCOUNT gla ON bli.GLACCOUNTID = gla.GLACCOUNTID
            INNER JOIN FINANCIAL_PLANNING.PLANNING.COSTCENTER cc ON bli.COSTCENTERID = cc.COSTCENTERID
            WHERE (cc.PARENTCOSTCENTERID = ${SOURCE_COST_CENTER_ID} OR cc.COSTCENTERID = ${SOURCE_COST_CENTER_ID})
              AND gla.ACCOUNTTYPE = 'E'
              AND bli.FISCALPERIODID = ${FISCAL_PERIOD_ID}
              ${budgetFilter}
        `);
        
        targetValue = getValue(`
            SELECT SUM(bli.FINALAMOUNT)
            FROM FINANCIAL_PLANNING.PLANNING.BUDGETLINEITEM bli
            INNER JOIN FINANCIAL_PLANNING.PLANNING.GLACCOUNT gla ON bli.GLACCOUNTID = gla.GLACCOUNTID
            WHERE bli.COSTCENTERID = ${TARGET_COST_CENTER_ID}
              AND gla.ACCOUNTTYPE = 'E'
              AND bli.FISCALPERIODID = ${FISCAL_PERIOD_ID}
              ${budgetFilter}
        `);
    }
    else if (ALLOCATION_BASIS === 'EQUAL') {
        // Equal distribution among all children
        var childCount = getValue(`
            SELECT COUNT(*)
            FROM FINANCIAL_PLANNING.PLANNING.COSTCENTER
            WHERE PARENTCOSTCENTERID = ${SOURCE_COST_CENTER_ID}
              AND ISACTIVE = TRUE
        `);
        
        if (childCount && childCount > 0) {
            return 1.0 / childCount;
        }
        return 0;
    }
    else if (ALLOCATION_BASIS === 'FIXED') {
        // Fixed percentage - factor comes from AllocationRule.AllocationPercent
        return 1.0;  // The percentage is applied by caller
    }
    
    // Calculate factor with null protection
    if (sourceTotal !== null && sourceTotal !== 0 && targetValue !== null) {
        factor = targetValue / sourceTotal;
    }
    
    return factor;
$$;
