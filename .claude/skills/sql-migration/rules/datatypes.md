# Data Type Mappings: SQL Server → Snowflake

## Numeric Types

| SQL Server | Snowflake | Notes |
|------------|-----------|-------|
| `TINYINT` | `SMALLINT` | Snowflake min is SMALLINT |
| `SMALLINT` | `SMALLINT` | Direct |
| `INT` | `INT` or `INTEGER` | Direct |
| `BIGINT` | `BIGINT` | Direct |
| `DECIMAL(p,s)` | `NUMBER(p,s)` | Direct |
| `NUMERIC(p,s)` | `NUMBER(p,s)` | Direct |
| `FLOAT` | `FLOAT` | Direct |
| `REAL` | `FLOAT` | Map to FLOAT |
| `MONEY` | `NUMBER(19,4)` | No MONEY type |
| `SMALLMONEY` | `NUMBER(10,4)` | No SMALLMONEY type |

## String Types

| SQL Server | Snowflake | Notes |
|------------|-----------|-------|
| `CHAR(n)` | `CHAR(n)` | Direct (but rarely needed) |
| `VARCHAR(n)` | `VARCHAR(n)` | Direct |
| `VARCHAR(MAX)` | `VARCHAR(16777216)` | Max size in Snowflake |
| `NCHAR(n)` | `CHAR(n)` | No N prefix (UTF-8 native) |
| `NVARCHAR(n)` | `VARCHAR(n)` | No N prefix (UTF-8 native) |
| `NVARCHAR(MAX)` | `VARCHAR(16777216)` | No N prefix |
| `TEXT` | `VARCHAR(16777216)` | Deprecated in SQL Server too |
| `NTEXT` | `VARCHAR(16777216)` | Deprecated |

## Date/Time Types

| SQL Server | Snowflake | Notes |
|------------|-----------|-------|
| `DATE` | `DATE` | Direct |
| `TIME` | `TIME` | Direct |
| `DATETIME` | `TIMESTAMP_NTZ` | No timezone |
| `DATETIME2` | `TIMESTAMP_NTZ` | No timezone |
| `DATETIMEOFFSET` | `TIMESTAMP_TZ` | With timezone |
| `SMALLDATETIME` | `TIMESTAMP_NTZ` | Map to TIMESTAMP |

## Binary Types

| SQL Server | Snowflake | Notes |
|------------|-----------|-------|
| `BINARY(n)` | `BINARY(n)` | Direct |
| `VARBINARY(n)` | `VARBINARY(n)` | Direct |
| `VARBINARY(MAX)` | `VARBINARY(8388608)` | Max 8MB |
| `IMAGE` | `VARBINARY` | Deprecated type |

## Special Types

| SQL Server | Snowflake | Notes |
|------------|-----------|-------|
| `BIT` | `BOOLEAN` | TRUE/FALSE instead of 1/0 |
| `UNIQUEIDENTIFIER` | `VARCHAR(36)` | Use `UUID_STRING()` to generate |
| `XML` | `VARIANT` | Parse with `PARSE_XML()`, query differently |
| `JSON` | `VARIANT` | Parse with `PARSE_JSON()` |
| `HIERARCHYID` | `VARCHAR(4000)` | **No equivalent** - use materialized path pattern |
| `GEOGRAPHY` | `GEOGRAPHY` | Direct (Snowflake has geo support) |
| `GEOMETRY` | `GEOMETRY` | Direct |

## Types with NO Equivalent

| SQL Server | Snowflake Approach |
|------------|-------------------|
| `ROWVERSION` / `TIMESTAMP` | Remove. Use `METADATA$ACTION` in streams or add `MODIFIED_AT TIMESTAMP` column |
| `SQL_VARIANT` | `VARIANT` (but different behavior) |
| `TABLE` (type) | Use temporary tables |
| `CURSOR` | Not a type - refactor logic |

## Identity/Sequences

| SQL Server | Snowflake |
|------------|-----------|
| `INT IDENTITY(1,1)` | `INT AUTOINCREMENT` |
| `INT IDENTITY(100,10)` | `INT AUTOINCREMENT START 100 INCREMENT 10` |
| `SEQUENCE` | `SEQUENCE` (similar syntax) |

## Default Values

| SQL Server | Snowflake |
|------------|-----------|
| `DEFAULT GETDATE()` | `DEFAULT CURRENT_TIMESTAMP()` |
| `DEFAULT SYSUTCDATETIME()` | `DEFAULT CURRENT_TIMESTAMP()` |
| `DEFAULT NEWID()` | `DEFAULT UUID_STRING()` |
| `DEFAULT NEWSEQUENTIALID()` | `DEFAULT UUID_STRING()` (not sequential) |

## Computed Columns

SQL Server:
```sql
FullName AS FirstName + ' ' + LastName PERSISTED
```

Snowflake - **Not supported directly**. Options:
1. Create a VIEW with the computed expression
2. Use a trigger to populate on INSERT/UPDATE
3. Compute in application layer
