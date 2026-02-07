/*
    fn_GetHierarchyPath - Builds the full hierarchy path string for a cost center
    
    SQL Server → Snowflake Translation:
    - Scalar UDF with WHILE loop → JavaScript UDF
    - @CostCenterID INT → COST_CENTER_ID FLOAT
    - @Delimiter NVARCHAR(5) → DELIMITER VARCHAR(5)
    - RETURNS NVARCHAR(1000) → RETURNS VARCHAR(1000)
    - Recursive logic implemented in JavaScript
*/

CREATE OR REPLACE FUNCTION FINANCIAL_PLANNING.PLANNING.FN_GETHIERARCHYPATH(
    COST_CENTER_ID FLOAT,
    DELIMITER VARCHAR(5)
)
RETURNS VARCHAR(1000)
LANGUAGE JAVASCRIPT
AS
$$
    // Default delimiter if not provided
    var delimiter = DELIMITER || ' > ';
    var path = '';
    var currentId = COST_CENTER_ID;
    var depth = 0;
    var maxDepth = 20;  // Prevent infinite loops
    
    // Prepare query to get cost center details
    var query = `
        SELECT COSTCENTERNAME, PARENTCOSTCENTERID
        FROM FINANCIAL_PLANNING.PLANNING.COSTCENTER
        WHERE COSTCENTERID = ?
    `;
    
    // Traverse up the hierarchy
    while (currentId !== null && currentId !== undefined && depth < maxDepth) {
        var stmt = snowflake.createStatement({
            sqlText: query,
            binds: [currentId]
        });
        
        var result = stmt.execute();
        
        if (!result.next()) {
            break;  // No record found
        }
        
        var name = result.getColumnValue(1);
        var parentId = result.getColumnValue(2);
        
        if (path === '') {
            path = name;
        } else {
            path = name + delimiter + path;
        }
        
        currentId = parentId;
        depth++;
    }
    
    return path;
$$;
