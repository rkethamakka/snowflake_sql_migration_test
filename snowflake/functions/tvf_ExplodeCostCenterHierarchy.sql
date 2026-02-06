/*
    tvf_ExplodeCostCenterHierarchy - Recursive CTE to explode hierarchy
    Dependencies: CostCenter

    Snowflake Migration Notes:
    - Multi-statement TVF → View with parameters not supported, converted to table function
    - Table variable → Recursive CTE pattern
    - WHILE loop → Recursive CTE
    - BIT → BOOLEAN
    - NVARCHAR → VARCHAR
    - GETDATE() → CURRENT_DATE()
    - @@ROWCOUNT → Not needed with recursive CTE
    - WITH SCHEMABINDING → Not supported in Snowflake
    - Computed columns (IsLeaf, ChildCount) → Subqueries in SELECT
*/
CREATE OR REPLACE FUNCTION FINANCIAL_PLANNING.PLANNING.tvf_ExplodeCostCenterHierarchy(
    ROOT_COST_CENTER_ID FLOAT,
    MAX_DEPTH FLOAT,
    INCLUDE_INACTIVE BOOLEAN,
    AS_OF_DATE DATE
)
RETURNS TABLE (
    CostCenterID        INTEGER,
    CostCenterCode      VARCHAR(20),
    CostCenterName      VARCHAR(100),
    ParentCostCenterID  INTEGER,
    HierarchyLevel      INTEGER,
    HierarchyPath       VARCHAR(500),
    SortPath            VARCHAR(500),
    IsLeaf              BOOLEAN,
    ChildCount          INTEGER
)
AS
$$
    WITH RECURSIVE hierarchy_tree AS (
        -- Root level
        SELECT
            cc.CostCenterID,
            cc.CostCenterCode,
            cc.CostCenterName,
            cc.ParentCostCenterID,
            0 AS HierarchyLevel,
            CAST(cc.CostCenterName AS VARCHAR(500)) AS HierarchyPath,
            CAST(LPAD(CAST(cc.CostCenterID AS VARCHAR(10)), 10, '0') AS VARCHAR(500)) AS SortPath
        FROM FINANCIAL_PLANNING.PLANNING.CostCenter cc
        WHERE (ROOT_COST_CENTER_ID IS NULL AND cc.ParentCostCenterID IS NULL)
           OR cc.CostCenterID = ROOT_COST_CENTER_ID
          AND (cc.IsActive = TRUE OR INCLUDE_INACTIVE = TRUE)
          AND cc.EffectiveFromDate <= COALESCE(AS_OF_DATE, CURRENT_DATE())
          AND (cc.EffectiveToDate IS NULL OR cc.EffectiveToDate >= COALESCE(AS_OF_DATE, CURRENT_DATE()))

        UNION ALL

        -- Children
        SELECT
            cc.CostCenterID,
            cc.CostCenterCode,
            cc.CostCenterName,
            cc.ParentCostCenterID,
            ht.HierarchyLevel + 1,
            ht.HierarchyPath || ' > ' || cc.CostCenterName,
            ht.SortPath || '/' || LPAD(CAST(cc.CostCenterID AS VARCHAR(10)), 10, '0')
        FROM FINANCIAL_PLANNING.PLANNING.CostCenter cc
        INNER JOIN hierarchy_tree ht ON cc.ParentCostCenterID = ht.CostCenterID
        WHERE ht.HierarchyLevel < COALESCE(MAX_DEPTH, 10) - 1
          AND (cc.IsActive = TRUE OR INCLUDE_INACTIVE = TRUE)
          AND cc.EffectiveFromDate <= COALESCE(AS_OF_DATE, CURRENT_DATE())
          AND (cc.EffectiveToDate IS NULL OR cc.EffectiveToDate >= COALESCE(AS_OF_DATE, CURRENT_DATE()))
    )
    SELECT
        ht.CostCenterID,
        ht.CostCenterCode,
        ht.CostCenterName,
        ht.ParentCostCenterID,
        ht.HierarchyLevel,
        ht.HierarchyPath,
        ht.SortPath,
        -- IsLeaf: check if has children
        NOT EXISTS (
            SELECT 1 FROM FINANCIAL_PLANNING.PLANNING.CostCenter cc2
            WHERE cc2.ParentCostCenterID = ht.CostCenterID
              AND (cc2.IsActive = TRUE OR INCLUDE_INACTIVE = TRUE)
        ) AS IsLeaf,
        -- ChildCount: count direct children
        (
            SELECT COUNT(*)
            FROM hierarchy_tree ht2
            WHERE ht2.ParentCostCenterID = ht.CostCenterID
        ) AS ChildCount
    FROM hierarchy_tree ht
$$;
