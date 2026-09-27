# Advisory Accountability & Fault Diagnosis System
### AI-Powered Irrigation Advisory — DBMS Mini Project

Three parts: PostgreSQL schema (`db/`), Express API backend (`backend/`), and a plain HTML/CSS/JS dashboard (`frontend/`).

## 1. Set up the database

Install PostgreSQL if you don't have it, then:

```bash
createdb farm_advisory
psql -d farm_advisory -f db/schema.sql
```

This creates all tables, the trigger (`trg_flag_unreliable_advisories`), the stored
procedure (`diagnose_yield_fault`), a summary view, and loads sample data so the
dashboard isn't empty on first run.

## 2. Set up the backend

```bash
cd backend
npm install
cp .env.example .env
```

Edit `.env` and put in your actual PostgreSQL password. Then:

```bash
npm start
```

Server runs on `http://localhost:4000`. Check it's alive at
`http://localhost:4000/api/health`.

## 3. Open the frontend

Just open `frontend/index.html` directly in a browser (double-click it, or
right-click → Open with browser). It talks to the backend at
`localhost:4000` automatically — no build step needed.

## What to demo in your viva

1. **Show the schema** — point out foreign keys, the `CHECK` constraints, and the view.
2. **Trigger demo**: insert a row into `sensor_health_log` with `status = 'offline'`
   twice, a few days apart, for the same sensor — then show `advisories_given`
   for that plot flip to `unreliable`.
   ```sql
   INSERT INTO sensor_health_log (sensor_id, status, logged_at)
   VALUES (1, 'offline', NOW());
   SELECT * FROM advisories_given WHERE plot_id = 1;
   ```
3. **Stored procedure demo**: click "Run Fault Diagnosis" on the dashboard for
   Plot-12 with outcome ID 1 — it will return `Sensor Malfunction` because that
   plot's sensor was flagged offline in the seed data.
4. **Explain the verdict logic** — sensor issues are checked first, then farmer
   compliance, then rainfall, and only then "Bad Advisory" as the leftover case.

## Known limitations (say this upfront if asked)

- This runs locally — it is not a hosted production system, which is standard
  for a mini project.
- The fault-diagnosis thresholds (30% deviation, 50mm rainfall, 48hr offline)
  are reasonable assumptions, not calibrated against real agricultural data —
  be ready to justify them as design choices, not measured constants.
