SET QUOTED_IDENTIFIER ON;
GO

IF OBJECT_ID('Planning.usp_GenerateRollingForecast', 'P') IS NOT NULL
    DROP PROCEDURE Planning.usp_GenerateRollingForecast;
GO

/*
    usp_GenerateRollingForecast - Generate rolling forecast (FIXED VERSION)
    Simplified to work with existing schema
*/
CREATE PROCEDURE Planning.usp_GenerateRollingForecast
    @BaseBudgetHeaderID         INT,
    @HistoricalPeriods          INT = 12,
    @ForecastPeriods            INT = 12,
    @ForecastMethod             VARCHAR(30) = 'WEIGHTED_AVERAGE',
    @GrowthRateOverride         DECIMAL(8,4) = NULL,
    @OutputFormat               VARCHAR(20) = 'DETAIL',
    @TargetBudgetHeaderID       INT = NULL OUTPUT,
    @ForecastAccuracyMetrics    NVARCHAR(MAX) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SourceFiscalYear SMALLINT;
    DECLARE @RowsCreated INT = 0;
    DECLARE @GrowthFactor DECIMAL(8,4) = ISNULL(@GrowthRateOverride, 0.05);
    
    -- Create temp table for calculations
    CREATE TABLE #ForecastCalc (
        GLAccountID INT,
        CostCenterID INT,
        AvgAmount DECIMAL(19,4),
        TrendFactor DECIMAL(19,4),
        ForecastAmount DECIMAL(19,4)
    );
    
    BEGIN TRY
        -- Get base budget info
        SELECT @SourceFiscalYear = FiscalYear
        FROM Planning.BudgetHeader
        WHERE BudgetHeaderID = @BaseBudgetHeaderID;
        
        IF @SourceFiscalYear IS NULL
        BEGIN
            RAISERROR('Base budget not found', 16, 1);
            RETURN -1;
        END
        
        -- Calculate averages by account/cost center
        INSERT INTO #ForecastCalc (GLAccountID, CostCenterID, AvgAmount, TrendFactor)
        SELECT 
            GLAccountID,
            CostCenterID,
            AVG(FinalAmount) AS AvgAmount,
            ISNULL(
                (MAX(FinalAmount) - MIN(FinalAmount)) / NULLIF(COUNT(*), 0), 
                0
            ) AS TrendFactor
        FROM Planning.BudgetLineItem
        WHERE BudgetHeaderID = @BaseBudgetHeaderID
        GROUP BY GLAccountID, CostCenterID;
        
        -- Apply growth factor
        UPDATE #ForecastCalc
        SET ForecastAmount = AvgAmount * (1 + @GrowthFactor);
        
        -- Create forecast budget header
        INSERT INTO Planning.BudgetHeader (
            BudgetCode, BudgetName, BudgetType, ScenarioType, FiscalYear,
            StartPeriodID, EndPeriodID, StatusCode, VersionNumber
        )
        SELECT 
            BudgetCode + '_FCST_' + FORMAT(GETDATE(), 'yyyyMMdd'),
            BudgetName + ' - Forecast',
            'FORECAST',
            'FORECAST',
            FiscalYear + 1,
            StartPeriodID,
            EndPeriodID,
            'DRAFT',
            1
        FROM Planning.BudgetHeader
        WHERE BudgetHeaderID = @BaseBudgetHeaderID;
        
        SET @TargetBudgetHeaderID = SCOPE_IDENTITY();
        
        -- Generate forecast line items for each period
        INSERT INTO Planning.BudgetLineItem (
            BudgetHeaderID, GLAccountID, CostCenterID, FiscalPeriodID,
            OriginalAmount, AdjustedAmount
        )
        SELECT 
            @TargetBudgetHeaderID,
            fc.GLAccountID,
            fc.CostCenterID,
            fp.FiscalPeriodID,
            fc.ForecastAmount,
            0
        FROM #ForecastCalc fc
        CROSS JOIN (
            SELECT TOP (@ForecastPeriods) FiscalPeriodID
            FROM Planning.FiscalPeriod
            ORDER BY FiscalPeriodID
        ) fp;
        
        SET @RowsCreated = @@ROWCOUNT;
        
        -- Build metrics JSON
        SET @ForecastAccuracyMetrics = (
            SELECT 
                @ForecastMethod AS ForecastMethod,
                @HistoricalPeriods AS HistoricalPeriods,
                @ForecastPeriods AS ForecastPeriods,
                @RowsCreated AS RowsCreated,
                @TargetBudgetHeaderID AS TargetBudgetID
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );
        
    END TRY
    BEGIN CATCH
        SET @ForecastAccuracyMetrics = ERROR_MESSAGE();
        DROP TABLE IF EXISTS #ForecastCalc;
        RETURN -1;
    END CATCH
    
    DROP TABLE IF EXISTS #ForecastCalc;
    RETURN 0;
END
GO
