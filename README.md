# Advisory Accountability & Fault Diagnosis System
### AI-Powered Irrigation Advisory — DBMS Mini Project

This project contains a PostgreSQL database schema, an Express API backend, and a web-based dashboard all in a single repository.

## 1. Database Setup

Ensure PostgreSQL is installed on your system. Open your terminal in the project folder and run:

```bash
createdb farm_advisory
psql -d farm_advisory -f schema.sql
This creates the required tables, triggers, stored procedures, and loads the initial seed data (10 plots) for the dashboard.

2. Backend Setup
Make sure your .env file is created in the same folder and contains your PostgreSQL database credentials. Install the required Node packages and start the server:

Bash
npm install
npm start
The Express API will run on http://localhost:4000. You can verify the connection at http://localhost:4000/api/health.

3. Frontend Dashboard
Open the index.html file directly in any web browser (Chrome, Edge, Safari). It will automatically connect to the local backend API and render the live data, interactive map, and charts. No build steps or frontend servers are required.
