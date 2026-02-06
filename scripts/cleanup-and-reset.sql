/*
    FULL Database Cleanup Script

    Drops ALL migrated objects (tables, views, functions, procedures)
    Run this for a completely fresh migration from scratch
*/

USE DATABASE FINANCIAL_PLANNING;
USE SCHEMA PLANNING;

-- Step 1: Drop Procedures
DROP PROCEDURE IF EXISTS usp_ProcessBudgetConsolidation(FLOAT, STRING, BOOLEAN, BOOLEAN, VARIANT, FLOAT, BOOLEAN);

-- Step 2: Drop Views
DROP VIEW IF EXISTS vw_BudgetConsolidationSummary;

-- Step 3: Drop Functions
DROP FUNCTION IF EXISTS fn_GetHierarchyPath(FLOAT);
DROP FUNCTION IF EXISTS tvf_ExplodeCostCenterHierarchy(FLOAT);

-- Step 4: Drop Tables (in dependency order)
DROP TABLE IF EXISTS ConsolidationJournal;
DROP TABLE IF EXISTS BudgetLineItem;
DROP TABLE IF EXISTS BudgetHeader;
DROP TABLE IF EXISTS CostCenter;
DROP TABLE IF EXISTS GLAccount;
DROP TABLE IF EXISTS FiscalPeriod;

SELECT 'Full cleanup complete - all migrated objects dropped' AS Status;

/*
    Next: Run full-cleanup.sh to delete generated files, then re-run pipeline:

    ./full-cleanup.sh
    /sql-migration-planner usp_ProcessBudgetConsolidation
    /sql-migration
    /test-data-generator usp_ProcessBudgetConsolidation
    /sql-migration-verify
*/
