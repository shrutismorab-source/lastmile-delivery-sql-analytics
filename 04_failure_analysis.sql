-- ============================================================================
-- 04 — Why do first attempts fail?
-- Concepts: filtered aggregation, pivot-style CASE columns, strftime weekday
-- ----------------------------------------------------------------------------
-- Each failed first attempt forces a second trip to the same address —
-- roughly doubling the delivery cost of that package. Knowing WHERE and WHY
-- failures happen tells us which countermeasure to fund (lockers, photo
-- on delivery, address validation, driver training...).
-- ============================================================================

-- 4.1  Failure reason breakdown, network-wide
SELECT
    failure_reason,
    COUNT(*)                                            AS failures,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1)  AS pct_of_failures
FROM delivery_attempts
WHERE attempt_number = 1 AND status = 'failed'
GROUP BY failure_reason
ORDER BY failures DESC;

-- 4.2  Failure reasons by zone type (urban vs suburban vs rural),
--      pivoted into columns with CASE WHEN for easy side-by-side reading.
SELECT
    s.zone_type,
    COUNT(*) AS total_failures,
    SUM(CASE WHEN a.failure_reason = 'customer_not_home' THEN 1 ELSE 0 END) AS not_home,
    SUM(CASE WHEN a.failure_reason = 'access_problem'    THEN 1 ELSE 0 END) AS access_problem,
    SUM(CASE WHEN a.failure_reason = 'address_issue'     THEN 1 ELSE 0 END) AS address_issue,
    SUM(CASE WHEN a.failure_reason = 'out_of_time'       THEN 1 ELSE 0 END) AS out_of_time,
    SUM(CASE WHEN a.failure_reason = 'package_damaged'   THEN 1 ELSE 0 END) AS damaged
FROM delivery_attempts a
JOIN packages p ON p.package_id = a.package_id
JOIN routes   r ON r.route_id   = p.route_id
JOIN delivery_stations s ON s.station_id = r.station_id
WHERE a.attempt_number = 1 AND a.status = 'failed'
GROUP BY s.zone_type
ORDER BY total_failures DESC;

-- 4.3  Do failures spike on certain weekdays? (0 = Sunday ... 6 = Saturday)
--      Hypothesis: 'customer_not_home' should peak Mon-Fri working hours.
SELECT
    CASE strftime('%w', attempt_time)
        WHEN '1' THEN 'Mon' WHEN '2' THEN 'Tue' WHEN '3' THEN 'Wed'
        WHEN '4' THEN 'Thu' WHEN '5' THEN 'Fri' WHEN '6' THEN 'Sat'
        ELSE 'Sun' END                                       AS weekday,
    COUNT(*)                                                 AS first_attempts,
    ROUND(AVG(CASE WHEN status = 'failed' THEN 1.0 ELSE 0 END) * 100, 2)
                                                             AS failure_rate_pct
FROM delivery_attempts
WHERE attempt_number = 1
GROUP BY strftime('%w', attempt_time)
ORDER BY strftime('%w', attempt_time);

-- 4.4  Cost of failure: estimate re-attempt cost per station.
--      Assumption: each re-attempt costs ~EUR 2.50 in driver time + fuel.
SELECT
    s.station_code,
    COUNT(*)                       AS second_attempts,
    ROUND(COUNT(*) * 2.50, 0)      AS est_reattempt_cost_eur
FROM delivery_attempts a
JOIN packages p ON p.package_id = a.package_id
JOIN routes   r ON r.route_id   = p.route_id
JOIN delivery_stations s ON s.station_id = r.station_id
WHERE a.attempt_number = 2
GROUP BY s.station_code
ORDER BY second_attempts DESC;
