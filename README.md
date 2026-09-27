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

