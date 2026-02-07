/*
    Test Data for usp_ProcessBudgetConsolidation - Snowflake

    Test Scenarios:
    1. Multi-level hierarchy: Corporate → Engineering/Sales/Marketing → Sub-departments
    2. IC Elimination: Matched pairs (+10K/-10K between Corp<->Eng) and unmatched (Sales +5K)
    3. Hierarchy Rollup: Verify parent amounts = sum of children

    Expected Results After Consolidation:
    - Corporate Total (all rolled up): ~$378,000
    - IC Eliminations: Corp/Eng matched pair = $0, Sales unmatched = $5K preserved
*/

USE DATABASE FINANCIAL_PLANNING;
USE SCHEMA PLANNING;

-- Clear existing data (reverse FK order)
DELETE FROM PLANNING.BudgetLineItem;
DELETE FROM PLANNING.BudgetHeader;
DELETE FROM PLANNING.CostCenter;
DELETE FROM PLANNING.GLAccount;
DELETE FROM PLANNING.FiscalPeriod;

-- =============================
-- Reference Data: FiscalPeriod
-- =============================
INSERT INTO PLANNING.FiscalPeriod (
    FiscalPeriodID, FiscalYear, FiscalQuarter, FiscalMonth, PeriodName,
    PeriodStartDate, PeriodEndDate, IsClosed, IsAdjustmentPeriod, WorkingDays
) VALUES
(1, 2024, 1, 1, 'Jan 2024', '2024-01-01', '2024-01-31', FALSE, FALSE, 22),
(2, 2024, 1, 2, 'Feb 2024', '2024-02-01', '2024-02-29', FALSE, FALSE, 20),
(3, 2024, 1, 3, 'Mar 2024', '2024-03-01', '2024-03-31', FALSE, FALSE, 21);

-- =============================
-- Reference Data: GLAccount
-- =============================
INSERT INTO PLANNING.GLAccount (
    GLAccountID, AccountNumber, AccountName, AccountType, AccountLevel,
    IsPostable, IsBudgetable, NormalBalance, IntercompanyFlag, IsActive
) VALUES
(1, '4000', 'Revenue', 'R', 1, TRUE, TRUE, 'C', FALSE, TRUE),
(2, '5000', 'Cost of Sales', 'X', 1, TRUE, TRUE, 'D', FALSE, TRUE),
(3, '6000', 'Operating Expenses', 'X', 1, TRUE, TRUE, 'D', FALSE, TRUE),
(4, '7000', 'Administrative', 'X', 1, TRUE, TRUE, 'D', FALSE, TRUE),
(5, '8000', 'Marketing Expenses', 'X', 1, TRUE, TRUE, 'D', FALSE, TRUE),
-- Intercompany account (for elimination testing)
(6, '9000', 'Intercompany Receivable', 'A', 1, TRUE, FALSE, 'D', TRUE, TRUE);

-- =============================
-- Reference Data: CostCenter (Hierarchy)
-- =============================
-- Level 0: Corporate (root)
INSERT INTO PLANNING.CostCenter (
    CostCenterID, CostCenterCode, CostCenterName, ParentCostCenterID,
    HierarchyPath, HierarchyLevel, IsActive, EffectiveFromDate, AllocationWeight
) VALUES
(1, 'CORP', 'Corporate', NULL, '/1/', 0, TRUE, '2024-01-01', 1.0000);

-- Level 1: Departments
INSERT INTO PLANNING.CostCenter (
    CostCenterID, CostCenterCode, CostCenterName, ParentCostCenterID,
    HierarchyPath, HierarchyLevel, IsActive, EffectiveFromDate, AllocationWeight
) VALUES
(2, 'ENG', 'Engineering', 1, '/1/2/', 1, TRUE, '2024-01-01', 1.0000),
(3, 'SALES', 'Sales', 1, '/1/3/', 1, TRUE, '2024-01-01', 1.0000),
(4, 'MKT', 'Marketing', 1, '/1/4/', 1, TRUE, '2024-01-01', 1.0000);

