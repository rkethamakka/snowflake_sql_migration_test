/*
    BudgetHeader - Budget version and scenario header
    Dependencies: FiscalPeriod
    Translated from SQL Server to Snowflake
*/

-- Use the correct database
USE DATABASE FINANCIAL_PLANNING;

-- Drop table if exists to ensure clean deployment
DROP TABLE IF EXISTS Planning.BudgetHeader;

CREATE TABLE Planning.BudgetHeader (
    BudgetHeaderID          NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1,
    BudgetCode              VARCHAR(30) NOT NULL,
    BudgetName              VARCHAR(100) NOT NULL,
    BudgetType              VARCHAR(20) NOT NULL,
    ScenarioType            VARCHAR(20) NOT NULL,
    FiscalYear              NUMBER(5,0) NOT NULL,
    StartPeriodID           NUMBER(38,0) NOT NULL,
    EndPeriodID             NUMBER(38,0) NOT NULL,
    BaseBudgetHeaderID      NUMBER(38,0) NULL,
    StatusCode              VARCHAR(15) NOT NULL DEFAULT 'DRAFT',
    SubmittedByUserID       NUMBER(38,0) NULL,
    SubmittedDateTime       TIMESTAMP_NTZ(7) NULL,
    ApprovedByUserID        NUMBER(38,0) NULL,
    ApprovedDateTime        TIMESTAMP_NTZ(7) NULL,
    LockedDateTime          TIMESTAMP_NTZ(7) NULL,
    VersionNumber           NUMBER(38,0) NOT NULL DEFAULT 1,
    Notes                   VARCHAR(16777216) NULL,
    ExtendedProperties      VARIANT NULL,
    CreatedDateTime         TIMESTAMP_NTZ(7) NOT NULL,
    ModifiedDateTime        TIMESTAMP_NTZ(7) NOT NULL,
    CONSTRAINT PK_BudgetHeader PRIMARY KEY (BudgetHeaderID),
    CONSTRAINT UQ_BudgetHeader_Code_Year UNIQUE (BudgetCode, FiscalYear, VersionNumber),
    CONSTRAINT FK_BudgetHeader_StartPeriod FOREIGN KEY (StartPeriodID) 
        REFERENCES Planning.FiscalPeriod (FiscalPeriodID),
    CONSTRAINT FK_BudgetHeader_EndPeriod FOREIGN KEY (EndPeriodID) 
        REFERENCES Planning.FiscalPeriod (FiscalPeriodID),
    CONSTRAINT FK_BudgetHeader_BaseBudget FOREIGN KEY (BaseBudgetHeaderID) 
        REFERENCES Planning.BudgetHeader (BudgetHeaderID)
);
