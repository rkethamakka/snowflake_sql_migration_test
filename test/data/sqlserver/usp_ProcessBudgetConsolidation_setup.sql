/*
    Test Data for usp_ProcessBudgetConsolidation - SQL Server

    Test Scenarios:
    1. Multi-level hierarchy: Corporate → Engineering/Sales/Marketing → Sub-departments
    2. IC Elimination: Matched pairs (+10K/-10K between Corp<->Eng) and unmatched (Sales +5K)
    3. Hierarchy Rollup: Verify parent amounts = sum of children

    Expected Results After Consolidation:
    - Corporate Total (all rolled up): ~$378,000
    - IC Eliminations: Corp/Eng matched pair = $0, Sales unmatched = $5K preserved
*/

USE FINANCIAL_PLANNING;
GO

SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

-- Clear existing data (reverse FK order)
DELETE FROM Planning.BudgetLineItem;
DELETE FROM Planning.BudgetHeader;
DELETE FROM Planning.CostCenter;
DELETE FROM Planning.GLAccount;
DELETE FROM Planning.FiscalPeriod;
GO

-- =============================
-- Reference Data: FiscalPeriod
-- =============================
SET IDENTITY_INSERT Planning.FiscalPeriod ON;

INSERT INTO Planning.FiscalPeriod (
    FiscalPeriodID, FiscalYear, FiscalQuarter, FiscalMonth, PeriodName,
    PeriodStartDate, PeriodEndDate, IsClosed, IsAdjustmentPeriod, WorkingDays,
    CreatedDateTime, ModifiedDateTime
) VALUES
(1, 2024, 1, 1, N'Jan 2024', '2024-01-01', '2024-01-31', 0, 0, 22, SYSUTCDATETIME(), SYSUTCDATETIME()),
(2, 2024, 1, 2, N'Feb 2024', '2024-02-01', '2024-02-29', 0, 0, 20, SYSUTCDATETIME(), SYSUTCDATETIME()),
(3, 2024, 1, 3, N'Mar 2024', '2024-03-01', '2024-03-31', 0, 0, 21, SYSUTCDATETIME(), SYSUTCDATETIME());

SET IDENTITY_INSERT Planning.FiscalPeriod OFF;
GO

-- =============================
-- Reference Data: GLAccount
-- =============================
SET IDENTITY_INSERT Planning.GLAccount ON;

INSERT INTO Planning.GLAccount (
    GLAccountID, AccountNumber, AccountName, AccountType, AccountLevel,
    IsPostable, IsBudgetable, NormalBalance, IntercompanyFlag, IsActive,
    CreatedDateTime, ModifiedDateTime
) VALUES
(1, '4000', N'Revenue', 'R', 1, 1, 1, 'C', 0, 1, SYSUTCDATETIME(), SYSUTCDATETIME()),
(2, '5000', N'Cost of Sales', 'X', 1, 1, 1, 'D', 0, 1, SYSUTCDATETIME(), SYSUTCDATETIME()),
(3, '6000', N'Operating Expenses', 'X', 1, 1, 1, 'D', 0, 1, SYSUTCDATETIME(), SYSUTCDATETIME()),
(4, '7000', N'Administrative', 'X', 1, 1, 1, 'D', 0, 1, SYSUTCDATETIME(), SYSUTCDATETIME()),
(5, '8000', N'Marketing Expenses', 'X', 1, 1, 1, 'D', 0, 1, SYSUTCDATETIME(), SYSUTCDATETIME()),
-- Intercompany account
(6, '9000', N'Intercompany Receivable', 'A', 1, 1, 0, 'D', 1, 1, SYSUTCDATETIME(), SYSUTCDATETIME());

SET IDENTITY_INSERT Planning.GLAccount OFF;
GO

-- =============================
-- Reference Data: CostCenter (Hierarchy)
-- =============================
SET IDENTITY_INSERT Planning.CostCenter ON;

-- Level 0: Corporate (root)
INSERT INTO Planning.CostCenter (
    CostCenterID, CostCenterCode, CostCenterName, ParentCostCenterID,
    HierarchyPath, HierarchyLevel, IsActive, EffectiveFromDate, AllocationWeight,
    CreatedDateTime, ModifiedDateTime
) VALUES
(1, 'CORP', N'Corporate', NULL, '/1/', 0, 1, '2024-01-01', 1.0000, SYSUTCDATETIME(), SYSUTCDATETIME());

-- Level 1: Departments
INSERT INTO Planning.CostCenter (
    CostCenterID, CostCenterCode, CostCenterName, ParentCostCenterID,
    HierarchyPath, HierarchyLevel, IsActive, EffectiveFromDate, AllocationWeight,
    CreatedDateTime, ModifiedDateTime
) VALUES
(2, 'ENG', N'Engineering', 1, '/1/2/', 1, 1, '2024-01-01', 1.0000, SYSUTCDATETIME(), SYSUTCDATETIME()),
(3, 'SALES', N'Sales', 1, '/1/3/', 1, 1, '2024-01-01', 1.0000, SYSUTCDATETIME(), SYSUTCDATETIME()),
(4, 'MKT', N'Marketing', 1, '/1/4/', 1, 1, '2024-01-01', 1.0000, SYSUTCDATETIME(), SYSUTCDATETIME());

