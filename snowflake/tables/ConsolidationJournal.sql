/*
    ConsolidationJournal - Journal entries for consolidation adjustments
    Dependencies: BudgetHeader, GLAccount, CostCenter, FiscalPeriod

    Snowflake Migration Notes:
    - BIGINT IDENTITY → INTEGER AUTOINCREMENT
    - NVARCHAR → VARCHAR
    - BIT → BOOLEAN
    - DECIMAL(19,4) → NUMBER(19,4)
    - DATETIME2(7) → TIMESTAMP_NTZ
    - Computed column IsBalanced → Cannot create as computed, would need view or materialized column
    - VARBINARY(MAX) FILESTREAM → BINARY (no FILESTREAM equivalent, use stages)
    - UNIQUEIDENTIFIER ROWGUIDCOL → VARCHAR(36) with UUID_STRING()
    - NEWSEQUENTIALID() → UUID_STRING()
    - Indexes converted to comments (Snowflake auto-optimizes)
*/
CREATE TABLE IF NOT EXISTS FINANCIAL_PLANNING.PLANNING.ConsolidationJournal (
    JournalID               INTEGER AUTOINCREMENT PRIMARY KEY,
    JournalNumber           VARCHAR(30) NOT NULL,
    JournalType             VARCHAR(20) NOT NULL,  -- ELIMINATION, RECLASSIFICATION, TRANSLATION, ADJUSTMENT
    BudgetHeaderID          INTEGER NOT NULL,
    FiscalPeriodID          INTEGER NOT NULL,
    PostingDate             DATE NOT NULL,
    Description             VARCHAR(500),
    StatusCode              VARCHAR(15) NOT NULL DEFAULT 'DRAFT',
    -- Entity tracking for multi-entity consolidation
    SourceEntityCode        VARCHAR(20),
    TargetEntityCode        VARCHAR(20),
    -- Reversal handling
    IsAutoReverse           BOOLEAN NOT NULL DEFAULT FALSE,
    ReversalPeriodID        INTEGER,
    ReversedFromJournalID   INTEGER,
    IsReversed              BOOLEAN NOT NULL DEFAULT FALSE,
    -- Totals (denormalized for performance)
    TotalDebits             NUMBER(19,4) NOT NULL DEFAULT 0,
    TotalCredits            NUMBER(19,4) NOT NULL DEFAULT 0,
    -- IsBalanced computed column not supported - use view if needed
    -- Approval workflow
    PreparedByUserID        INTEGER,
    PreparedDateTime        TIMESTAMP_NTZ,
    ReviewedByUserID        INTEGER,
    ReviewedDateTime        TIMESTAMP_NTZ,
    ApprovedByUserID        INTEGER,
    ApprovedDateTime        TIMESTAMP_NTZ,
    PostedByUserID          INTEGER,
    PostedDateTime          TIMESTAMP_NTZ,
    -- Attachments (no FILESTREAM - use Snowflake stages for large files)
    AttachmentData          BINARY,
    AttachmentRowGuid       VARCHAR(36) NOT NULL DEFAULT UUID_STRING(),
    CONSTRAINT UQ_ConsolidationJournal_Number UNIQUE (JournalNumber),
    CONSTRAINT FK_ConsolidationJournal_Header FOREIGN KEY (BudgetHeaderID)
        REFERENCES FINANCIAL_PLANNING.PLANNING.BudgetHeader (BudgetHeaderID),
    CONSTRAINT FK_ConsolidationJournal_Period FOREIGN KEY (FiscalPeriodID)
        REFERENCES FINANCIAL_PLANNING.PLANNING.FiscalPeriod (FiscalPeriodID),
    CONSTRAINT FK_ConsolidationJournal_ReversalPeriod FOREIGN KEY (ReversalPeriodID)
        REFERENCES FINANCIAL_PLANNING.PLANNING.FiscalPeriod (FiscalPeriodID),
    CONSTRAINT FK_ConsolidationJournal_ReversedFrom FOREIGN KEY (ReversedFromJournalID)
        REFERENCES FINANCIAL_PLANNING.PLANNING.ConsolidationJournal (JournalID)
);

-- Note: Snowflake does not require explicit indexes - auto-optimizes based on query patterns
-- Original index: IX_ConsolidationJournal_RowGuid on AttachmentRowGuid
