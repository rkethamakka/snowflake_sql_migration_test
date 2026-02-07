CREATE TABLE IF NOT EXISTS FINANCIAL_PLANNING.PLANNING.AllocationRule (
    AllocationRuleID INT AUTOINCREMENT PRIMARY KEY,
    RuleName VARCHAR(100) NOT NULL,
    RuleCode VARCHAR(20) NOT NULL,
    SourceCostCenterID INT,
    SourceGLAccountID INT,
    AllocationMethod VARCHAR(20),
    AllocationBasis VARCHAR(50),
    AllocationPercent NUMBER(5,2),
    IsActive BOOLEAN DEFAULT TRUE,
    EffectiveFromDate DATE,
    EffectiveToDate DATE,
    Priority INT DEFAULT 1,
    CreatedDateTime TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
