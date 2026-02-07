CREATE TABLE IF NOT EXISTS FINANCIAL_PLANNING.PLANNING.CostCenter (
    CostCenterID INT AUTOINCREMENT PRIMARY KEY,
    CostCenterCode VARCHAR(20) NOT NULL,
    CostCenterName VARCHAR(100) NOT NULL,
    ParentCostCenterID INT,
    HierarchyPath VARCHAR(500),
    HierarchyLevel INT,
    IsActive BOOLEAN DEFAULT TRUE,
    EffectiveFromDate DATE,
    EffectiveToDate DATE,
    CreatedDateTime TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
