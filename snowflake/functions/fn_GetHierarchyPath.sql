CREATE OR REPLACE FUNCTION FINANCIAL_PLANNING.PLANNING.fn_GetHierarchyPath(p_cost_center_id FLOAT)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
SELECT LISTAGG(CostCenterCode, '/') WITHIN GROUP (ORDER BY lvl DESC)
FROM (
    WITH RECURSIVE hierarchy AS (
        SELECT CostCenterID, CostCenterCode, ParentCostCenterID, 1 as lvl
        FROM FINANCIAL_PLANNING.PLANNING.CostCenter
        WHERE CostCenterID = p_cost_center_id
        UNION ALL
        SELECT c.CostCenterID, c.CostCenterCode, c.ParentCostCenterID, h.lvl + 1
        FROM FINANCIAL_PLANNING.PLANNING.CostCenter c
        JOIN hierarchy h ON c.CostCenterID = h.ParentCostCenterID
    )
    SELECT CostCenterCode, lvl FROM hierarchy
)
$$;
