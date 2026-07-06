-- ============================================================================
-- 03 — Station performance & capacity utilization
-- Concepts: multi-table JOINs, aggregation at different grains, subqueries
-- ----------------------------------------------------------------------------
-- Business question: which sites are underperforming, and WHY?
-- Grain warning (a classic real-world trap): routes and packages live at
-- different levels of detail, so we aggregate each in its own CTE first and
-- only then join — otherwise the route metrics get double-counted.
-- ============================================================================

-- 3.1  Scorecard per station: volume, first-attempt success, route overrun.
WITH pkg_stats AS (                 -- package grain -> station grain
    SELECT
        r.station_id,
        COUNT(*)                                                       AS packages,
        ROUND(AVG(CASE WHEN a.status = 'delivered' THEN 1.0 ELSE 0 END) * 100, 2)
                                                                       AS first_attempt_success_pct
    FROM delivery_attempts a
    JOIN packages p ON p.package_id = a.package_id
    JOIN routes   r ON r.route_id   = p.route_id
    WHERE a.attempt_number = 1
    GROUP BY r.station_id
),
route_stats AS (                    -- route grain -> station grain
    SELECT
        station_id,
        COUNT(*)                                              AS routes,
        ROUND(AVG(planned_stops), 0)                          AS avg_stops_per_route,
        ROUND(AVG(actual_duration_min * 1.0 / planned_duration_min - 1) * 100, 1)
                                                              AS avg_route_overrun_pct
    FROM routes
    GROUP BY station_id
)
SELECT
    s.station_code,
    s.city,
    s.zone_type,
    ps.packages,
    ps.first_attempt_success_pct,
    rs.avg_stops_per_route,
    rs.avg_route_overrun_pct
FROM delivery_stations s
JOIN pkg_stats   ps ON ps.station_id = s.station_id
JOIN route_stats rs ON rs.station_id = s.station_id
ORDER BY ps.first_attempt_success_pct ASC;   -- worst performer first

-- 3.2  Capacity utilization: average daily volume vs. site capacity.
--      >90% utilization is the standard "site is running hot" threshold.
WITH daily_volume AS (
    SELECT
        r.station_id,
        r.route_date,
        COUNT(p.package_id) AS pkgs_that_day
    FROM routes r
    JOIN packages p ON p.route_id = r.route_id
    GROUP BY r.station_id, r.route_date
)
SELECT
    s.station_code,
    s.daily_capacity,
    ROUND(AVG(d.pkgs_that_day), 0)                              AS avg_daily_pkgs,
    ROUND(AVG(d.pkgs_that_day) * 100.0 / s.daily_capacity, 1)   AS avg_utilization_pct,
    ROUND(MAX(d.pkgs_that_day) * 100.0 / s.daily_capacity, 1)   AS peak_utilization_pct
FROM daily_volume d
JOIN delivery_stations s ON s.station_id = d.station_id
GROUP BY s.station_code, s.daily_capacity
ORDER BY avg_utilization_pct DESC;
