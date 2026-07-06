-- ============================================================================
-- 05 — Driver tenure vs. performance
-- Concepts: julianday date math, CTEs, window functions (RANK), bucketing
-- ----------------------------------------------------------------------------
-- Hypothesis: drivers in their first 90 days ("rookies") fail more first
-- attempts. If true, the fix is better onboarding / ride-alongs — a cheap,
-- targeted intervention with measurable payoff.
-- ============================================================================

-- 5.1  First-attempt success by tenure bucket AT THE TIME OF THE ROUTE.
--      Note: tenure is computed against route_date, not today — a driver
--      can be a rookie in week 1 of the data and experienced by week 12.
WITH attempt_with_tenure AS (
    SELECT
        a.status,
        julianday(r.route_date) - julianday(d.hire_date) AS tenure_days
    FROM delivery_attempts a
    JOIN packages p ON p.package_id = a.package_id
    JOIN routes   r ON r.route_id   = p.route_id
    JOIN drivers  d ON d.driver_id  = r.driver_id
    WHERE a.attempt_number = 1
)
SELECT
    CASE
        WHEN tenure_days < 90  THEN '1: rookie (<90d)'
        WHEN tenure_days < 365 THEN '2: developing (90-365d)'
        ELSE                        '3: experienced (>1y)'
    END                                                            AS tenure_bucket,
    COUNT(*)                                                       AS first_attempts,
    ROUND(AVG(CASE WHEN status = 'delivered' THEN 1.0 ELSE 0 END) * 100, 2)
                                                                   AS success_pct
FROM attempt_with_tenure
GROUP BY tenure_bucket
ORDER BY tenure_bucket;

-- 5.2  Top 5 and bottom 5 drivers per station by first-attempt success,
--      using RANK() OVER (PARTITION BY ...) — the classic window function.
--      Only drivers with >= 500 first attempts, to avoid small-sample noise.
WITH driver_perf AS (
    SELECT
        r.station_id,
        d.driver_name,
        COUNT(*)                                                   AS attempts,
        ROUND(AVG(CASE WHEN a.status = 'delivered' THEN 1.0 ELSE 0 END) * 100, 2)
                                                                   AS success_pct
    FROM delivery_attempts a
    JOIN packages p ON p.package_id = a.package_id
    JOIN routes   r ON r.route_id   = p.route_id
    JOIN drivers  d ON d.driver_id  = r.driver_id
    WHERE a.attempt_number = 1
    GROUP BY r.station_id, d.driver_id
    HAVING COUNT(*) >= 500
),
ranked AS (
    SELECT
        *,
        RANK() OVER (PARTITION BY station_id ORDER BY success_pct DESC) AS rank_best,
        RANK() OVER (PARTITION BY station_id ORDER BY success_pct ASC)  AS rank_worst
    FROM driver_perf
)
SELECT
    s.station_code,
    CASE WHEN rank_best <= 5 THEN 'top 5' ELSE 'bottom 5' END AS cohort,
    driver_name,
    attempts,
    success_pct
FROM ranked
JOIN delivery_stations s ON s.station_id = ranked.station_id
WHERE rank_best <= 5 OR rank_worst <= 5
ORDER BY s.station_code, success_pct DESC;
