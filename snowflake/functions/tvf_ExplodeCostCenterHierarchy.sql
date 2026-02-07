/*
    tvf_ExplodeCostCenterHierarchy - Explodes cost center hierarchy
    Dependencies: CostCenter

    Translation notes:
    - Multi-statement TVF → SQL table function with recursive CTE
    - WHILE loop → Recursive CTE (more efficient in Snowflake)
    - Table variable → CTE result set
    - @AsOfDate parameter for temporal queries
    - Returns TABLE instead of inline table definition
*/

USE DATABASE FINANCIAL_PLANNING;
USE SCHEMA PLANNING;

CREATE OR REPLACE FUNCTION PLANNING.tvf_ExplodeCostCenterHierarchy(
    RootCostCenterID FLOAT,
    MaxDepth FLOAT,
    IncludeInactive BOOLEAN,
    AsOfDate DATE
)
RETURNS TABLE (
    CostCenterID NUMBER(38,0),
    CostCenterCode VARCHAR(20),
    CostCenterName VARCHAR(100),
    ParentCostCenterID NUMBER(38,0),
    HierarchyLevel NUMBER(38,0),
    HierarchyPath VARCHAR(500),
    SortPath VARCHAR(500),
    IsLeaf BOOLEAN,
    ChildCount NUMBER(38,0),
    CumulativeWeight NUMBER(18,10)
)
AS
$$
    WITH RECURSIVE hierarchy_cte AS (
        -- Base case: Root level
        SELECT
            cc.CostCenterID,
            cc.CostCenterCode,
            cc.CostCenterName,
            cc.ParentCostCenterID,
            0 AS HierarchyLevel,
            CAST(cc.CostCenterName AS VARCHAR(500)) AS HierarchyPath,
            CAST(LPAD(cc.CostCenterID::VARCHAR, 10, '0') AS VARCHAR(500)) AS SortPath,
            FALSE AS IsLeaf,
            0 AS ChildCount,
            cc.AllocationWeight AS CumulativeWeight
        FROM PLANNING.CostCenter cc
        WHERE (
                (RootCostCenterID IS NULL AND cc.ParentCostCenterID IS NULL)
                OR cc.CostCenterID = RootCostCenterID
              )
          AND (cc.IsActive = TRUE OR IncludeInactive = TRUE)
          AND cc.EffectiveFromDate <= COALESCE(AsOfDate, CURRENT_DATE())
          AND (cc.EffectiveToDate IS NULL OR cc.EffectiveToDate >= COALESCE(AsOfDate, CURRENT_DATE()))

        UNION ALL

        -- Recursive case: Children
        SELECT
            cc.CostCenterID,
            cc.CostCenterCode,
            cc.CostCenterName,
            cc.ParentCostCenterID,
            h.HierarchyLevel + 1,
            h.HierarchyPath || ' > ' || cc.CostCenterName,
            h.SortPath || '/' || LPAD(cc.CostCenterID::VARCHAR, 10, '0'),
            FALSE AS IsLeaf,
            0 AS ChildCount,
            h.CumulativeWeight * cc.AllocationWeight
        FROM PLANNING.CostCenter cc
        INNER JOIN hierarchy_cte h ON cc.ParentCostCenterID = h.CostCenterID
        WHERE h.HierarchyLevel < MaxDepth - 1
          AND (cc.IsActive = TRUE OR IncludeInactive = TRUE)
          AND cc.EffectiveFromDate <= COALESCE(AsOfDate, CURRENT_DATE())
          AND (cc.EffectiveToDate IS NULL OR cc.EffectiveToDate >= COALESCE(AsOfDate, CURRENT_DATE()))
    ),
    -- Calculate child counts
    hierarchy_with_children AS (
        SELECT
            h.*,
            (SELECT COUNT(*)
             FROM PLANNING.CostCenter cc
             WHERE cc.ParentCostCenterID = h.CostCenterID
               AND (cc.IsActive = TRUE OR IncludeInactive = TRUE)) AS ActualChildCount
        FROM hierarchy_cte h
    )
    SELECT
        CostCenterID,
        CostCenterCode,
        CostCenterName,
        ParentCostCenterID,
        HierarchyLevel,
        HierarchyPath,
        SortPath,
        CASE WHEN ActualChildCount = 0 THEN TRUE ELSE FALSE END AS IsLeaf,
        ActualChildCount AS ChildCount,
        CumulativeWeight
    FROM hierarchy_with_children
$$;
