-- ============================================================================
-- 06 — Capacity planning: when does each site run out of headroom?
-- Concepts: window functions (LAG, AVG OVER), growth rates, simple projection
-- ----------------------------------------------------------------------------
-- This is the "Launch & Expansion" question: given the observed growth
-- rate, which sites breach 100% utilization first — i.e. where does the
-- network need investment (site upgrade, re-zoning, or a new station)?
-- ============================================================================

-- 6.1  Week-over-week growth per station using LAG().
WITH weekly AS (
    SELECT
        r.station_id,
        strftime('%Y-%W', r.route_date) AS year_week,
        COUNT(p.package_id)             AS pkgs
    FROM routes r
    JOIN packages p ON p.route_id = r.route_id
    GROUP BY r.station_id, year_week
),
with_growth AS (
    SELECT
        station_id,
        year_week,
        pkgs,
        LAG(pkgs) OVER (PARTITION BY station_id ORDER BY year_week) AS prev_week,
        ROUND((pkgs * 1.0 / LAG(pkgs) OVER (PARTITION BY station_id ORDER BY year_week) - 1) * 100, 2)
            AS wow_growth_pct
    FROM weekly
)
SELECT
    s.station_code,
    ROUND(AVG(g.wow_growth_pct), 2) AS avg_wow_growth_pct
FROM with_growth g
JOIN delivery_stations s ON s.station_id = g.station_id
WHERE g.wow_growth_pct IS NOT NULL
GROUP BY s.station_code
ORDER BY avg_wow_growth_pct DESC;

-- 6.2  Runway to capacity breach.
--      Take each station's latest-week avg daily volume and its avg growth
--      rate, then project how many weeks until avg utilization crosses 100%.
--      (Compound-growth projection done with LOG math since SQLite has no
--      POWER-based loop; weeks = log(capacity/current) / log(1+g).)
WITH daily AS (
    SELECT r.station_id, r.route_date, COUNT(p.package_id) AS pkgs
    FROM routes r JOIN packages p ON p.route_id = r.route_id
    GROUP BY r.station_id, r.route_date
),
last_week AS (          -- avg daily volume over the final 6 operating days
    SELECT station_id, AVG(pkgs) AS current_daily
    FROM (
        SELECT
            station_id, pkgs,
            ROW_NUMBER() OVER (PARTITION BY station_id ORDER BY route_date DESC) AS rn
        FROM daily
    )
    WHERE rn <= 6
    GROUP BY station_id
),
growth AS (             -- reuse the WoW growth logic, averaged per station
    SELECT station_id, AVG(g) / 100.0 AS weekly_growth
    FROM (
        SELECT
            station_id,
            (pkgs * 1.0 / LAG(pkgs) OVER (PARTITION BY station_id
                                          ORDER BY year_week) - 1) * 100 AS g
        FROM (
            SELECT r.station_id,
                   strftime('%Y-%W', r.route_date) AS year_week,
                   COUNT(p.package_id) AS pkgs
            FROM routes r JOIN packages p ON p.route_id = r.route_id
            GROUP BY r.station_id, year_week
        )
    )
    WHERE g IS NOT NULL
    GROUP BY station_id
)
SELECT
    s.station_code,
    s.daily_capacity,
    ROUND(lw.current_daily, 0)                                   AS current_avg_daily,
    ROUND(lw.current_daily * 100.0 / s.daily_capacity, 1)        AS current_utilization_pct,
    ROUND(gr.weekly_growth * 100, 2)                             AS avg_weekly_growth_pct,
    CASE
        WHEN lw.current_daily >= s.daily_capacity THEN 0
        WHEN gr.weekly_growth <= 0                THEN NULL      -- no breach on trend
        ELSE CAST(
            ( ( LN(s.daily_capacity) - LN(lw.current_daily) )
              / LN(1 + gr.weekly_growth) ) AS INTEGER)
    END                                                          AS weeks_until_capacity
FROM delivery_stations s
JOIN last_week lw ON lw.station_id = s.station_id
JOIN growth    gr ON gr.station_id = s.station_id
ORDER BY weeks_until_capacity ASC;
