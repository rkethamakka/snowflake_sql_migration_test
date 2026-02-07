SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('Planning.usp_BulkImportBudgetData', 'P') IS NOT NULL
    DROP PROCEDURE Planning.usp_BulkImportBudgetData;
GO

/*
    usp_BulkImportBudgetData - Bulk import budget data with validation
    FIXED VERSION: Proper schema.table parsing for dynamic SQL
*/
CREATE PROCEDURE Planning.usp_BulkImportBudgetData
    @ImportSource           VARCHAR(20),
    @FilePath               NVARCHAR(500) = NULL,
    @FormatFilePath         NVARCHAR(500) = NULL,
    @BudgetData             Planning.BudgetLineItemTableType READONLY,
    @StagingTableName       NVARCHAR(128) = NULL,
    @LinkedServerName       NVARCHAR(128) = NULL,
    @LinkedServerQuery      NVARCHAR(MAX) = NULL,
    @TargetBudgetHeaderID   INT,
    @ValidationMode         VARCHAR(20) = 'STRICT',
    @DuplicateHandling      VARCHAR(20) = 'REJECT',
    @BatchSize              INT = 10000,
    @UseParallelLoad        BIT = 1,
    @MaxDegreeOfParallelism INT = 4,
    @ImportResults          XML = NULL OUTPUT,
    @RowsImported           INT = NULL OUTPUT,
    @RowsRejected           INT = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    
    DECLARE @StartTime DATETIME2 = SYSUTCDATETIME();
    DECLARE @ImportBatchID UNIQUEIDENTIFIER = NEWID();
    DECLARE @ErrorMessage NVARCHAR(4000);
    DECLARE @DynamicSQL NVARCHAR(MAX);
    DECLARE @TotalRows INT = 0;
    DECLARE @ValidRows INT = 0;
    DECLARE @InvalidRows INT = 0;
    
    -- Staging table for imported data
    CREATE TABLE #ImportStaging (
        RowID                   INT IDENTITY(1,1) PRIMARY KEY,
        GLAccountID             INT NULL,
        AccountNumber           VARCHAR(20) NULL,
        CostCenterID            INT NULL,
        CostCenterCode          VARCHAR(20) NULL,
        FiscalPeriodID          INT NULL,
        FiscalYear              SMALLINT NULL,
        FiscalMonth             TINYINT NULL,
        OriginalAmount          DECIMAL(19,4) NULL,
        AdjustedAmount          DECIMAL(19,4) NULL,
        SpreadMethodCode        VARCHAR(10) NULL,
        Notes                   NVARCHAR(500) NULL,
        IsValid                 BIT DEFAULT 1,
        ValidationErrors        NVARCHAR(MAX) NULL,
        IsProcessed             BIT DEFAULT 0
    );
    
    -- Error tracking
    CREATE TABLE #ImportErrors (
        ErrorID     INT IDENTITY(1,1) PRIMARY KEY,
        RowID       INT,
        ErrorCode   VARCHAR(20),
        ErrorMessage NVARCHAR(500),
        Severity    VARCHAR(10)
    );
    
    BEGIN TRY
        -- Load from staging table
        IF @ImportSource = 'STAGING_TABLE'
        BEGIN
            IF @StagingTableName IS NULL
            BEGIN
                RAISERROR('Staging table name is required', 16, 1);
                RETURN -1;
            END
            
            -- FIX: Properly parse schema.table and quote each part
            DECLARE @SchemaName NVARCHAR(128);
            DECLARE @TableName NVARCHAR(128);
            DECLARE @DotPos INT = CHARINDEX('.', @StagingTableName);
            
            IF @DotPos > 0
            BEGIN
                SET @SchemaName = QUOTENAME(LEFT(@StagingTableName, @DotPos - 1));
                SET @TableName = QUOTENAME(SUBSTRING(@StagingTableName, @DotPos + 1, LEN(@StagingTableName)));
            END
            ELSE
            BEGIN
                SET @SchemaName = N'';
                SET @TableName = QUOTENAME(@StagingTableName);
            END
            
            SET @DynamicSQL = N'
                INSERT INTO #ImportStaging (
                    AccountNumber, CostCenterCode, FiscalYear, FiscalMonth,
                    OriginalAmount, AdjustedAmount, SpreadMethodCode, Notes
                )
                SELECT 
                    AccountNumber, CostCenterCode, FiscalYear, FiscalMonth,
                    OriginalAmount, AdjustedAmount, SpreadMethodCode, Notes
                FROM ' + CASE WHEN @SchemaName = N'' THEN @TableName 
                              ELSE @SchemaName + N'.' + @TableName END + N';';
            
            EXEC sp_executesql @DynamicSQL;
            SET @TotalRows = @@ROWCOUNT;
        END
        ELSE IF @ImportSource = 'TVP'
        BEGIN
            INSERT INTO #ImportStaging (
                GLAccountID, CostCenterID, FiscalPeriodID,
                OriginalAmount, AdjustedAmount, SpreadMethodCode, Notes
            )
            SELECT 
                GLAccountID, CostCenterID, FiscalPeriodID,
                OriginalAmount, AdjustedAmount, SpreadMethodCode, Notes
            FROM @BudgetData;
            
            SET @TotalRows = @@ROWCOUNT;
        END
        
        -- Resolve lookups
        UPDATE stg SET stg.GLAccountID = gla.GLAccountID
        FROM #ImportStaging stg
        INNER JOIN Planning.GLAccount gla ON stg.AccountNumber = gla.AccountNumber
        WHERE stg.GLAccountID IS NULL AND stg.AccountNumber IS NOT NULL;
        
        UPDATE stg SET stg.CostCenterID = cc.CostCenterID
        FROM #ImportStaging stg
        INNER JOIN Planning.CostCenter cc ON stg.CostCenterCode = cc.CostCenterCode
        WHERE stg.CostCenterID IS NULL AND stg.CostCenterCode IS NOT NULL;
        
        UPDATE stg SET stg.FiscalPeriodID = fp.FiscalPeriodID
        FROM #ImportStaging stg
        INNER JOIN Planning.FiscalPeriod fp 
            ON stg.FiscalYear = fp.FiscalYear AND stg.FiscalMonth = fp.FiscalMonth
        WHERE stg.FiscalPeriodID IS NULL 
          AND stg.FiscalYear IS NOT NULL AND stg.FiscalMonth IS NOT NULL;
        
        -- Validation
        IF @ValidationMode <> 'NONE'
        BEGIN
            INSERT INTO #ImportErrors (RowID, ErrorCode, ErrorMessage, Severity)
            SELECT RowID, 'MISSING_ACCOUNT', 'GL Account not found', 'ERROR'
            FROM #ImportStaging WHERE GLAccountID IS NULL;
            
            INSERT INTO #ImportErrors (RowID, ErrorCode, ErrorMessage, Severity)
            SELECT RowID, 'MISSING_COSTCENTER', 'Cost Center not found', 'ERROR'
            FROM #ImportStaging WHERE CostCenterID IS NULL;
            
            INSERT INTO #ImportErrors (RowID, ErrorCode, ErrorMessage, Severity)
            SELECT RowID, 'MISSING_PERIOD', 'Fiscal Period not found', 'ERROR'
            FROM #ImportStaging WHERE FiscalPeriodID IS NULL;
            
            -- Mark invalid rows
            UPDATE stg
            SET IsValid = 0, 
                ValidationErrors = (
                    SELECT STRING_AGG(ErrorCode + ': ' + ErrorMessage, '; ')
                    FROM #ImportErrors e WHERE e.RowID = stg.RowID
                )
            FROM #ImportStaging stg
            WHERE EXISTS (SELECT 1 FROM #ImportErrors e WHERE e.RowID = stg.RowID AND e.Severity = 'ERROR');
        END
        
        -- Count valid/invalid
        SELECT 
            @ValidRows = SUM(CASE WHEN IsValid = 1 THEN 1 ELSE 0 END),
            @InvalidRows = SUM(CASE WHEN IsValid = 0 THEN 1 ELSE 0 END)
        FROM #ImportStaging;
        
        -- Insert valid rows
        INSERT INTO Planning.BudgetLineItem (
            BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
            OriginalAmount, AdjustedAmount
        )
        SELECT 
            @TargetBudgetHeaderID,
            GLAccountID,
            CostCenterID,
            FiscalPeriodID,
            OriginalAmount,
            ISNULL(AdjustedAmount, 0)
        FROM #ImportStaging
        WHERE IsValid = 1;
        
        SET @RowsImported = @@ROWCOUNT;
        SET @RowsRejected = @InvalidRows;
        
    END TRY
    BEGIN CATCH
        SET @ErrorMessage = ERROR_MESSAGE();
        SET @RowsImported = 0;
        SET @RowsRejected = @TotalRows;
    END CATCH
    
    -- Build results XML
    SET @ImportResults = (
        SELECT 
            @ImportBatchID AS '@BatchID',
            @ImportSource AS '@Source',
            @TargetBudgetHeaderID AS '@TargetBudgetID',
            DATEDIFF(MILLISECOND, @StartTime, SYSUTCDATETIME()) AS '@DurationMs',
            (
                SELECT 
                    @TotalRows AS TotalRows,
                    @ValidRows AS ValidRows,
                    @InvalidRows AS InvalidRows,
                    @RowsImported AS ImportedRows,
                    @RowsRejected AS RejectedRows
                FOR XML PATH('Summary'), TYPE
            )
        FOR XML PATH('ImportResults')
    );
    
    -- Cleanup
    DROP TABLE IF EXISTS #ImportStaging;
    DROP TABLE IF EXISTS #ImportErrors;
    
    RETURN CASE WHEN @ErrorMessage IS NULL THEN 0 ELSE -1 END;
END
GO
