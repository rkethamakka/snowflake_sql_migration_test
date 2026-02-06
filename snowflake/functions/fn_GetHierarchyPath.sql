/*
    fn_GetHierarchyPath - Builds the full hierarchy path string for a cost center
    Dependencies: CostCenter

    Snowflake Migration Notes:
    - Scalar function with WHILE loop → JavaScript UDF
    - SQL Server recursive pattern → JavaScript iteration
    - NVARCHAR → STRING
    - Better approach: Use recursive CTE instead of function, but keeping for compatibility
*/
CREATE OR REPLACE FUNCTION FINANCIAL_PLANNING.PLANNING.fn_GetHierarchyPath(
    COST_CENTER_ID FLOAT,
    DELIMITER STRING
)
RETURNS STRING
LANGUAGE JAVASCRIPT
AS
$$
    if (DELIMITER === null || DELIMITER === undefined) {
        DELIMITER = ' > ';
    }

    var path = '';
    var currentId = COST_CENTER_ID;
    var depth = 0;
    var maxDepth = 20;  // Prevent infinite loops

    // Traverse up the hierarchy
    while (currentId !== null && depth < maxDepth) {
        var stmt = snowflake.createStatement({
            sqlText: `SELECT CostCenterName, ParentCostCenterID
                      FROM FINANCIAL_PLANNING.PLANNING.CostCenter
                      WHERE CostCenterID = :1`,
            binds: [currentId]
        });

        var result = stmt.execute();

        if (result.next()) {
            var name = result.getColumnValue(1);
            var parentId = result.getColumnValue(2);

            if (path === '') {
                path = name;
            } else {
                path = name + DELIMITER + path;
            }

            currentId = parentId;
        } else {
            break;
        }

        depth++;
    }

    return path;
$$;
