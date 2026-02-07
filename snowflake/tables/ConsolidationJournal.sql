/*
    ConsolidationJournal - Journal entries for consolidation adjustments
    Dependencies: BudgetHeader, GLAccount, CostCenter, FiscalPeriod
    Translated from SQL Server to Snowflake
*/

-- Use the correct database
USE DATABASE FINANCIAL_PLANNING;

-- Drop table if exists to ensure clean deployment
DROP TABLE IF EXISTS Planning.ConsolidationJournal;

CREATE TABLE Planning.ConsolidationJournal (
    JournalID               NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1,
    JournalNumber           VARCHAR(30) NOT NULL,
    JournalType             VARCHAR(20) NOT NULL,
    BudgetHeaderID          NUMBER(38,0) NOT NULL,
    FiscalPeriodID          NUMBER(38,0) NOT NULL,
    PostingDate             DATE NOT NULL,
    Description             VARCHAR(500) NULL,
    StatusCode              VARCHAR(15) NOT NULL DEFAULT 'DRAFT',
    SourceEntityCode        VARCHAR(20) NULL,
    TargetEntityCode        VARCHAR(20) NULL,
    IsAutoReverse           BOOLEAN NOT NULL DEFAULT FALSE,
    ReversalPeriodID        NUMBER(38,0) NULL,
    ReversedFromJournalID   NUMBER(38,0) NULL,
    IsReversed              BOOLEAN NOT NULL DEFAULT FALSE,
    TotalDebits             DECIMAL(19,4) NOT NULL DEFAULT 0,
    TotalCredits            DECIMAL(19,4) NOT NULL DEFAULT 0,
    PreparedByUserID        NUMBER(38,0) NULL,
    PreparedDateTime        TIMESTAMP_NTZ(7) NULL,
    ReviewedByUserID        NUMBER(38,0) NULL,
    ReviewedDateTime        TIMESTAMP_NTZ(7) NULL,
    ApprovedByUserID        NUMBER(38,0) NULL,
    ApprovedDateTime        TIMESTAMP_NTZ(7) NULL,
    PostedByUserID          NUMBER(38,0) NULL,
    PostedDateTime          TIMESTAMP_NTZ(7) NULL,
    AttachmentData          BINARY NULL,
    AttachmentRowGuid       VARCHAR(36) NOT NULL DEFAULT UUID_STRING(),
    CONSTRAINT PK_ConsolidationJournal PRIMARY KEY (JournalID),
    CONSTRAINT UQ_ConsolidationJournal_Number UNIQUE (JournalNumber),
    CONSTRAINT FK_ConsolidationJournal_Header FOREIGN KEY (BudgetHeaderID) 
        REFERENCES Planning.BudgetHeader (BudgetHeaderID),
    CONSTRAINT FK_ConsolidationJournal_Period FOREIGN KEY (FiscalPeriodID) 
        REFERENCES Planning.FiscalPeriod (FiscalPeriodID),
    CONSTRAINT FK_ConsolidationJournal_ReversalPeriod FOREIGN KEY (ReversalPeriodID) 
        REFERENCES Planning.FiscalPeriod (FiscalPeriodID),
    CONSTRAINT FK_ConsolidationJournal_ReversedFrom FOREIGN KEY (ReversedFromJournalID) 
        REFERENCES Planning.ConsolidationJournal (JournalID)
);
