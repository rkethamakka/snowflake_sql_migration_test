/*
    ConsolidationJournal - Journal entries for consolidation adjustments
    Dependencies: BudgetHeader, FiscalPeriod

    Translation notes:
    - Computed column (IsBalanced) removed
    - FILESTREAM → Removed (no equivalent, store externally or as VARIANT)
    - ROWGUIDCOL → Removed
    - NEWSEQUENTIALID() → Use UUID_STRING() when inserting
*/

USE DATABASE FINANCIAL_PLANNING;
USE SCHEMA PLANNING;

CREATE OR REPLACE TABLE PLANNING.ConsolidationJournal (
    JournalID               NUMBER(38,0) AUTOINCREMENT NOT NULL,
    JournalNumber           VARCHAR(30) NOT NULL,
    JournalType             VARCHAR(20) NOT NULL,  -- ELIMINATION, RECLASSIFICATION, TRANSLATION, ADJUSTMENT
    BudgetHeaderID          NUMBER(38,0) NOT NULL,
    FiscalPeriodID          NUMBER(38,0) NOT NULL,
    PostingDate             DATE NOT NULL,
    Description             VARCHAR(500) NULL,
    StatusCode              VARCHAR(15) NOT NULL DEFAULT 'DRAFT',
    -- Entity tracking
    SourceEntityCode        VARCHAR(20) NULL,
    TargetEntityCode        VARCHAR(20) NULL,
    -- Reversal handling
    IsAutoReverse           BOOLEAN NOT NULL DEFAULT FALSE,
    ReversalPeriodID        NUMBER(38,0) NULL,
    ReversedFromJournalID   NUMBER(38,0) NULL,
    IsReversed              BOOLEAN NOT NULL DEFAULT FALSE,
    -- Totals (denormalized)
    TotalDebits             NUMBER(19,4) NOT NULL DEFAULT 0,
    TotalCredits            NUMBER(19,4) NOT NULL DEFAULT 0,
    -- IsBalanced computed column removed - calculate as: (TotalDebits = TotalCredits)
    -- Approval workflow
    PreparedByUserID        NUMBER(38,0) NULL,
    PreparedDateTime        TIMESTAMP_NTZ(9) NULL,
    ReviewedByUserID        NUMBER(38,0) NULL,
    ReviewedDateTime        TIMESTAMP_NTZ(9) NULL,
    ApprovedByUserID        NUMBER(38,0) NULL,
    ApprovedDateTime        TIMESTAMP_NTZ(9) NULL,
    PostedByUserID          NUMBER(38,0) NULL,
    PostedDateTime          TIMESTAMP_NTZ(9) NULL,
    -- FILESTREAM columns removed (no Snowflake equivalent)
    -- AttachmentData/AttachmentRowGuid removed - store attachments externally
    CONSTRAINT PK_ConsolidationJournal PRIMARY KEY (JournalID),
    CONSTRAINT UQ_ConsolidationJournal_Number UNIQUE (JournalNumber),
    CONSTRAINT FK_ConsolidationJournal_Header FOREIGN KEY (BudgetHeaderID)
        REFERENCES PLANNING.BudgetHeader (BudgetHeaderID),
    CONSTRAINT FK_ConsolidationJournal_Period FOREIGN KEY (FiscalPeriodID)
        REFERENCES PLANNING.FiscalPeriod (FiscalPeriodID),
    CONSTRAINT FK_ConsolidationJournal_Reversed FOREIGN KEY (ReversedFromJournalID)
        REFERENCES PLANNING.ConsolidationJournal (JournalID)
);
