/*
    BudgetHeader - Budget version and scenario header
    Dependencies: FiscalPeriod

    Translation notes:
    - XML → VARIANT (store as JSON)
    - Computed column (IsLocked) → Remove, calculate in queries
    - NVARCHAR(MAX) → VARCHAR
    - XML indexes removed (use VARIANT indexing)
*/

USE DATABASE FINANCIAL_PLANNING;
USE SCHEMA PLANNING;

CREATE OR REPLACE TABLE PLANNING.BudgetHeader (
    BudgetHeaderID          NUMBER(38,0) AUTOINCREMENT NOT NULL,
    BudgetCode              VARCHAR(30) NOT NULL,
    BudgetName              VARCHAR(100) NOT NULL,
    BudgetType              VARCHAR(20) NOT NULL,  -- ANNUAL, QUARTERLY, ROLLING, FORECAST
    ScenarioType            VARCHAR(20) NOT NULL,  -- BASE, OPTIMISTIC, PESSIMISTIC, STRETCH
    FiscalYear              NUMBER(5,0) NOT NULL,
    StartPeriodID           NUMBER(38,0) NOT NULL,
    EndPeriodID             NUMBER(38,0) NOT NULL,
    BaseBudgetHeaderID      NUMBER(38,0) NULL,  -- For variance calculations
    StatusCode              VARCHAR(15) NOT NULL DEFAULT 'DRAFT',
    SubmittedByUserID       NUMBER(38,0) NULL,
    SubmittedDateTime       TIMESTAMP_NTZ(9) NULL,
    ApprovedByUserID        NUMBER(38,0) NULL,
    ApprovedDateTime        TIMESTAMP_NTZ(9) NULL,
    LockedDateTime          TIMESTAMP_NTZ(9) NULL,
    -- IsLocked computed column removed - calculate as: (LockedDateTime IS NOT NULL)
    VersionNumber           NUMBER(38,0) NOT NULL DEFAULT 1,
    Notes                   VARCHAR NULL,
    -- XML → VARIANT for flexible metadata storage (store as JSON)
    ExtendedProperties      VARIANT NULL,
    CreatedDateTime         TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ModifiedDateTime        TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_BudgetHeader PRIMARY KEY (BudgetHeaderID),
    CONSTRAINT UQ_BudgetHeader_Code_Year UNIQUE (BudgetCode, FiscalYear, VersionNumber),
    CONSTRAINT FK_BudgetHeader_StartPeriod FOREIGN KEY (StartPeriodID)
        REFERENCES PLANNING.FiscalPeriod (FiscalPeriodID),
    CONSTRAINT FK_BudgetHeader_EndPeriod FOREIGN KEY (EndPeriodID)
        REFERENCES PLANNING.FiscalPeriod (FiscalPeriodID),
    CONSTRAINT FK_BudgetHeader_BaseBudget FOREIGN KEY (BaseBudgetHeaderID)
        REFERENCES PLANNING.BudgetHeader (BudgetHeaderID)
    -- CHECK constraint removed: StatusCode IN (...)
);

-- XML indexes removed - Snowflake uses automatic optimization for VARIANT queries
