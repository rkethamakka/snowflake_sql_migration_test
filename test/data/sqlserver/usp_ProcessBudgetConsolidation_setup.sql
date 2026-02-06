-- Test Data for usp_ProcessBudgetConsolidation (SQL Server)
-- 40 rows total across 5 tables

USE FINANCIAL_PLANNING;
GO

-- Enable identity inserts
SET IDENTITY_INSERT Planning.FiscalPeriod ON;
SET IDENTITY_INSERT Planning.GLAccount ON;
SET IDENTITY_INSERT Planning.CostCenter ON;
SET IDENTITY_INSERT Planning.BudgetHeader ON;

-- FiscalPeriod (12 rows)
INSERT INTO Planning.FiscalPeriod (FiscalPeriodID, FiscalYear, FiscalQuarter, FiscalMonth, PeriodName, PeriodStartDate, PeriodEndDate, IsActive)
VALUES
(1, 2024, 1, 1, 'Jan 2024', '2024-01-01', '2024-01-31', 1),
(2, 2024, 1, 2, 'Feb 2024', '2024-02-01', '2024-02-29', 1),
(3, 2024, 1, 3, 'Mar 2024', '2024-03-01', '2024-03-31', 1),
(4, 2024, 2, 4, 'Apr 2024', '2024-04-01', '2024-04-30', 1),
(5, 2024, 2, 5, 'May 2024', '2024-05-01', '2024-05-31', 1),
(6, 2024, 2, 6, 'Jun 2024', '2024-06-01', '2024-06-30', 1),
(7, 2024, 3, 7, 'Jul 2024', '2024-07-01', '2024-07-31', 1),
(8, 2024, 3, 8, 'Aug 2024', '2024-08-01', '2024-08-31', 1),
(9, 2024, 3, 9, 'Sep 2024', '2024-09-01', '2024-09-30', 1),
(10, 2024, 4, 10, 'Oct 2024', '2024-10-01', '2024-10-31', 1),
(11, 2024, 4, 11, 'Nov 2024', '2024-11-01', '2024-11-30', 1),
(12, 2024, 4, 12, 'Dec 2024', '2024-12-01', '2024-12-31', 1);

SET IDENTITY_INSERT Planning.FiscalPeriod OFF;

-- GLAccount (6 rows)
INSERT INTO Planning.GLAccount (GLAccountID, AccountNumber, AccountName, AccountType, IsPostable, IsBudgetable, IntercompanyFlag, NormalBalance, IsActive)
VALUES
(1, '4000', 'Revenue', 'R', 1, 1, 0, 'C', 1),
(2, '5000', 'Cost of Sales', 'E', 1, 1, 0, 'D', 1),
(3, '6000', 'Operating Expenses', 'E', 1, 1, 0, 'D', 1),
(4, '7000', 'Admin Expenses', 'E', 1, 1, 0, 'D', 1),
(5, '8000', 'Other Income', 'R', 1, 1, 0, 'C', 1),
(6, '9000', 'Intercompany', 'E', 1, 1, 1, 'D', 1);

SET IDENTITY_INSERT Planning.GLAccount OFF;

-- CostCenter (7 rows)
INSERT INTO Planning.CostCenter (CostCenterID, CostCenterCode, CostCenterName, ParentCostCenterID, IsActive, EffectiveFromDate, EffectiveToDate)
VALUES
(1, 'CORP', 'Corporate', NULL, 1, '2024-01-01', NULL),
(2, 'ENG', 'Engineering', 1, 1, '2024-01-01', NULL),
(3, 'SALES', 'Sales', 1, 1, '2024-01-01', NULL),
(4, 'MKT', 'Marketing', 1, 1, '2024-01-01', NULL),
(5, 'ENG-BE', 'Backend Team', 2, 1, '2024-01-01', NULL),
(6, 'ENG-FE', 'Frontend Team', 2, 1, '2024-01-01', NULL),
(7, 'SALES-W', 'Sales West', 3, 1, '2024-01-01', NULL);

SET IDENTITY_INSERT Planning.CostCenter OFF;

-- BudgetHeader (1 row)
INSERT INTO Planning.BudgetHeader (BudgetHeaderID, BudgetCode, BudgetName, BudgetType, ScenarioType, FiscalYear, StartPeriodID, EndPeriodID, StatusCode, VersionNumber)
VALUES
(1, 'BUD-2024-001', '2024 Annual Budget', 'ANNUAL', 'BASE', 2024, 1, 12, 'APPROVED', 1);

SET IDENTITY_INSERT Planning.BudgetHeader OFF;

-- BudgetLineItem (20 rows - no identity column)
INSERT INTO Planning.BudgetLineItem (BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID, OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated, LastModifiedByUserID)
VALUES
-- Corporate direct amounts
(1, 1, 1, 1, 50000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),
(1, 4, 1, 1, 25000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),
(1, 6, 1, 1, 10000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),

-- Engineering direct amounts
(1, 1, 2, 1, 80000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),
(1, 3, 2, 1, 35000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),
(1, 6, 2, 1, -10000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),

-- Sales direct amounts
(1, 1, 3, 1, 120000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),
(1, 2, 3, 1, 70000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),
(1, 6, 3, 1, 5000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),

-- Marketing direct amounts
(1, 1, 4, 1, 60000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),
(1, 3, 4, 1, 45000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),

-- Backend Team direct amounts
(1, 1, 5, 1, 40000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),
(1, 3, 5, 1, 20000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),

-- Frontend Team direct amounts
(1, 1, 6, 1, 35000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),
(1, 3, 6, 1, 15000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),

-- Sales West direct amounts
(1, 1, 7, 1, 30000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),
(1, 2, 7, 1, 18000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),

-- Additional periods
(1, 1, 1, 2, 52000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),
(1, 1, 2, 2, 82000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100),
(1, 1, 3, 2, 125000, 0, 'MANUAL', 'MANUAL_ENTRY', 0, 100);

SELECT 'Test data loaded: 40 rows total' AS Status;
GO
