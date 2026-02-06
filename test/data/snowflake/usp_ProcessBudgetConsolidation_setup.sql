-- Test Data for usp_ProcessBudgetConsolidation (Snowflake)
-- 40 rows total across 5 tables

-- FiscalPeriod (12 rows)
INSERT INTO FINANCIAL_PLANNING.PLANNING.FiscalPeriod (FiscalPeriodID, FiscalYear, FiscalQuarter, FiscalMonth, PeriodName, PeriodStartDate, PeriodEndDate)
VALUES
(1, 2024, 1, 1, 'Jan 2024', '2024-01-01', '2024-01-31'),
(2, 2024, 1, 2, 'Feb 2024', '2024-02-01', '2024-02-29'),
(3, 2024, 1, 3, 'Mar 2024', '2024-03-01', '2024-03-31'),
(4, 2024, 2, 4, 'Apr 2024', '2024-04-01', '2024-04-30'),
(5, 2024, 2, 5, 'May 2024', '2024-05-01', '2024-05-31'),
(6, 2024, 2, 6, 'Jun 2024', '2024-06-01', '2024-06-30'),
(7, 2024, 3, 7, 'Jul 2024', '2024-07-01', '2024-07-31'),
(8, 2024, 3, 8, 'Aug 2024', '2024-08-01', '2024-08-31'),
(9, 2024, 3, 9, 'Sep 2024', '2024-09-01', '2024-09-30'),
(10, 2024, 4, 10, 'Oct 2024', '2024-10-01', '2024-10-31'),
(11, 2024, 4, 11, 'Nov 2024', '2024-11-01', '2024-11-30'),
(12, 2024, 4, 12, 'Dec 2024', '2024-12-01', '2024-12-31');

-- GLAccount (6 rows - 5 operational + 1 IC)
INSERT INTO FINANCIAL_PLANNING.PLANNING.GLAccount (GLAccountID, AccountNumber, AccountName, AccountType, IntercompanyFlag, NormalBalance)
VALUES
(1, '4000', 'Revenue', 'R', FALSE, 'C'),
(2, '5000', 'Cost of Sales', 'E', FALSE, 'D'),
(3, '6000', 'Operating Expenses', 'E', FALSE, 'D'),
(4, '7000', 'Admin Expenses', 'E', FALSE, 'D'),
(5, '8000', 'Other Income', 'R', FALSE, 'C'),
(6, '9000', 'Intercompany', 'E', TRUE, 'D');

-- CostCenter (7 rows - 3 level hierarchy)
INSERT INTO FINANCIAL_PLANNING.PLANNING.CostCenter (CostCenterID, CostCenterCode, CostCenterName, ParentCostCenterID)
VALUES
(1, 'CORP', 'Corporate', NULL),
(2, 'ENG', 'Engineering', 1),
(3, 'SALES', 'Sales', 1),
(4, 'MKT', 'Marketing', 1),
(5, 'ENG-BE', 'Backend Team', 2),
(6, 'ENG-FE', 'Frontend Team', 2),
(7, 'SALES-W', 'Sales West', 3);

-- BudgetHeader (1 row)
INSERT INTO FINANCIAL_PLANNING.PLANNING.BudgetHeader (BudgetHeaderID, BudgetCode, BudgetName, BudgetType, ScenarioType, FiscalYear, StartPeriodID, EndPeriodID, StatusCode, VersionNumber)
VALUES
(1, 'BUD-2024-001', '2024 Annual Budget', 'ANNUAL', 'BASE', 2024, 1, 12, 'APPROVED', 1);

-- BudgetLineItem (20 rows with IC pairs)
INSERT INTO FINANCIAL_PLANNING.PLANNING.BudgetLineItem (BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID, OriginalAmount, AdjustedAmount, SpreadMethodCode, SourceSystem, IsAllocated, LastModifiedByUserID)
VALUES
-- Corporate direct amounts
(1, 1, 1, 1, 50000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),
(1, 4, 1, 1, 25000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),
(1, 6, 1, 1, 10000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100), -- IC +10K (matches Engineering)

-- Engineering direct amounts
(1, 1, 2, 1, 80000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),
(1, 3, 2, 1, 35000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),
(1, 6, 2, 1, -10000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100), -- IC -10K (matches Corporate)

-- Sales direct amounts
(1, 1, 3, 1, 120000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),
(1, 2, 3, 1, 70000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),
(1, 6, 3, 1, 5000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100), -- IC +5K (unmatched)

-- Marketing direct amounts
(1, 1, 4, 1, 60000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),
(1, 3, 4, 1, 45000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),

-- Backend Team direct amounts
(1, 1, 5, 1, 40000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),
(1, 3, 5, 1, 20000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),

-- Frontend Team direct amounts
(1, 1, 6, 1, 35000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),
(1, 3, 6, 1, 15000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),

-- Sales West direct amounts
(1, 1, 7, 1, 30000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),
(1, 2, 7, 1, 18000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),

-- Additional periods
(1, 1, 1, 2, 52000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),
(1, 1, 2, 2, 82000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100),
(1, 1, 3, 2, 125000, 0, 'MANUAL', 'MANUAL_ENTRY', FALSE, 100);

SELECT 'Test data loaded: 40 rows total' AS Status;