-- Level 2: Sub-departments
INSERT INTO PLANNING.CostCenter (
    CostCenterID, CostCenterCode, CostCenterName, ParentCostCenterID,
    HierarchyPath, HierarchyLevel, IsActive, EffectiveFromDate, AllocationWeight
) VALUES
(5, 'ENG-BE', 'Engineering - Backend', 2, '/1/2/5/', 2, TRUE, '2024-01-01', 0.6000),
(6, 'ENG-FE', 'Engineering - Frontend', 2, '/1/2/6/', 2, TRUE, '2024-01-01', 0.4000),
(7, 'SALES-W', 'Sales - West Region', 3, '/1/3/7/', 2, TRUE, '2024-01-01', 1.0000);

-- =============================
-- Transaction Data: BudgetHeader
-- =============================
INSERT INTO PLANNING.BudgetHeader (
    BudgetHeaderID, BudgetCode, BudgetName, BudgetType, ScenarioType,
    FiscalYear, StartPeriodID, EndPeriodID, StatusCode, VersionNumber
) VALUES
(1, 'BUD-2024-001', '2024 Annual Budget', 'ANNUAL', 'BASE',
 2024, 1, 3, 'APPROVED', 1);

-- =============================
-- Transaction Data: BudgetLineItem
-- =============================

-- Direct amounts (leaf nodes only)
-- Engineering - Backend (ENG-BE, ID=5): $100K
INSERT INTO PLANNING.BudgetLineItem (
    BudgetLineItemID, BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
    OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated
) VALUES
(1, 1, 2, 5, 1, 100000, 0, 'MANUAL', 'UPLOAD', FALSE);

-- Engineering - Frontend (ENG-FE, ID=6): $50K + IC entries
INSERT INTO PLANNING.BudgetLineItem (
    BudgetLineItemID, BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
    OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated
) VALUES
(2, 1, 2, 6, 1, 50000, 0, 'MANUAL', 'UPLOAD', FALSE),
-- IC: ENG-FE → CORP: -$10K (will be matched with Corporate's +$10K)
(3, 1, 6, 6, 1, -10000, 0, 'MANUAL', 'IC_ENTRY', FALSE);

-- Sales - West (SALES-W, ID=7): $75K
INSERT INTO PLANNING.BudgetLineItem (
    BudgetLineItemID, BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
    OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated
) VALUES
(4, 1, 3, 7, 1, 75000, 0, 'MANUAL', 'UPLOAD', FALSE);

-- Marketing (MKT, ID=4): $100K
INSERT INTO PLANNING.BudgetLineItem (
    BudgetLineItemID, BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
    OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated
) VALUES
(5, 1, 5, 4, 1, 100000, 0, 'MANUAL', 'UPLOAD', FALSE);

-- Corporate (CORP, ID=1): $50K + IC entries
INSERT INTO PLANNING.BudgetLineItem (
    BudgetLineItemID, BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
    OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated
) VALUES
(6, 1, 4, 1, 1, 50000, 0, 'MANUAL', 'UPLOAD', FALSE),
-- IC: CORP → ENG-FE: +$10K (will be matched with ENG-FE's -$10K) - SHOULD BE ELIMINATED
(7, 1, 6, 1, 1, 10000, 0, 'MANUAL', 'IC_ENTRY', FALSE);

-- Sales (parent SALES, ID=3): $3K direct + IC unmatched
INSERT INTO PLANNING.BudgetLineItem (
    BudgetLineItemID, BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
    OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated
) VALUES
(8, 1, 3, 3, 1, 3000, 0, 'MANUAL', 'UPLOAD', FALSE),
-- IC: Sales unmatched (no offsetting entry) - SHOULD BE PRESERVED
(9, 1, 6, 3, 1, 5000, 0, 'MANUAL', 'IC_ENTRY', FALSE);

SELECT 'Test data loaded to Snowflake' AS Status;

-- Verify row counts
SELECT 'FiscalPeriod' as tbl, COUNT(*) as cnt FROM PLANNING.FiscalPeriod
UNION ALL SELECT 'GLAccount', COUNT(*) FROM PLANNING.GLAccount
UNION ALL SELECT 'CostCenter', COUNT(*) FROM PLANNING.CostCenter
UNION ALL SELECT 'BudgetHeader', COUNT(*) FROM PLANNING.BudgetHeader
UNION ALL SELECT 'BudgetLineItem', COUNT(*) FROM PLANNING.BudgetLineItem;
