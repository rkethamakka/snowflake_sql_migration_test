/*
    BudgetLineItem - Individual budget amounts by account/cost center/period
    Dependencies: BudgetHeader, GLAccount, CostCenter, FiscalPeriod
    Translated from SQL Server to Snowflake
*/

-- Use the correct database
USE DATABASE FINANCIAL_PLANNING;

-- Drop table if exists to ensure clean deployment
DROP TABLE IF EXISTS Planning.BudgetLineItem;

CREATE TABLE Planning.BudgetLineItem (
    BudgetLineItemID        NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1,
    BudgetHeaderID          NUMBER(38,0) NOT NULL,
    GLAccountID             NUMBER(38,0) NOT NULL,
    CostCenterID            NUMBER(38,0) NOT NULL,
    FiscalPeriodID          NUMBER(38,0) NOT NULL,
    OriginalAmount          DECIMAL(19,4) NOT NULL DEFAULT 0,
    AdjustedAmount          DECIMAL(19,4) NOT NULL DEFAULT 0,
    LocalCurrencyAmount     DECIMAL(19,4) NULL,
    ReportingCurrencyAmount DECIMAL(19,4) NULL,
    StatisticalQuantity     DECIMAL(18,6) NULL,
    UnitOfMeasure           VARCHAR(10) NULL,
    SpreadMethodCode        VARCHAR(10) NULL,
    SeasonalityFactor       DECIMAL(8,6) NULL,
    SourceSystem            VARCHAR(30) NULL,
    SourceReference         VARCHAR(100) NULL,
    ImportBatchID           VARCHAR(36) NULL,
    IsAllocated             BOOLEAN NOT NULL DEFAULT FALSE,
    AllocationSourceLineID  NUMBER(38,0) NULL,
    AllocationPercentage    DECIMAL(8,6) NULL,
    LastModifiedByUserID    NUMBER(38,0) NULL,
    LastModifiedDateTime    TIMESTAMP_NTZ(7) NOT NULL,
    CONSTRAINT PK_BudgetLineItem PRIMARY KEY (BudgetLineItemID),
    CONSTRAINT UQ_BudgetLineItem_NaturalKey UNIQUE (BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID),
    CONSTRAINT FK_BudgetLineItem_Header FOREIGN KEY (BudgetHeaderID) 
        REFERENCES Planning.BudgetHeader (BudgetHeaderID),
    CONSTRAINT FK_BudgetLineItem_Account FOREIGN KEY (GLAccountID) 
        REFERENCES Planning.GLAccount (GLAccountID),
    CONSTRAINT FK_BudgetLineItem_CostCenter FOREIGN KEY (CostCenterID) 
        REFERENCES Planning.CostCenter (CostCenterID),
    CONSTRAINT FK_BudgetLineItem_Period FOREIGN KEY (FiscalPeriodID) 
        REFERENCES Planning.FiscalPeriod (FiscalPeriodID),
    CONSTRAINT FK_BudgetLineItem_AllocationSource FOREIGN KEY (AllocationSourceLineID) 
        REFERENCES Planning.BudgetLineItem (BudgetLineItemID)
);
