CREATE OR REPLACE FUNCTION FINANCIAL_PLANNING.PLANNING.tvf_ExplodeCostCenterHierarchy(p_root_id FLOAT)
RETURNS TABLE (
    CostCenterID INT,
    CostCenterCode VARCHAR,
    CostCenterName VARCHAR,
    ParentCostCenterID INT,
    HierarchyLevel INT,
    HierarchyPath VARCHAR
)
LANGUAGE SQL
AS
$$
WITH RECURSIVE hierarchy AS (
    SELECT 
        CostCenterID,
        CostCenterCode,
        CostCenterName,
        ParentCostCenterID,
        1 as HierarchyLevel,
        CostCenterCode as HierarchyPath
    FROM FINANCIAL_PLANNING.PLANNING.CostCenter
    WHERE CostCenterID = p_root_id OR (p_root_id IS NULL AND ParentCostCenterID IS NULL)
    
    UNION ALL
    
    SELECT 
        c.CostCenterID,
        c.CostCenterCode,
        c.CostCenterName,
        c.ParentCostCenterID,
        h.HierarchyLevel + 1,
        h.HierarchyPath || '/' || c.CostCenterCode
    FROM FINANCIAL_PLANNING.PLANNING.CostCenter c
    JOIN hierarchy h ON c.ParentCostCenterID = h.CostCenterID
)
SELECT * FROM hierarchy
$$;
