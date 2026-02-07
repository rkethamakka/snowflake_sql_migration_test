/*
    FiscalPeriod - Core reference table for fiscal calendar
    Dependencies: None (base table)
    Translated from SQL Server to Snowflake
*/

-- Use the correct database
USE DATABASE FINANCIAL_PLANNING;

-- Drop table if exists to ensure clean deployment
DROP TABLE IF EXISTS Planning.FiscalPeriod;

CREATE TABLE Planning.FiscalPeriod (
    FiscalPeriodID          NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1,
    FiscalYear              NUMBER(5,0) NOT NULL,
    FiscalQuarter           NUMBER(3,0) NOT NULL,
    FiscalMonth             NUMBER(3,0) NOT NULL,
    PeriodName              VARCHAR(50) NOT NULL,
    PeriodStartDate         DATE NOT NULL,
    PeriodEndDate           DATE NOT NULL,
    IsClosed                BOOLEAN NOT NULL DEFAULT FALSE,
    ClosedByUserID          NUMBER(38,0) NULL,
    ClosedDateTime          TIMESTAMP_NTZ(7) NULL,
    IsAdjustmentPeriod      BOOLEAN NOT NULL DEFAULT FALSE,
    WorkingDays             NUMBER(3,0) NULL,
    CreatedDateTime         TIMESTAMP_NTZ(7) NOT NULL,
    ModifiedDateTime        TIMESTAMP_NTZ(7) NOT NULL,
    CONSTRAINT PK_FiscalPeriod PRIMARY KEY (FiscalPeriodID),
    CONSTRAINT UQ_FiscalPeriod_YearMonth UNIQUE (FiscalYear, FiscalMonth)
);
