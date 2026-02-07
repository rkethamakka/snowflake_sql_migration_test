/*
    fn_GetHierarchyPath - Builds the full hierarchy path string for a cost center
    Dependencies: CostCenter

    Translation notes:
    - Scalar UDF with WHILE loop → JavaScript UDF
    - NVARCHAR → VARCHAR (Snowflake VARCHAR is Unicode)
    - Variable declarations become JavaScript variables
    - SQL queries via snowflake.createStatement()
*/

USE DATABASE FINANCIAL_PLANNING;
USE SCHEMA PLANNING;

CREATE OR REPLACE FUNCTION PLANNING.fn_GetHierarchyPath(
    CostCenterID FLOAT,
    Delimiter VARCHAR
)
RETURNS VARCHAR
LANGUAGE JAVASCRIPT
AS
$$
    // Default delimiter if not provided
    var delimiter = DELIMITER || ' > ';
    var path = '';
    var currentId = COSTCENTERID;
    var depth = 0;
    var maxDepth = 20; // Prevent infinite loops

    // Traverse up the hierarchy
    while (currentId != null && depth < maxDepth) {
        var stmt = snowflake.createStatement({
            sqlText: `SELECT CostCenterName, ParentCostCenterID
                      FROM PLANNING.CostCenter
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
                path = name + delimiter + path;
            }

            currentId = parentId;
            depth++;
        } else {
            // No record found, exit loop
            currentId = null;
        }
    }

    return path;
$$;
