SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('Planning.fn_GetAllocationFactor', 'FN') IS NOT NULL
    DROP FUNCTION Planning.fn_GetAllocationFactor;
GO

/*
    fn_GetAllocationFactor - Calculates allocation factor based on various drivers
    FIXED VERSION: Added 'FIXED' allocation basis handler
    Dependencies: CostCenter, BudgetLineItem, AllocationRule, vw_AllocationRuleTargets
    
    Challenges for Snowflake migration:
    - Scalar UDF performance characteristics differ significantly
    - Snowflake UDFs are Python/JavaScript/SQL, not T-SQL
    - Cross-database queries via synonyms not supported
    - The recursive hierarchy traversal pattern needs refactoring
*/
CREATE FUNCTION Planning.fn_GetAllocationFactor (
    @SourceCostCenterID     INT,
    @TargetCostCenterID     INT,
    @AllocationBasis        VARCHAR(30),
    @FiscalPeriodID         INT,
    @BudgetHeaderID         INT = NULL
)
RETURNS DECIMAL(18,10)
-- FIX: Removed SCHEMABINDING to allow reference to vw_AllocationRuleTargets
-- WITH SCHEMABINDING, RETURNS NULL ON NULL INPUT
AS
BEGIN
    DECLARE @Factor DECIMAL(18,10) = 0;
    DECLARE @SourceTotal DECIMAL(19,4);
    DECLARE @TargetValue DECIMAL(19,4);
    
    -- Different allocation bases require different calculations
    IF @AllocationBasis = 'HEADCOUNT'
    BEGIN
        -- Get headcount from cost center attributes (simplified)
        SELECT @SourceTotal = SUM(cc.AllocationWeight)
        FROM Planning.CostCenter cc
        WHERE cc.ParentCostCenterID = @SourceCostCenterID
          AND cc.IsActive = 1;
        
        SELECT @TargetValue = cc.AllocationWeight
        FROM Planning.CostCenter cc
        WHERE cc.CostCenterID = @TargetCostCenterID
          AND cc.IsActive = 1;
    END
    ELSE IF @AllocationBasis = 'REVENUE'
    BEGIN
        -- Revenue-based allocation from budget line items
        SELECT @SourceTotal = SUM(bli.FinalAmount)
        FROM Planning.BudgetLineItem bli
        INNER JOIN Planning.GLAccount gla ON bli.GLAccountID = gla.GLAccountID
        INNER JOIN Planning.CostCenter cc ON bli.CostCenterID = cc.CostCenterID
        WHERE (cc.ParentCostCenterID = @SourceCostCenterID OR cc.CostCenterID = @SourceCostCenterID)
          AND gla.AccountType = 'R'
          AND bli.FiscalPeriodID = @FiscalPeriodID
          AND (@BudgetHeaderID IS NULL OR bli.BudgetHeaderID = @BudgetHeaderID);
        
        SELECT @TargetValue = SUM(bli.FinalAmount)
        FROM Planning.BudgetLineItem bli
        INNER JOIN Planning.GLAccount gla ON bli.GLAccountID = gla.GLAccountID
        WHERE bli.CostCenterID = @TargetCostCenterID
          AND gla.AccountType = 'R'
          AND bli.FiscalPeriodID = @FiscalPeriodID
          AND (@BudgetHeaderID IS NULL OR bli.BudgetHeaderID = @BudgetHeaderID);
    END
    ELSE IF @AllocationBasis = 'EXPENSE'
    BEGIN
        SELECT @SourceTotal = SUM(bli.FinalAmount)
        FROM Planning.BudgetLineItem bli
        INNER JOIN Planning.GLAccount gla ON bli.GLAccountID = gla.GLAccountID
        INNER JOIN Planning.CostCenter cc ON bli.CostCenterID = cc.CostCenterID
        WHERE (cc.ParentCostCenterID = @SourceCostCenterID OR cc.CostCenterID = @SourceCostCenterID)
          AND gla.AccountType = 'X'
          AND bli.FiscalPeriodID = @FiscalPeriodID
          AND (@BudgetHeaderID IS NULL OR bli.BudgetHeaderID = @BudgetHeaderID);
        
        SELECT @TargetValue = SUM(bli.FinalAmount)
        FROM Planning.BudgetLineItem bli
        INNER JOIN Planning.GLAccount gla ON bli.GLAccountID = gla.GLAccountID
        WHERE bli.CostCenterID = @TargetCostCenterID
          AND gla.AccountType = 'X'
          AND bli.FiscalPeriodID = @FiscalPeriodID
          AND (@BudgetHeaderID IS NULL OR bli.BudgetHeaderID = @BudgetHeaderID);
    END
    ELSE IF @AllocationBasis = 'EQUAL'
    BEGIN
        -- Equal distribution among all children
        DECLARE @ChildCount INT;
        SELECT @ChildCount = COUNT(*)
        FROM Planning.CostCenter cc
        WHERE cc.ParentCostCenterID = @SourceCostCenterID
          AND cc.IsActive = 1;
        
        IF @ChildCount > 0
            SET @Factor = 1.0 / @ChildCount;
        
        RETURN @Factor;
    END
    ELSE IF @AllocationBasis = 'FIXED'
    BEGIN
        -- FIX: For FIXED allocations, look up the target percentage from vw_AllocationRuleTargets
        -- Match based on source cost center and target cost center
        SELECT @Factor = vt.TargetAllocationPct
        FROM Planning.vw_AllocationRuleTargets vt
        INNER JOIN Planning.AllocationRule ar ON vt.AllocationRuleID = ar.AllocationRuleID
        WHERE ar.SourceCostCenterID = @SourceCostCenterID
          AND vt.TargetCostCenterID = @TargetCostCenterID
          AND ar.IsActive = 1;
        
        IF @Factor IS NULL SET @Factor = 0;
        RETURN @Factor;
    END
    
    -- Calculate factor with null protection
    IF @SourceTotal IS NOT NULL AND @SourceTotal <> 0 AND @TargetValue IS NOT NULL
        SET @Factor = @TargetValue / @SourceTotal;
    
    RETURN @Factor;
END
GO
