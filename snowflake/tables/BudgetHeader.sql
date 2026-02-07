CREATE TABLE IF NOT EXISTS FINANCIAL_PLANNING.PLANNING.BudgetHeader (
    BudgetHeaderID INT AUTOINCREMENT PRIMARY KEY,
    BudgetCode VARCHAR(50) NOT NULL,
    BudgetName VARCHAR(200),
    BudgetType VARCHAR(20),
    ScenarioType VARCHAR(20),
    FiscalYear INT,
    StartPeriodID INT,
    EndPeriodID INT,
    StatusCode VARCHAR(20),
    VersionNumber INT DEFAULT 1,
    CreatedDateTime TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
