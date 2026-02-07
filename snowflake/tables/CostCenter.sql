/*
    CostCenter - Organizational hierarchy for cost allocation
    Dependencies: None (base table)
    Translated from SQL Server to Snowflake
    
    Note: HIERARCHYID replaced with VARCHAR(900), computed columns removed, temporal features removed
*/

-- Use the correct database
USE DATABASE FINANCIAL_PLANNING;

-- Drop table if exists to ensure clean deployment
DROP TABLE IF EXISTS Planning.CostCenter;

CREATE TABLE Planning.CostCenter (
    CostCenterID            NUMBER(38,0) NOT NULL AUTOINCREMENT START 1 INCREMENT 1,
    CostCenterCode          VARCHAR(20) NOT NULL,
    CostCenterName          VARCHAR(100) NOT NULL,
    ParentCostCenterID      NUMBER(38,0) NULL,
    HierarchyPath           VARCHAR(900) NULL,
    HierarchyLevel          NUMBER(38,0) NULL,
    ManagerEmployeeID       NUMBER(38,0) NULL,
    DepartmentCode          VARCHAR(10) NULL,
    IsActive                BOOLEAN NOT NULL DEFAULT TRUE,
    EffectiveFromDate       DATE NOT NULL,
    EffectiveToDate         DATE NULL,
    AllocationWeight        DECIMAL(5,4) NOT NULL DEFAULT 1.0000,
    ValidFrom               TIMESTAMP_NTZ(7) NOT NULL,
    ValidTo                 TIMESTAMP_NTZ(7) NOT NULL,
    CONSTRAINT PK_CostCenter PRIMARY KEY (CostCenterID),
    CONSTRAINT UQ_CostCenter_Code UNIQUE (CostCenterCode),
    CONSTRAINT FK_CostCenter_Parent FOREIGN KEY (ParentCostCenterID) 
        REFERENCES Planning.CostCenter (CostCenterID)
);
