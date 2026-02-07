/*
    GLAccount - General Ledger Account master
    Dependencies: None (base table, self-referencing FK)

    Translation notes:
    - SPARSE columns → Regular columns (no SPARSE in Snowflake)
    - CHAR(1)/CHAR(3) → VARCHAR (Snowflake converts CHAR to VARCHAR)
    - TINYINT → NUMBER(3,0)
    - CHECK constraints removed (not supported)
    - COLUMNSTORE index removed (Snowflake uses columnar storage by default)
*/

USE DATABASE FINANCIAL_PLANNING;
USE SCHEMA PLANNING;

CREATE OR REPLACE TABLE PLANNING.GLAccount (
    GLAccountID             NUMBER(38,0) AUTOINCREMENT NOT NULL,
    AccountNumber           VARCHAR(20) NOT NULL,
    AccountName             VARCHAR(150) NOT NULL,
    AccountType             VARCHAR(1) NOT NULL,  -- A=Asset, L=Liability, E=Equity, R=Revenue, X=Expense
    AccountSubType          VARCHAR(30) NULL,
    ParentAccountID         NUMBER(38,0) NULL,
    AccountLevel            NUMBER(3,0) NOT NULL DEFAULT 1,
    IsPostable              BOOLEAN NOT NULL DEFAULT TRUE,
    IsBudgetable            BOOLEAN NOT NULL DEFAULT TRUE,
    IsStatistical           BOOLEAN NOT NULL DEFAULT FALSE,
    NormalBalance           VARCHAR(1) NOT NULL DEFAULT 'D',  -- D=Debit, C=Credit
    CurrencyCode            VARCHAR(3) NOT NULL DEFAULT 'USD',
    ConsolidationAccountID  NUMBER(38,0) NULL,
    IntercompanyFlag        BOOLEAN NOT NULL DEFAULT FALSE,
    IsActive                BOOLEAN NOT NULL DEFAULT TRUE,
    CreatedDateTime         TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ModifiedDateTime        TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    -- Sparse columns (SPARSE keyword removed - not supported in Snowflake)
    TaxCode                 VARCHAR(20) NULL,
    StatutoryAccountCode    VARCHAR(30) NULL,
    IFRSAccountCode         VARCHAR(30) NULL,
    CONSTRAINT PK_GLAccount PRIMARY KEY (GLAccountID),
    CONSTRAINT UQ_GLAccount_Number UNIQUE (AccountNumber),
    CONSTRAINT FK_GLAccount_Parent FOREIGN KEY (ParentAccountID)
        REFERENCES PLANNING.GLAccount (GLAccountID)
    -- CHECK constraints removed (not supported):
    -- CK_GLAccount_Type: AccountType IN ('A','L','E','R','X')
    -- CK_GLAccount_Balance: NormalBalance IN ('D','C')
);

-- Note: COLUMNSTORE index removed - Snowflake uses columnar storage by default
