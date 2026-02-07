/*
    FiscalPeriod - Core reference table for fiscal calendar
    Dependencies: None (base table)

    Translation notes:
    - IDENTITY(1,1) → AUTOINCREMENT
    - SMALLINT/TINYINT → NUMBER (Snowflake has no exact equivalent)
    - NVARCHAR → VARCHAR
    - BIT → BOOLEAN
    - DATETIME2(7) → TIMESTAMP_NTZ
    - ROWVERSION → Removed (no equivalent, use TIMESTAMP_NTZ with default)
    - SYSUTCDATETIME() → CURRENT_TIMESTAMP()
    - CLUSTERED keyword removed
    - Filtered index (WHERE clause) removed - not supported
    - INCLUDE clause removed - not supported
    - GO statements removed
*/

USE DATABASE FINANCIAL_PLANNING;
USE SCHEMA PLANNING;

CREATE OR REPLACE TABLE PLANNING.FiscalPeriod (
    FiscalPeriodID          NUMBER(38,0) AUTOINCREMENT NOT NULL,
    FiscalYear              NUMBER(5,0) NOT NULL,
    FiscalQuarter           NUMBER(3,0) NOT NULL,
    FiscalMonth             NUMBER(3,0) NOT NULL,
    PeriodName              VARCHAR(50) NOT NULL,
    PeriodStartDate         DATE NOT NULL,
    PeriodEndDate           DATE NOT NULL,
    IsClosed                BOOLEAN NOT NULL DEFAULT FALSE,
    ClosedByUserID          NUMBER(38,0) NULL,
    ClosedDateTime          TIMESTAMP_NTZ(9) NULL,
    IsAdjustmentPeriod      BOOLEAN NOT NULL DEFAULT FALSE,
    WorkingDays             NUMBER(3,0) NULL,
    CreatedDateTime         TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ModifiedDateTime        TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    -- RowVersionStamp removed - no ROWVERSION equivalent
    CONSTRAINT PK_FiscalPeriod PRIMARY KEY (FiscalPeriodID),
    CONSTRAINT UQ_FiscalPeriod_YearMonth UNIQUE (FiscalYear, FiscalMonth)
    -- CHECK constraints not supported in Snowflake:
    -- CK_FiscalPeriod_Quarter: FiscalQuarter BETWEEN 1 AND 4
    -- CK_FiscalPeriod_Month: FiscalMonth BETWEEN 1 AND 13
    -- CK_FiscalPeriod_DateRange: PeriodEndDate >= PeriodStartDate
);

-- Note: Indexes removed - Snowflake automatically optimizes queries
-- Snowflake uses micro-partitions and automatic clustering instead of explicit indexes
-- Original indexes for reference:
-- - IX_FiscalPeriod_OpenPeriods ON (FiscalYear, FiscalMonth) WHERE IsClosed = 0
-- - IX_FiscalPeriod_Dates ON (PeriodStartDate, PeriodEndDate) INCLUDE (FiscalYear, FiscalQuarter, FiscalMonth)
