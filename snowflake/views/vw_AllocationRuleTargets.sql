CREATE OR REPLACE VIEW FINANCIAL_PLANNING.PLANNING.vw_AllocationRuleTargets AS
SELECT 
    ar.AllocationRuleID,
    ar.RuleName,
    ar.RuleCode,
    ar.SourceCostCenterID,
    src_cc.CostCenterCode AS SourceCostCenterCode,
    src_cc.CostCenterName AS SourceCostCenterName,
    ar.SourceGLAccountID,
    gla.AccountNumber AS SourceAccountNumber,
    gla.AccountName AS SourceAccountName,
    ar.AllocationMethod,
    ar.AllocationBasis,
    ar.AllocationPercent,
    ar.Priority,
    tgt_cc.CostCenterID AS TargetCostCenterID,
    tgt_cc.CostCenterCode AS TargetCostCenterCode,
    tgt_cc.CostCenterName AS TargetCostCenterName
FROM FINANCIAL_PLANNING.PLANNING.AllocationRule ar
LEFT JOIN FINANCIAL_PLANNING.PLANNING.CostCenter src_cc 
    ON ar.SourceCostCenterID = src_cc.CostCenterID
LEFT JOIN FINANCIAL_PLANNING.PLANNING.GLAccount gla 
    ON ar.SourceGLAccountID = gla.GLAccountID
LEFT JOIN FINANCIAL_PLANNING.PLANNING.CostCenter tgt_cc 
    ON tgt_cc.ParentCostCenterID = src_cc.CostCenterID
WHERE ar.IsActive = TRUE;
