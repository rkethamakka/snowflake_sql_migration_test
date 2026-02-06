/*
    FIXED VERSION - Created by sql-migration-verify skill
    
    BUG FIXED: Dynamic SQL cannot access table variables.
    The original used sp_executesql to UPDATE @ConsolidatedAmounts, 
    but table variables are not accessible in dynamic SQL scope.
    
    FIX: Replace dynamic SQL with direct UPDATE statement.
*/
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE Planning.usp_ProcessBudgetConsolidation
    @SourceBudgetHeaderID       INT,
    @TargetBudgetHeaderID       INT = NULL OUTPUT,
    @ConsolidationType          VARCHAR(20) = 'FULL',
    @IncludeEliminations        BIT = 1,
    @RecalculateAllocations     BIT = 1,
    @ProcessingOptions          XML = NULL,
    @UserID                     INT = NULL,
    @DebugMode                  BIT = 0,
    @RowsProcessed              INT = NULL OUTPUT,
    @ErrorMessage               NVARCHAR(4000) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT OFF;
    
    DECLARE @ProcStartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @StepStartTime DATETIME2;
    DECLARE @CurrentStep NVARCHAR(100);
    DECLARE @ReturnCode INT = 0;
    DECLARE @TotalRowsProcessed INT = 0;
    DECLARE @ConsolidationRunID UNIQUEIDENTIFIER = NEWID();
    
    DECLARE @ProcessingLog TABLE (
        LogID INT IDENTITY(1,1) PRIMARY KEY,
        StepName NVARCHAR(100),
        StartTime DATETIME2,
        EndTime DATETIME2,
        RowsAffected INT,
        StatusCode VARCHAR(20)
    );
    
    DECLARE @HierarchyNodes TABLE (
        NodeID INT PRIMARY KEY,
        ParentNodeID INT,
        NodeLevel INT,
        IsProcessed BIT DEFAULT 0,
        SubtotalAmount DECIMAL(19,4)
    );
    
    DECLARE @ConsolidatedAmounts TABLE (
        GLAccountID INT NOT NULL,
        CostCenterID INT NOT NULL,
        FiscalPeriodID INT NOT NULL,
        ConsolidatedAmount DECIMAL(19,4) NOT NULL DEFAULT 0,
        EliminationAmount DECIMAL(19,4) DEFAULT 0,
        FinalAmount DECIMAL(19,4),
        SourceCount INT,
        PRIMARY KEY (GLAccountID, CostCenterID, FiscalPeriodID)
    );
    
    BEGIN TRY
        SET @CurrentStep = 'Create Target Budget';
        SET @StepStartTime = SYSUTCDATETIME();
        
        BEGIN TRANSACTION;
        
        INSERT INTO Planning.BudgetHeader (
            BudgetCode, BudgetName, BudgetType, ScenarioType, FiscalYear,
            StartPeriodID, EndPeriodID, BaseBudgetHeaderID, StatusCode, VersionNumber
        )
        SELECT 
            BudgetCode + '_CONSOL_' + FORMAT(GETDATE(), 'yyyyMMdd'),
            BudgetName + ' - Consolidated',
            'CONSOL',
            ScenarioType,
            FiscalYear,
            StartPeriodID,
            EndPeriodID,
            BudgetHeaderID,
            'DRAFT',
            1
        FROM Planning.BudgetHeader
        WHERE BudgetHeaderID = @SourceBudgetHeaderID;
        
        SET @TargetBudgetHeaderID = SCOPE_IDENTITY();
        
        INSERT INTO @ProcessingLog (StepName, StartTime, EndTime, RowsAffected, StatusCode)
        VALUES (@CurrentStep, @StepStartTime, SYSUTCDATETIME(), 1, 'COMPLETED');
        
        -- Build hierarchy
        SET @CurrentStep = 'Build Hierarchy';
        SET @StepStartTime = SYSUTCDATETIME();
        
        INSERT INTO @HierarchyNodes (NodeID, ParentNodeID, NodeLevel)
        SELECT 
            CostCenterID,
            ParentCostCenterID,
            0  -- Will update level in next step
        FROM Planning.CostCenter
        WHERE IsActive = 1;
        
        -- Calculate levels
        DECLARE @Level INT = 0;
        UPDATE @HierarchyNodes SET NodeLevel = 0 WHERE ParentNodeID IS NULL;
        
        WHILE EXISTS (SELECT 1 FROM @HierarchyNodes WHERE NodeLevel IS NULL OR NodeLevel = 0 AND ParentNodeID IS NOT NULL)
        BEGIN
            SET @Level = @Level + 1;
            UPDATE h
            SET NodeLevel = @Level
            FROM @HierarchyNodes h
            JOIN @HierarchyNodes p ON h.ParentNodeID = p.NodeID
            WHERE p.NodeLevel = @Level - 1 AND h.NodeLevel = 0 AND h.ParentNodeID IS NOT NULL;
            
            IF @Level > 20 BREAK;
        END
        
        INSERT INTO @ProcessingLog (StepName, StartTime, EndTime, RowsAffected, StatusCode)
        VALUES (@CurrentStep, @StepStartTime, SYSUTCDATETIME(), @@ROWCOUNT, 'COMPLETED');
        
        -- Consolidate amounts (bottom-up)
        SET @CurrentStep = 'Hierarchy Consolidation';
        SET @StepStartTime = SYSUTCDATETIME();
        
        DECLARE @MaxLevel INT = (SELECT MAX(NodeLevel) FROM @HierarchyNodes);
        SET @Level = @MaxLevel;
        
        WHILE @Level >= 0
        BEGIN
            INSERT INTO @ConsolidatedAmounts (GLAccountID, CostCenterID, FiscalPeriodID, ConsolidatedAmount, SourceCount)
            SELECT 
                bli.GLAccountID,
                h.NodeID,
                bli.FiscalPeriodID,
                SUM(bli.OriginalAmount + bli.AdjustedAmount),
                COUNT(*)
            FROM @HierarchyNodes h
            JOIN Planning.BudgetLineItem bli ON bli.CostCenterID = h.NodeID
            WHERE h.NodeLevel = @Level
              AND bli.BudgetHeaderID = @SourceBudgetHeaderID
            GROUP BY bli.GLAccountID, h.NodeID, bli.FiscalPeriodID;
            
            -- Add child totals to parent
            UPDATE ca
            SET ConsolidatedAmount = ca.ConsolidatedAmount + child_totals.ChildAmount
            FROM @ConsolidatedAmounts ca
            JOIN (
                SELECT 
                    h_parent.NodeID as ParentID,
                    ca_child.GLAccountID,
                    ca_child.FiscalPeriodID,
                    SUM(ca_child.ConsolidatedAmount) as ChildAmount
                FROM @HierarchyNodes h_child
                JOIN @HierarchyNodes h_parent ON h_child.ParentNodeID = h_parent.NodeID
                JOIN @ConsolidatedAmounts ca_child ON ca_child.CostCenterID = h_child.NodeID
                WHERE h_child.NodeLevel = @Level
                GROUP BY h_parent.NodeID, ca_child.GLAccountID, ca_child.FiscalPeriodID
            ) child_totals ON ca.CostCenterID = child_totals.ParentID 
                          AND ca.GLAccountID = child_totals.GLAccountID
                          AND ca.FiscalPeriodID = child_totals.FiscalPeriodID;
            
            SET @TotalRowsProcessed = @TotalRowsProcessed + @@ROWCOUNT;
            SET @Level = @Level - 1;
        END
        
        INSERT INTO @ProcessingLog (StepName, StartTime, EndTime, RowsAffected, StatusCode)
        VALUES (@CurrentStep, @StepStartTime, SYSUTCDATETIME(), @TotalRowsProcessed, 'COMPLETED');
        
        -- Intercompany eliminations
        IF @IncludeEliminations = 1
        BEGIN
            SET @CurrentStep = 'Intercompany Eliminations';
            SET @StepStartTime = SYSUTCDATETIME();
            
            -- Find matched IC pairs and eliminate
            UPDATE ca1
            SET EliminationAmount = ca1.ConsolidatedAmount
            FROM @ConsolidatedAmounts ca1
            JOIN Planning.GLAccount gla ON ca1.GLAccountID = gla.GLAccountID
            WHERE gla.IntercompanyFlag = 1
              AND EXISTS (
                  SELECT 1 FROM @ConsolidatedAmounts ca2
                  WHERE ca2.GLAccountID = ca1.GLAccountID
                    AND ca2.FiscalPeriodID = ca1.FiscalPeriodID
                    AND ca2.CostCenterID <> ca1.CostCenterID
                    AND ca2.ConsolidatedAmount = -ca1.ConsolidatedAmount
              );
            
            INSERT INTO @ProcessingLog (StepName, StartTime, EndTime, RowsAffected, StatusCode)
            VALUES (@CurrentStep, @StepStartTime, SYSUTCDATETIME(), @@ROWCOUNT, 'COMPLETED');
        END
        
        -- Calculate FinalAmount (THIS WAS THE BUG - was in dynamic SQL which can't access table variables)
        SET @CurrentStep = 'Calculate Final Amounts';
        SET @StepStartTime = SYSUTCDATETIME();
        
        UPDATE @ConsolidatedAmounts
        SET FinalAmount = ConsolidatedAmount - ISNULL(EliminationAmount, 0)
        WHERE ConsolidatedAmount <> 0 OR EliminationAmount <> 0;
        
        INSERT INTO @ProcessingLog (StepName, StartTime, EndTime, RowsAffected, StatusCode)
        VALUES (@CurrentStep, @StepStartTime, SYSUTCDATETIME(), @@ROWCOUNT, 'COMPLETED');
        
        -- Insert results
        SET @CurrentStep = 'Insert Results';
        SET @StepStartTime = SYSUTCDATETIME();
        
        -- Note: FinalAmount is a computed column (OriginalAmount + AdjustedAmount), can't INSERT into it
        INSERT INTO Planning.BudgetLineItem (
            BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
            OriginalAmount, AdjustedAmount, SpreadMethodCode, 
            SourceSystem, SourceReference, IsAllocated, LastModifiedByUserID, LastModifiedDateTime
        )
        SELECT 
            @TargetBudgetHeaderID,
            ca.GLAccountID,
            ca.CostCenterID,
            ca.FiscalPeriodID,
            ca.FinalAmount,  -- Goes into OriginalAmount
            0,               -- AdjustedAmount = 0
            'CONSOLIDATED',
            'CONSOLIDATION_PROC',
            CAST(@ConsolidationRunID AS VARCHAR(50)),
            0,
            @UserID,
            SYSUTCDATETIME()
        FROM @ConsolidatedAmounts ca
        WHERE ca.FinalAmount IS NOT NULL;
        
        SET @TotalRowsProcessed = @@ROWCOUNT;
        
        INSERT INTO @ProcessingLog (StepName, StartTime, EndTime, RowsAffected, StatusCode)
        VALUES (@CurrentStep, @StepStartTime, SYSUTCDATETIME(), @TotalRowsProcessed, 'COMPLETED');
        
        COMMIT TRANSACTION;
        
        SET @RowsProcessed = @TotalRowsProcessed;
        
        IF @DebugMode = 1
            SELECT * FROM @ProcessingLog ORDER BY LogID;
        
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK;
        SET @ErrorMessage = ERROR_MESSAGE();
        SET @RowsProcessed = 0;
    END CATCH
END
GO
