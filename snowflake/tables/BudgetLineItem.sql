/*
    BudgetLineItem - Individual budget amounts by account/cost center/period
    Dependencies: BudgetHeader, GLAccount, CostCenter, FiscalPeriod

    Translation notes:
    - BIGINT → NUMBER(38,0)
    - Computed columns (FinalAmount, RowHash) removed - calculate in queries/views
    - UNIQUEIDENTIFIER → VARCHAR(36)
    - HASHBYTES → Use HASH() function in Snowflake if needed
*/

USE DATABASE FINANCIAL_PLANNING;
USE SCHEMA PLANNING;

CREATE OR REPLACE TABLE PLANNING.BudgetLineItem (
    BudgetLineItemID        NUMBER(38,0) AUTOINCREMENT NOT NULL,
    BudgetHeaderID          NUMBER(38,0) NOT NULL,
    GLAccountID             NUMBER(38,0) NOT NULL,
    CostCenterID            NUMBER(38,0) NOT NULL,
    FiscalPeriodID          NUMBER(38,0) NOT NULL,
    -- Amounts
    OriginalAmount          NUMBER(19,4) NOT NULL DEFAULT 0,
    AdjustedAmount          NUMBER(19,4) NOT NULL DEFAULT 0,
    -- FinalAmount computed column removed - calculate as: OriginalAmount + AdjustedAmount
    LocalCurrencyAmount     NUMBER(19,4) NULL,
    ReportingCurrencyAmount NUMBER(19,4) NULL,
    StatisticalQuantity     NUMBER(18,6) NULL,
    UnitOfMeasure           VARCHAR(10) NULL,
    -- Spreading pattern
    SpreadMethodCode        VARCHAR(10) NULL,
    SeasonalityFactor       NUMBER(8,6) NULL,
    -- Source tracking
    SourceSystem            VARCHAR(30) NULL,
    SourceReference         VARCHAR(100) NULL,
    ImportBatchID           VARCHAR(36) NULL,  -- UNIQUEIDENTIFIER → VARCHAR(36)
    -- Allocation tracking
    IsAllocated             BOOLEAN NOT NULL DEFAULT FALSE,
    AllocationSourceLineID  NUMBER(38,0) NULL,
    AllocationPercentage    NUMBER(8,6) NULL,
    -- Audit columns
    LastModifiedByUserID    NUMBER(38,0) NULL,
    LastModifiedDateTime    TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    -- RowHash computed column removed - calculate using HASH() if needed
    CONSTRAINT PK_BudgetLineItem PRIMARY KEY (BudgetLineItemID),
    CONSTRAINT FK_BudgetLineItem_Header FOREIGN KEY (BudgetHeaderID)
        REFERENCES PLANNING.BudgetHeader (BudgetHeaderID),
    CONSTRAINT FK_BudgetLineItem_Account FOREIGN KEY (GLAccountID)
        REFERENCES PLANNING.GLAccount (GLAccountID),
    CONSTRAINT FK_BudgetLineItem_CostCenter FOREIGN KEY (CostCenterID)
        REFERENCES PLANNING.CostCenter (CostCenterID),
    CONSTRAINT FK_BudgetLineItem_Period FOREIGN KEY (FiscalPeriodID)
        REFERENCES PLANNING.FiscalPeriod (FiscalPeriodID),
    CONSTRAINT FK_BudgetLineItem_AllocationSource FOREIGN KEY (AllocationSourceLineID)
        REFERENCES PLANNING.BudgetLineItem (BudgetLineItemID)
);
