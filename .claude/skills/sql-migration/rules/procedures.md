# Procedural Code: SQL Server → Snowflake

## Procedure Structure

### SQL Server
```sql
CREATE PROCEDURE dbo.MyProc
    @Param1 INT,
    @Param2 VARCHAR(100) = NULL,
    @OutputParam INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    -- logic
END
```

### Snowflake (SQL Scripting)
```sql
CREATE OR REPLACE PROCEDURE MyProc(
    PARAM1 INT,
    PARAM2 VARCHAR DEFAULT NULL
)
RETURNS INT  -- For output, return a value or VARIANT
LANGUAGE SQL
AS
$$
DECLARE
    output_param INT;
BEGIN
    -- logic
    RETURN output_param;
END;
$$;
```

### Snowflake (JavaScript)
```sql
CREATE OR REPLACE PROCEDURE MyProc(PARAM1 FLOAT, PARAM2 STRING)
RETURNS STRING
LANGUAGE JAVASCRIPT
AS
$$
    // JavaScript logic
    var result = PARAM1 + 1;
    return result.toString();
$$;
```

## Variable Declaration

| SQL Server | Snowflake SQL Scripting |
|------------|------------------------|
| `DECLARE @x INT = 5;` | `DECLARE x INT := 5;` or `LET x INT := 5;` |
| `SET @x = 10;` | `x := 10;` |
| `SELECT @x = col FROM t` | `SELECT col INTO x FROM t` |

## Control Flow

### IF/ELSE

```sql
-- SQL Server
IF @x > 10
BEGIN
    SELECT 'big';
END
ELSE
BEGIN
    SELECT 'small';
END

-- Snowflake
IF (x > 10) THEN
    SELECT 'big';
ELSE
    SELECT 'small';
END IF;
```

### WHILE Loop

```sql
-- SQL Server
WHILE @i < 10
BEGIN
    SET @i = @i + 1;
    IF @i = 5 CONTINUE;
    IF @i = 8 BREAK;
END

-- Snowflake
LOOP
    i := i + 1;
    IF (i = 5) THEN
        CONTINUE;
    END IF;
    IF (i = 8) THEN
        BREAK;
    END IF;
    IF (i >= 10) THEN
        BREAK;
    END IF;
END LOOP;

-- Or use FOR loop
FOR i IN 1 TO 10 DO
    -- logic
END FOR;
```

## Cursors → Set-Based Operations

**Cursors don't exist in Snowflake.** Refactor to:

### Option 1: Recursive CTE (for hierarchy traversal)
```sql
-- SQL Server cursor walking hierarchy
DECLARE cur CURSOR FOR SELECT ID, ParentID FROM Tree;
-- ... loop through

-- Snowflake recursive CTE
WITH RECURSIVE tree_walk AS (
    -- Base case
    SELECT ID, ParentID, 1 as Level
    FROM Tree WHERE ParentID IS NULL
    
    UNION ALL
    
    -- Recursive case
    SELECT t.ID, t.ParentID, tw.Level + 1
    FROM Tree t
    JOIN tree_walk tw ON t.ParentID = tw.ID
)
SELECT * FROM tree_walk;
```

### Option 2: JavaScript Procedure (for complex logic)
```sql
CREATE OR REPLACE PROCEDURE process_rows()
RETURNS STRING
LANGUAGE JAVASCRIPT
AS
$$
    var stmt = snowflake.createStatement({sqlText: "SELECT id, name FROM my_table"});
    var rs = stmt.execute();
    
    while (rs.next()) {
        var id = rs.getColumnValue(1);
        var name = rs.getColumnValue(2);
        
        // Process each row
        snowflake.execute({sqlText: `UPDATE other_table SET processed = TRUE WHERE id = ${id}`});
    }
    
    return "Done";
$$;
```

### Option 3: RESULTSET (Snowflake Scripting)
```sql
CREATE OR REPLACE PROCEDURE process_rows()
RETURNS TABLE()
LANGUAGE SQL
AS
$$
DECLARE
    res RESULTSET;
    cur CURSOR FOR SELECT id, name FROM my_table;
BEGIN
    OPEN cur;
    FOR row_var IN cur DO
        -- process row_var.id, row_var.name
    END FOR;
    CLOSE cur;
    RETURN TABLE(res);
END;
$$;
```

## Table Variables → Temporary Tables

```sql
-- SQL Server
DECLARE @TempData TABLE (ID INT, Name VARCHAR(100));
INSERT INTO @TempData VALUES (1, 'test');

-- Snowflake
CREATE OR REPLACE TEMPORARY TABLE TempData (ID INT, Name VARCHAR(100));
INSERT INTO TempData VALUES (1, 'test');
-- Temp table is auto-dropped at session end
```

## Error Handling

### SQL Server TRY-CATCH
```sql
BEGIN TRY
    -- risky operation
END TRY
BEGIN CATCH
    SELECT ERROR_MESSAGE(), ERROR_NUMBER();
    THROW;
END CATCH
```

### Snowflake EXCEPTION
```sql
BEGIN
    -- risky operation
EXCEPTION
    WHEN OTHER THEN
        LET err_msg := SQLERRM;
        LET err_code := SQLCODE;
        -- handle error
        RAISE;  -- re-throw
END;
```

## Transactions

### SQL Server
```sql
BEGIN TRANSACTION;
SAVE TRANSACTION SavePoint1;
-- work
IF @@ERROR <> 0 
    ROLLBACK TRANSACTION SavePoint1;
COMMIT TRANSACTION;
```

### Snowflake
```sql
BEGIN TRANSACTION;
-- work
-- No savepoints in Snowflake!
-- Commit or rollback entire transaction
COMMIT;
-- or ROLLBACK;
```

**Note:** Snowflake has **no savepoints**. Refactor logic to not depend on partial rollbacks.

## Dynamic SQL

### SQL Server sp_executesql
```sql
DECLARE @sql NVARCHAR(MAX) = N'SELECT * FROM ' + @TableName;
DECLARE @count INT;
EXEC sp_executesql @sql, N'@out INT OUTPUT', @out = @count OUTPUT;
```

### Snowflake EXECUTE IMMEDIATE
```sql
DECLARE
    sql_text VARCHAR;
    result_count INT;
BEGIN
    sql_text := 'SELECT COUNT(*) FROM ' || table_name;
    EXECUTE IMMEDIATE sql_text INTO result_count;
    RETURN result_count;
END;
```

## System Variables

| SQL Server | Snowflake |
|------------|-----------|
| `@@ROWCOUNT` | `SQLROWCOUNT` (in procedures) |
| `@@ERROR` | Use EXCEPTION block |
| `@@IDENTITY` | Use RETURNING or sequence |
| `SCOPE_IDENTITY()` | Use RETURNING clause |
| `@@TRANCOUNT` | Not available |
| `@@SPID` | `CURRENT_SESSION()` |

## Not Supported - Must Refactor

| SQL Server | Snowflake Approach |
|------------|-------------------|
| `GOTO` | Restructure with loops/conditions |
| `WAITFOR DELAY` | Use Snowflake Tasks for scheduling |
| `sp_getapplock` | Use Snowflake's transaction isolation |
| `RAISERROR` with state | Use `RAISE` with custom exception |
| `PRINT` | Use `SYSTEM$LOG()` or return messages |
| `sp_send_dbmail` | External notification (use external function) |
| Nested transactions | Not supported - flatten logic |