-- Level 2: Sub-departments
INSERT INTO Planning.CostCenter (
    CostCenterID, CostCenterCode, CostCenterName, ParentCostCenterID,
    HierarchyPath, HierarchyLevel, IsActive, EffectiveFromDate, AllocationWeight,
    CreatedDateTime, ModifiedDateTime
) VALUES
(5, 'ENG-BE', N'Engineering - Backend', 2, '/1/2/5/', 2, 1, '2024-01-01', 0.6000, SYSUTCDATETIME(), SYSUTCDATETIME()),
(6, 'ENG-FE', N'Engineering - Frontend', 2, '/1/2/6/', 2, 1, '2024-01-01', 0.4000, SYSUTCDATETIME(), SYSUTCDATETIME()),
(7, 'SALES-W', N'Sales - West Region', 3, '/1/3/7/', 2, 1, '2024-01-01', 1.0000, SYSUTCDATETIME(), SYSUTCDATETIME());

SET IDENTITY_INSERT Planning.CostCenter OFF;
GO

-- =============================
-- Transaction Data: BudgetHeader
-- =============================
SET IDENTITY_INSERT Planning.BudgetHeader ON;

INSERT INTO Planning.BudgetHeader (
    BudgetHeaderID, BudgetCode, BudgetName, BudgetType, ScenarioType,
    FiscalYear, StartPeriodID, EndPeriodID, StatusCode, VersionNumber,
    CreatedDateTime, ModifiedDateTime
) VALUES
(1, 'BUD-2024-001', N'2024 Annual Budget', 'ANNUAL', 'BASE',
 2024, 1, 3, 'APPROVED', 1, SYSUTCDATETIME(), SYSUTCDATETIME());

SET IDENTITY_INSERT Planning.BudgetHeader OFF;
GO

-- =============================
-- Transaction Data: BudgetLineItem
-- =============================
SET IDENTITY_INSERT Planning.BudgetLineItem ON;

-- Direct amounts (leaf nodes only)
-- Engineering - Backend (ENG-BE, ID=5): $100K
INSERT INTO Planning.BudgetLineItem (
    BudgetLineItemID, BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
    OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated,
    LastModifiedDateTime
) VALUES
(1, 1, 2, 5, 1, 100000, 0, 'MANUAL', 'UPLOAD', 0, SYSUTCDATETIME());

-- Engineering - Frontend (ENG-FE, ID=6): $50K + IC entries
INSERT INTO Planning.BudgetLineItem (
    BudgetLineItemID, BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
    OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated,
    LastModifiedDateTime
) VALUES
(2, 1, 2, 6, 1, 50000, 0, 'MANUAL', 'UPLOAD', 0, SYSUTCDATETIME()),
-- IC: ENG-FE → CORP: -$10K (will be matched with Corporate's +$10K)
(3, 1, 6, 6, 1, -10000, 0, 'MANUAL', 'IC_ENTRY', 0, SYSUTCDATETIME());

-- Sales - West (SALES-W, ID=7): $75K
INSERT INTO Planning.BudgetLineItem (
    BudgetLineItemID, BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
    OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated,
    LastModifiedDateTime
) VALUES
(4, 1, 3, 7, 1, 75000, 0, 'MANUAL', 'UPLOAD', 0, SYSUTCDATETIME());

-- Marketing (MKT, ID=4): $100K
INSERT INTO Planning.BudgetLineItem (
    BudgetLineItemID, BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
    OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated,
    LastModifiedDateTime
) VALUES
(5, 1, 5, 4, 1, 100000, 0, 'MANUAL', 'UPLOAD', 0, SYSUTCDATETIME());

-- Corporate (CORP, ID=1): $50K + IC entries
INSERT INTO Planning.BudgetLineItem (
    BudgetLineItemID, BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
    OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated,
    LastModifiedDateTime
) VALUES
(6, 1, 4, 1, 1, 50000, 0, 'MANUAL', 'UPLOAD', 0, SYSUTCDATETIME()),
-- IC: CORP → ENG-FE: +$10K (will be matched with ENG-FE's -$10K) - SHOULD BE ELIMINATED
(7, 1, 6, 1, 1, 10000, 0, 'MANUAL', 'IC_ENTRY', 0, SYSUTCDATETIME());

-- Sales (parent SALES, ID=3): $3K direct + IC unmatched
INSERT INTO Planning.BudgetLineItem (
    BudgetLineItemID, BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
    OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated,
    LastModifiedDateTime
) VALUES
(8, 1, 3, 3, 1, 3000, 0, 'MANUAL', 'UPLOAD', 0, SYSUTCDATETIME()),
-- IC: Sales unmatched (no offsetting entry) - SHOULD BE PRESERVED
(9, 1, 6, 3, 1, 5000, 0, 'MANUAL', 'IC_ENTRY', 0, SYSUTCDATETIME());

SET IDENTITY_INSERT Planning.BudgetLineItem OFF;
GO

PRINT 'Test data loaded to SQL Server';
GO

-- Verify row counts
SET QUOTED_IDENTIFIER ON;
SELECT 'FiscalPeriod' as tbl, COUNT(*) as cnt FROM Planning.FiscalPeriod
UNION ALL SELECT 'GLAccount', COUNT(*) FROM Planning.GLAccount
UNION ALL SELECT 'CostCenter', COUNT(*) FROM Planning.CostCenter
UNION ALL SELECT 'BudgetHeader', COUNT(*) FROM Planning.BudgetHeader
UNION ALL SELECT 'BudgetLineItem', COUNT(*) FROM Planning.BudgetLineItem;
GO
