/*
    tvf_ExplodeCostCenterHierarchy - Explode cost center hierarchy
    
    SQL Server → Snowflake Translation:
    - Multi-statement TVF with WHILE loop → SQL table function with recursive CTE
    - INT → FLOAT (parameters), NUMBER(38,0) (return columns)
    - BIT → BOOLEAN
    - DATE → DATE
    - DECIMAL(18,10) → NUMBER(18,10)
    - NVARCHAR → VARCHAR
    - Removed SCHEMABINDING
    - WHILE loop replaced with recursive CTE
*/

CREATE OR REPLACE FUNCTION FINANCIAL_PLANNING.PLANNING.TVF_EXPLODECOSTCENTERHIERARCHY(
    ROOT_COST_CENTER_ID FLOAT,
    MAX_DEPTH FLOAT,
    INCLUDE_INACTIVE BOOLEAN,
    AS_OF_DATE DATE
)
RETURNS TABLE (
    COSTCENTERID NUMBER(38,0),
    COSTCENTERCODE VARCHAR(20),
    COSTCENTERNAME VARCHAR(100),
    PARENTCOSTCENTERID NUMBER(38,0),
    HIERARCHYLEVEL NUMBER(38,0),
    HIERARCHYPATH VARCHAR(500),
    SORTPATH VARCHAR(500),
    ISLEAF BOOLEAN,
    CHILDCOUNT NUMBER(38,0),
    CUMULATIVEWEIGHT NUMBER(18,10)
)
AS
$$
    WITH RECURSIVE hierarchy AS (
        -- Root level (anchor member)
        SELECT 
            cc.COSTCENTERID,
            cc.COSTCENTERCODE,
            cc.COSTCENTERNAME,
            cc.PARENTCOSTCENTERID,
            0 AS HIERARCHYLEVEL,
            CAST(cc.COSTCENTERNAME AS VARCHAR(500)) AS HIERARCHYPATH,
            CAST(LPAD(cc.COSTCENTERID::VARCHAR, 10, '0') AS VARCHAR(500)) AS SORTPATH,
            FALSE AS ISLEAF,
            0 AS CHILDCOUNT,
            cc.ALLOCATIONWEIGHT AS CUMULATIVEWEIGHT
        FROM FINANCIAL_PLANNING.PLANNING.COSTCENTER cc
        WHERE (
            (ROOT_COST_CENTER_ID IS NULL AND cc.PARENTCOSTCENTERID IS NULL)
            OR cc.COSTCENTERID = ROOT_COST_CENTER_ID
        )
        AND (cc.ISACTIVE = TRUE OR INCLUDE_INACTIVE = TRUE)
        AND cc.EFFECTIVEFROMDATE <= COALESCE(AS_OF_DATE, CURRENT_DATE())
        AND (cc.EFFECTIVETODATE IS NULL OR cc.EFFECTIVETODATE >= COALESCE(AS_OF_DATE, CURRENT_DATE()))
        
        UNION ALL
        
        -- Recursive member (children)
        SELECT 
            cc.COSTCENTERID,
            cc.COSTCENTERCODE,
            cc.COSTCENTERNAME,
            cc.PARENTCOSTCENTERID,
            h.HIERARCHYLEVEL + 1,
            h.HIERARCHYPATH || ' > ' || cc.COSTCENTERNAME,
            h.SORTPATH || '/' || LPAD(cc.COSTCENTERID::VARCHAR, 10, '0'),
            FALSE AS ISLEAF,
            0 AS CHILDCOUNT,
            h.CUMULATIVEWEIGHT * cc.ALLOCATIONWEIGHT
        FROM FINANCIAL_PLANNING.PLANNING.COSTCENTER cc
        INNER JOIN hierarchy h ON cc.PARENTCOSTCENTERID = h.COSTCENTERID
        WHERE h.HIERARCHYLEVEL < COALESCE(MAX_DEPTH, 10) - 1
          AND (cc.ISACTIVE = TRUE OR INCLUDE_INACTIVE = TRUE)
          AND cc.EFFECTIVEFROMDATE <= COALESCE(AS_OF_DATE, CURRENT_DATE())
          AND (cc.EFFECTIVETODATE IS NULL OR cc.EFFECTIVETODATE >= COALESCE(AS_OF_DATE, CURRENT_DATE()))
    ),
    -- Calculate leaf flags and child counts
    hierarchy_with_flags AS (
        SELECT 
            h.COSTCENTERID,
            h.COSTCENTERCODE,
            h.COSTCENTERNAME,
            h.PARENTCOSTCENTERID,
            h.HIERARCHYLEVEL,
            h.HIERARCHYPATH,
            h.SORTPATH,
            CASE 
                WHEN EXISTS (
                    SELECT 1 
                    FROM hierarchy h2 
                    WHERE h2.PARENTCOSTCENTERID = h.COSTCENTERID
                ) THEN FALSE 
                ELSE TRUE 
            END AS ISLEAF,
            (
                SELECT COUNT(*) 
                FROM hierarchy c 
                WHERE c.PARENTCOSTCENTERID = h.COSTCENTERID
            ) AS CHILDCOUNT,
            h.CUMULATIVEWEIGHT
        FROM hierarchy h
    )
    SELECT * FROM hierarchy_with_flags
$$;
