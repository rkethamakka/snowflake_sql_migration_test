# Syntax Mappings: SQL Server → Snowflake

## Basic SQL

### SELECT Syntax

| SQL Server | Snowflake |
|------------|-----------|
| `SELECT TOP 10 *` | `SELECT * ... LIMIT 10` |
| `SELECT TOP 10 PERCENT` | `SELECT * ... SAMPLE (10)` |
| `SELECT TOP 10 WITH TIES` | Use window function with QUALIFY |

### String Operations

| SQL Server | Snowflake |
|------------|-----------|
| `'a' + 'b'` | `'a' \|\| 'b'` |
| `CONCAT(a, b)` | `CONCAT(a, b)` | Direct |
| `LEN(str)` | `LENGTH(str)` |
| `CHARINDEX(find, str)` | `POSITION(find IN str)` or `CHARINDEX(find, str)` |
| `SUBSTRING(str, start, len)` | `SUBSTR(str, start, len)` |
| `STUFF(str, start, len, new)` | `INSERT(str, start, len, new)` |
| `REPLICATE(str, n)` | `REPEAT(str, n)` |
| `STRING_SPLIT(str, delim)` | `SPLIT_TO_TABLE(str, delim)` |

### NULL Handling

| SQL Server | Snowflake |
|------------|-----------|
| `ISNULL(x, default)` | `NVL(x, default)` or `COALESCE(x, default)` |
| `NULLIF(a, b)` | `NULLIF(a, b)` | Direct |
| `COALESCE(a, b, c)` | `COALESCE(a, b, c)` | Direct |

### Date/Time Functions

| SQL Server | Snowflake |
|------------|-----------|
| `GETDATE()` | `CURRENT_TIMESTAMP()` |
| `GETUTCDATE()` | `CURRENT_TIMESTAMP()` (if TZ configured) |
| `SYSUTCDATETIME()` | `SYSDATE()` or `CURRENT_TIMESTAMP()` |
| `SYSDATETIME()` | `CURRENT_TIMESTAMP()` |
| `DATEPART(year, date)` | `YEAR(date)` or `DATE_PART('year', date)` |
| `DATEPART(month, date)` | `MONTH(date)` |
| `DATEPART(day, date)` | `DAY(date)` |
| `DATEADD(day, 5, date)` | `DATEADD('day', 5, date)` |
| `DATEDIFF(day, d1, d2)` | `DATEDIFF('day', d1, d2)` |
| `FORMAT(date, 'yyyy-MM-dd')` | `TO_VARCHAR(date, 'YYYY-MM-DD')` |
| `CONVERT(DATE, str)` | `TO_DATE(str)` |
| `CAST(str AS DATE)` | `CAST(str AS DATE)` or `str::DATE` |
| `EOMONTH(date)` | `LAST_DAY(date)` |

### Type Conversion

| SQL Server | Snowflake |
|------------|-----------|
| `CAST(x AS INT)` | `CAST(x AS INT)` or `x::INT` |
| `CONVERT(INT, x)` | `x::INT` or `TRY_CAST(x AS INT)` |
| `TRY_CAST(x AS INT)` | `TRY_CAST(x AS INT)` |
| `TRY_CONVERT(INT, x)` | `TRY_CAST(x AS INT)` |
| `PARSE(str AS DATE)` | `TRY_TO_DATE(str)` |

### Conditional Logic

| SQL Server | Snowflake |
|------------|-----------|
| `IIF(cond, true, false)` | `IFF(cond, true, false)` |
| `CASE WHEN ... END` | `CASE WHEN ... END` | Direct |
| `CHOOSE(idx, a, b, c)` | Use CASE or array |

## Table Operations

### CREATE TABLE

```sql
-- SQL Server
CREATE TABLE t (
    ID INT IDENTITY(1,1) PRIMARY KEY,
    Name NVARCHAR(100) NOT NULL,
    CONSTRAINT UQ_Name UNIQUE (Name)
);

-- Snowflake
CREATE TABLE t (
    ID INT AUTOINCREMENT PRIMARY KEY,
    Name VARCHAR(100) NOT NULL,
    CONSTRAINT UQ_Name UNIQUE (Name)
);
```

### Temporary Tables

| SQL Server | Snowflake |
|------------|-----------|
| `#TempTable` | `CREATE TEMPORARY TABLE TempTable` |
| `##GlobalTemp` | Not supported - use permanent with cleanup |
| `@TableVariable` | Use `CREATE TEMPORARY TABLE` |

### MERGE Statement

```sql
-- SQL Server
MERGE target AS t
USING source AS s ON t.ID = s.ID
WHEN MATCHED THEN UPDATE SET t.Name = s.Name
WHEN NOT MATCHED THEN INSERT (ID, Name) VALUES (s.ID, s.Name);

-- Snowflake (similar but slight differences)
MERGE INTO target AS t
USING source AS s ON t.ID = s.ID
WHEN MATCHED THEN UPDATE SET t.Name = s.Name
WHEN NOT MATCHED THEN INSERT (ID, Name) VALUES (s.ID, s.Name);
```

### OUTPUT Clause

SQL Server:
```sql
INSERT INTO t (Name) OUTPUT inserted.ID VALUES ('test');
```

Snowflake - Use `RETURNING`:
```sql
INSERT INTO t (Name) VALUES ('test') RETURNING ID;
```

## Joins & Subqueries

### CROSS APPLY / OUTER APPLY

SQL Server:
```sql
SELECT * FROM t1 CROSS APPLY fn_GetData(t1.ID)
```

Snowflake:
```sql
-- If fn_GetData returns table, use LATERAL JOIN
SELECT * FROM t1, LATERAL fn_GetData(t1.ID)

-- Or TABLE() function
SELECT * FROM t1, TABLE(fn_GetData(t1.ID))
```

### Common Table Expressions (CTE)

Direct translation - CTEs work the same:
```sql
WITH cte AS (SELECT * FROM t)
SELECT * FROM cte;
```

## Window Functions

Most window functions are the same:
```sql
ROW_NUMBER() OVER (PARTITION BY x ORDER BY y)
RANK() OVER (...)
DENSE_RANK() OVER (...)
LAG(col, 1) OVER (...)
LEAD(col, 1) OVER (...)
```

Snowflake addition - `QUALIFY` clause:
```sql
-- SQL Server (subquery needed)
SELECT * FROM (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY x ORDER BY y) as rn
    FROM t
) sub WHERE rn = 1;

-- Snowflake (cleaner)
SELECT * FROM t
QUALIFY ROW_NUMBER() OVER (PARTITION BY x ORDER BY y) = 1;
```
