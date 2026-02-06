#!/bin/bash
#
# Full Cleanup Script
# Removes ALL test data, procedures, and generated files for fresh execution
#

echo "🧹 Starting full cleanup..."

# Step 1: Clean up Snowflake (test data and procedures)
echo "  → Cleaning up Snowflake..."
/Users/ravikiran/Library/Python/3.9/bin/snow sql -f scripts/cleanup-and-reset.sql

# Step 2: Delete generated verification reports
echo "  → Deleting verification results..."
rm -f test/results/*.md

# Step 3: Delete generated test data scripts (will be regenerated)
echo "  → Deleting test data scripts..."
rm -f test/data/snowflake/*.sql
rm -f test/data/sqlserver/*.sql

# Step 4: Delete migrated Snowflake code (will be regenerated)
echo "  → Deleting migrated Snowflake code..."
rm -f snowflake/tables/*.sql
rm -f snowflake/views/*.sql
rm -f snowflake/functions/*.sql
rm -f snowflake/StoredProcedures/*.sql

echo ""
echo "✅ Cleanup complete!"
echo ""
echo "Ready for fresh run. Execute:"
echo "  /sql-migration-planner usp_ProcessBudgetConsolidation"
echo "  /sql-migration"
echo "  /test-data-generator usp_ProcessBudgetConsolidation"
echo "  /sql-migration-verify"
