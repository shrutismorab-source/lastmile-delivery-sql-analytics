-- ============================================================================
-- 01 — Data quality checks
-- Concepts: SELECT, COUNT, GROUP BY, LEFT JOIN, IS NULL, HAVING
-- ----------------------------------------------------------------------------
-- Any analysis is only as good as the data underneath it. Before computing
-- KPIs, verify the dataset is complete and internally consistent.
-- ============================================================================

-- 1.1  Row counts per table (sanity check the load)
SELECT 'delivery_stations' AS table_name, COUNT(*) AS rows FROM delivery_stations
UNION ALL SELECT 'drivers',            COUNT(*) FROM drivers
UNION ALL SELECT 'routes',             COUNT(*) FROM routes
UNION ALL SELECT 'packages',           COUNT(*) FROM packages
UNION ALL SELECT 'delivery_attempts',  COUNT(*) FROM delivery_attempts;

-- 1.2  Orphan check: every package must belong to a real route.
--      LEFT JOIN keeps all packages; a NULL on the route side = orphan.
SELECT COUNT(*) AS orphan_packages
FROM packages p
LEFT JOIN routes r ON r.route_id = p.route_id
WHERE r.route_id IS NULL;

-- 1.3  Every package should have at least one delivery attempt
SELECT COUNT(*) AS packages_without_attempts
FROM packages p
LEFT JOIN delivery_attempts a ON a.package_id = p.package_id
WHERE a.attempt_id IS NULL;

-- 1.4  Consistency rule: failure_reason must be NULL when delivered,
--      and NOT NULL when failed. Count violations of both rules.
SELECT
    SUM(CASE WHEN status = 'delivered' AND failure_reason IS NOT NULL THEN 1 ELSE 0 END)
        AS delivered_with_reason,
    SUM(CASE WHEN status = 'failed'    AND failure_reason IS NULL     THEN 1 ELSE 0 END)
        AS failed_without_reason
FROM delivery_attempts;

-- 1.5  Duplicate check: a package should never have two attempts with the
--      same attempt_number.
SELECT package_id, attempt_number, COUNT(*) AS n
FROM delivery_attempts
GROUP BY package_id, attempt_number
HAVING COUNT(*) > 1;
