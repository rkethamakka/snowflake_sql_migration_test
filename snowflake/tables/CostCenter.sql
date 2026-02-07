/*
    CostCenter - Organizational hierarchy for cost allocation
    Dependencies: None (base table, self-referencing FK)

    Translation notes:
    - HIERARCHYID → VARCHAR(900) to store path as string (e.g., /1/2/3/)
    - Computed column (GetLevel()) → Regular column, calculate in application/procedure
    - Temporal table (SYSTEM_VERSIONING) → Not supported, removed
    - WITH clause removed
*/

USE DATABASE FINANCIAL_PLANNING;
USE SCHEMA PLANNING;

CREATE OR REPLACE TABLE PLANNING.CostCenter (
    CostCenterID            NUMBER(38,0) AUTOINCREMENT NOT NULL,
    CostCenterCode          VARCHAR(20) NOT NULL,
    CostCenterName          VARCHAR(100) NOT NULL,
    ParentCostCenterID      NUMBER(38,0) NULL,
    HierarchyPath           VARCHAR(900) NULL,  -- Store as string path, e.g., /1/2/3/
    HierarchyLevel          NUMBER(3,0) NULL,  -- Manually maintained instead of computed
    ManagerEmployeeID       NUMBER(38,0) NULL,
    DepartmentCode          VARCHAR(10) NULL,
    IsActive                BOOLEAN NOT NULL DEFAULT TRUE,
    EffectiveFromDate       DATE NOT NULL,
    EffectiveToDate         DATE NULL,
    AllocationWeight        NUMBER(5,4) NOT NULL DEFAULT 1.0000,
    -- Temporal columns removed (SYSTEM_VERSIONING not supported)
    -- ValidFrom/ValidTo removed
    CreatedDateTime         TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    ModifiedDateTime        TIMESTAMP_NTZ(9) NOT NULL DEFAULT CURRENT_TIMESTAMP(),
    CONSTRAINT PK_CostCenter PRIMARY KEY (CostCenterID),
    CONSTRAINT UQ_CostCenter_Code UNIQUE (CostCenterCode),
    CONSTRAINT FK_CostCenter_Parent FOREIGN KEY (ParentCostCenterID)
        REFERENCES PLANNING.CostCenter (CostCenterID)
    -- CHECK constraint removed: AllocationWeight BETWEEN 0 AND 1
);

-- Note: HierarchyPath index removed - Snowflake doesn't support spatial indexes
