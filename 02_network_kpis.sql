-- ============================================================================
-- 02 — Network-level KPIs
-- Concepts: JOIN, CASE WHEN inside aggregates, date functions, CTE (WITH)
-- ----------------------------------------------------------------------------
-- The KPIs every last-mile network is judged on:
--   * First-attempt success rate (FAS%)  — the single most important one:
--     every failed first attempt means a re-attempt, i.e. double cost.
--   * On-time delivery rate vs the promised date
--   * Weekly volume trend
-- ============================================================================

-- 2.1  First-attempt success rate across the whole network.
--      Trick: AVG(CASE WHEN ... THEN 1.0 ELSE 0 END) computes a percentage.
SELECT
    COUNT(*)                                                        AS first_attempts,
    ROUND(AVG(CASE WHEN status = 'delivered' THEN 1.0 ELSE 0 END) * 100, 2)
                                                                    AS first_attempt_success_pct
FROM delivery_attempts
WHERE attempt_number = 1;

-- 2.2  On-time delivery: delivered on or before the promised date.
--      We take each package's final successful attempt and compare dates.
WITH final_delivery AS (
    SELECT
        package_id,
        MIN(DATE(attempt_time)) AS delivered_date   -- first successful attempt
    FROM delivery_attempts
    WHERE status = 'delivered'
    GROUP BY package_id
)
SELECT
    COUNT(*)                                                          AS delivered_packages,
    ROUND(AVG(CASE WHEN f.delivered_date <= p.promised_date
                   THEN 1.0 ELSE 0 END) * 100, 2)                     AS on_time_pct
FROM final_delivery f
JOIN packages p ON p.package_id = f.package_id;

-- 2.3  Weekly package volume — is the network growing?
--      strftime('%Y-%W', ...) buckets dates into ISO-ish year-week.
SELECT
    strftime('%Y-%W', r.route_date) AS year_week,
    COUNT(p.package_id)             AS packages
FROM packages p
JOIN routes r ON r.route_id = p.route_id
GROUP BY year_week
ORDER BY year_week;

-- 2.4  Undeliverable rate: packages that failed BOTH attempts.
WITH outcomes AS (
    SELECT
        package_id,
        MAX(CASE WHEN status = 'delivered' THEN 1 ELSE 0 END) AS ever_delivered
    FROM delivery_attempts
    GROUP BY package_id
)
SELECT
    COUNT(*)                                              AS total_packages,
    SUM(1 - ever_delivered)                               AS undelivered,
    ROUND(AVG(1.0 - ever_delivered) * 100, 2)             AS undelivered_pct
FROM outcomes;
