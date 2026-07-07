"""
Synthetic data generator for the Last-Mile Delivery Network Analytics project.

Creates deliveries.db (SQLite) with 5 related tables that mimic the kind of
operational data a last-mile logistics network produces:

    delivery_stations   - the physical sites (like AMZL delivery stations)
    drivers             - delivery associates assigned to a home station
    routes              - one route = one driver + one van + one day
    packages            - individual shipments assigned to routes
    delivery_attempts   - every attempt made on a package (success or failure)

The data is SYNTHETIC (randomly generated with realistic patterns baked in),
so there is no confidential information anywhere in this project.

Deliberate patterns hidden in the data (so the SQL analysis finds real signal):
    * Station BER-4 is over capacity -> more failed deliveries, longer routes
    * Failure reasons cluster: "customer_not_home" spikes on weekdays,
      "access_problem" is concentrated in dense urban zip zones
    * Newer drivers (< 90 days tenure) have lower first-attempt success
    * Package volume grows ~2% week over week (network growth trend)

Run:  python3 generate_data.py     -> writes deliveries.db in this folder
"""

import random
import sqlite3
from datetime import date, datetime, timedelta

random.seed(42)  # reproducible

DB_PATH = "deliveries.db"

# ---------------------------------------------------------------- stations
STATIONS = [
    # code, city, zone_type, daily_capacity (packages/day), opened
    ("BER-1", "Berlin",  "urban",    900, "2021-03-01"),
    ("BER-4", "Berlin",  "urban",    700, "2022-06-15"),  # the constrained site
    ("HAM-2", "Hamburg", "urban",    800, "2021-09-01"),
    ("MUC-1", "Munich",  "suburban", 850, "2020-11-20"),
    ("CGN-3", "Cologne", "suburban", 650, "2023-01-10"),
    ("LEJ-1", "Leipzig", "rural",    500, "2023-08-01"),
]

FAILURE_REASONS = ["customer_not_home", "access_problem", "address_issue",
                   "package_damaged", "out_of_time"]

FIRST = ["Anna", "Ben", "Clara", "David", "Elif", "Felix", "Gina", "Hakan",
         "Ines", "Jonas", "Katja", "Lars", "Mara", "Nico", "Omar", "Paula",
         "Quentin", "Rosa", "Stefan", "Tara", "Umut", "Vera", "Wim", "Yara", "Zoe"]
LAST = ["Schmidt", "Yilmaz", "Weber", "Kowalski", "Nguyen", "Fischer", "Peters",
        "Hoffmann", "Ali", "Novak", "Keller", "Braun", "Silva", "Wagner", "Krause"]


def main():
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.executescript(open("../sql/00_schema.sql").read())

    # ---- stations
    for i, (code, city, zone, cap, opened) in enumerate(STATIONS, start=1):
        cur.execute("INSERT INTO delivery_stations VALUES (?,?,?,?,?,?)",
                    (i, code, city, zone, cap, opened))

    # ---- drivers (40-70 per station)
    driver_id = 0
    drivers_by_station = {}
    for sid in range(1, len(STATIONS) + 1):
        drivers_by_station[sid] = []
        for _ in range(random.randint(40, 70)):
            driver_id += 1
            hired = date(2024, 1, 1) + timedelta(days=random.randint(0, 850))
            name = f"{random.choice(FIRST)} {random.choice(LAST)}"
            cur.execute("INSERT INTO drivers VALUES (?,?,?,?)",
                        (driver_id, name, sid, hired.isoformat()))
            drivers_by_station[sid].append((driver_id, hired))

    # ---- routes, packages, attempts over a 12-week window
    start = date(2026, 3, 30)          # Monday
    weeks = 12
    route_id = pkg_id = att_id = 0

    for week in range(weeks):
        growth = 1.02 ** week          # 2% WoW volume growth
        for dow in range(6):           # Mon-Sat operations
            d = start + timedelta(weeks=week, days=dow)
            for sid, (code, city, zone, cap, _) in enumerate(STATIONS, start=1):
                # demand grows; BER-4 demand runs hot vs its capacity
                base = cap * (0.78 if code != "BER-4" else 0.97)
                demand = int(base * growth * random.uniform(0.92, 1.08))
                over_capacity = demand > cap

                n_routes = max(1, demand // 180)   # ~180 stops per route
                for _ in range(n_routes):
                    route_id += 1
                    drv, hired = random.choice(drivers_by_station[sid])
                    tenure_days = (d - hired).days
                    rookie = 0 <= tenure_days < 90

                    stops = random.randint(140, 210)
                    # over-capacity sites cram more stops into routes
                    if over_capacity:
                        stops = int(stops * 1.15)
                    planned_min = int(stops * random.uniform(2.3, 2.7))
                    actual_min = int(planned_min *
                                     random.uniform(1.02, 1.30 if over_capacity else 1.18))
                    cur.execute("INSERT INTO routes VALUES (?,?,?,?,?,?,?)",
                                (route_id, sid, drv, d.isoformat(),
                                 stops, planned_min, actual_min))

                    # packages on this route (~1.15 pkgs per stop)
                    for _ in range(int(stops * 1.15)):
                        pkg_id += 1
                        promised = d
                        cur.execute(
                            "INSERT INTO packages VALUES (?,?,?,?,?)",
                            (pkg_id, route_id,
                             f"{random.choice(['10','12','13','20','22','80','81','50','51','04'])}"
                             f"{random.randint(100, 999)}",
                             random.choice(["standard", "standard", "standard", "prime_same_day"]),
                             promised.isoformat()))

                        # ---- first attempt
                        p_fail = 0.055
                        if over_capacity: p_fail += 0.035
                        if rookie:        p_fail += 0.030
                        if zone == "urban" and dow < 5: p_fail += 0.015
                        failed = random.random() < p_fail

                        att_id += 1
                        t1 = datetime(d.year, d.month, d.day,
                                      random.randint(9, 19), random.randint(0, 59))
                        if not failed:
                            cur.execute("INSERT INTO delivery_attempts VALUES (?,?,?,?,?,?)",
                                        (att_id, pkg_id, 1, t1.isoformat(),
                                         "delivered", None))
                        else:
                            if zone == "urban":
                                reason = random.choices(FAILURE_REASONS,
                                                        [45, 30, 10, 5, 10])[0]
                            else:
                                reason = random.choices(FAILURE_REASONS,
                                                        [50, 10, 20, 5, 15])[0]
                            cur.execute("INSERT INTO delivery_attempts VALUES (?,?,?,?,?,?)",
                                        (att_id, pkg_id, 1, t1.isoformat(),
                                         "failed", reason))
                            # ---- second attempt next day, 90% succeed
                            att_id += 1
                            d2 = d + timedelta(days=1)
                            t2 = datetime(d2.year, d2.month, d2.day,
                                          random.randint(9, 19), random.randint(0, 59))
                            ok2 = random.random() < 0.90
                            cur.execute("INSERT INTO delivery_attempts VALUES (?,?,?,?,?,?)",
                                        (att_id, pkg_id, 2, t2.isoformat(),
                                         "delivered" if ok2 else "failed",
                                         None if ok2 else random.choice(FAILURE_REASONS)))

    conn.commit()
    for t in ["delivery_stations", "drivers", "routes", "packages", "delivery_attempts"]:
        n = cur.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0]
        print(f"{t:20s} {n:>9,} rows")
    conn.close()


if __name__ == "__main__":
    main()
