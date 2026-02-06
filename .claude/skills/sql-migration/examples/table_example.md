# Example: Table Migration

## SQL Server Source

```sql
CREATE TABLE Planning.FiscalPeriod (
    FiscalPeriodID      INT IDENTITY(1,1) NOT NULL,
    FiscalYear          SMALLINT NOT NULL,
    FiscalQuarter       TINYINT NOT NULL,
    FiscalMonth         TINYINT NOT NULL,
    PeriodName          NVARCHAR(50) NOT NULL,
    StartDate           DATE NOT NULL,
    EndDate             DATE NOT NULL,
    IsClosed            BIT NOT NULL DEFAULT 0,
    ClosedDateTime      DATETIME2(7) NULL,
    ClosedByUserID      INT NULL,
    PeriodSequence      INT NOT NULL,
    RowVersion          ROWVERSION NOT NULL,
    CreatedDateTime     DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
    ModifiedDateTime    DATETIME2(7) NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_FiscalPeriod PRIMARY KEY CLUSTERED (FiscalPeriodID),
    CONSTRAINT UQ_FiscalPeriod_Sequence UNIQUE (PeriodSequence),
    CONSTRAINT CK_FiscalPeriod_Quarter CHECK (FiscalQuarter BETWEEN 1 AND 4),
    CONSTRAINT CK_FiscalPeriod_Month CHECK (FiscalMonth BETWEEN 1 AND 12)
);
```

## Snowflake Target

```sql
CREATE OR REPLACE TABLE PLANNING.FiscalPeriod (
    FiscalPeriodID      INT AUTOINCREMENT NOT NULL,
    FiscalYear          SMALLINT NOT NULL,
    FiscalQuarter       SMALLINT NOT NULL,  -- TINYINT → SMALLINT
    FiscalMonth         SMALLINT NOT NULL,  -- TINYINT → SMALLINT
    PeriodName          VARCHAR(50) NOT NULL,  -- NVARCHAR → VARCHAR
    StartDate           DATE NOT NULL,
    EndDate             DATE NOT NULL,
    IsClosed            BOOLEAN NOT NULL DEFAULT FALSE,  -- BIT → BOOLEAN
    ClosedDateTime      TIMESTAMP_NTZ NULL,  -- DATETIME2 → TIMESTAMP_NTZ
    ClosedByUserID      INT NULL,
    PeriodSequence      INT NOT NULL,
    -- RowVersion REMOVED (no equivalent)
    CreatedDateTime     TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ModifiedDateTime    TIMESTAMP_NTZ NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    
    CONSTRAINT PK_FiscalPeriod PRIMARY KEY (FiscalPeriodID),
    CONSTRAINT UQ_FiscalPeriod_Sequence UNIQUE (PeriodSequence)
    -- CHECK constraints work the same
    -- CONSTRAINT CK_FiscalPeriod_Quarter CHECK (FiscalQuarter BETWEEN 1 AND 4),
    -- CONSTRAINT CK_FiscalPeriod_Month CHECK (FiscalMonth BETWEEN 1 AND 12)
);
```

## Changes Made

| Change | Reason |
|--------|--------|
| `IDENTITY(1,1)` → `AUTOINCREMENT` | Snowflake syntax |
| `TINYINT` → `SMALLINT` | No TINYINT in Snowflake |
| `NVARCHAR` → `VARCHAR` | Snowflake is UTF-8 native |
| `BIT` → `BOOLEAN` | Different type |
| `DATETIME2` → `TIMESTAMP_NTZ` | Different type name |
| `ROWVERSION` → removed | No equivalent |
| `SYSUTCDATETIME()` → `CURRENT_TIMESTAMP()` | Different function |
| `CLUSTERED` → removed | Snowflake handles clustering differently |
