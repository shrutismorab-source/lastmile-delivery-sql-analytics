-- ============================================================================
-- 00_schema.sql — Database design for a last-mile delivery network
-- ============================================================================
-- Design notes:
--   * 5 tables in a classic star-ish shape: stations and drivers are
--     dimension tables; routes, packages and delivery_attempts are facts.
--   * One route  = one driver + one day + one station.
--   * One package belongs to exactly one route (FK route_id).
--   * A package can have MULTIPLE delivery attempts (1st attempt fails ->
--     2nd attempt next day). This 1-to-many is what makes the analysis
--     interesting: "first-attempt success rate" is a core last-mile KPI.
-- ============================================================================

DROP TABLE IF EXISTS delivery_attempts;
DROP TABLE IF EXISTS packages;
DROP TABLE IF EXISTS routes;
DROP TABLE IF EXISTS drivers;
DROP TABLE IF EXISTS delivery_stations;

CREATE TABLE delivery_stations (
    station_id      INTEGER PRIMARY KEY,
    station_code    TEXT NOT NULL UNIQUE,   -- e.g. 'BER-4'
    city            TEXT NOT NULL,
    zone_type       TEXT NOT NULL,          -- urban / suburban / rural
    daily_capacity  INTEGER NOT NULL,       -- max packages/day the site can process
    opened_date     TEXT NOT NULL           -- ISO date
);

CREATE TABLE drivers (
    driver_id        INTEGER PRIMARY KEY,
    driver_name      TEXT NOT NULL,
    home_station_id  INTEGER NOT NULL REFERENCES delivery_stations(station_id),
    hire_date        TEXT NOT NULL
);

CREATE TABLE routes (
    route_id             INTEGER PRIMARY KEY,
    station_id           INTEGER NOT NULL REFERENCES delivery_stations(station_id),
    driver_id            INTEGER NOT NULL REFERENCES drivers(driver_id),
    route_date           TEXT NOT NULL,     -- ISO date
    planned_stops        INTEGER NOT NULL,
    planned_duration_min INTEGER NOT NULL,
    actual_duration_min  INTEGER NOT NULL
);

CREATE TABLE packages (
    package_id    INTEGER PRIMARY KEY,
    route_id      INTEGER NOT NULL REFERENCES routes(route_id),
    dest_zip      TEXT NOT NULL,
    service_type  TEXT NOT NULL,            -- standard / prime_same_day
    promised_date TEXT NOT NULL
);

CREATE TABLE delivery_attempts (
    attempt_id     INTEGER PRIMARY KEY,
    package_id     INTEGER NOT NULL REFERENCES packages(package_id),
    attempt_number INTEGER NOT NULL,        -- 1 or 2
    attempt_time   TEXT NOT NULL,           -- ISO datetime
    status         TEXT NOT NULL,           -- delivered / failed
    failure_reason TEXT                     -- NULL when delivered
);

-- Indexes on the join keys we query constantly
CREATE INDEX idx_routes_station   ON routes(station_id, route_date);
CREATE INDEX idx_packages_route   ON packages(route_id);
CREATE INDEX idx_attempts_package ON delivery_attempts(package_id);
