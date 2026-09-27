const express = require('express');
const cors = require('cors');
const pool = require('./db');
require('dotenv').config();

const app = express();
app.use(cors());
app.use(express.json());

// ---------- Farmers ----------
app.get('/api/farmers', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM farmers ORDER BY farmer_id');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ---------- Plots (dashboard summary view) ----------
app.get('/api/plots', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM plot_dashboard_summary ORDER BY plot_id');
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/plots/:id', async (req, res) => {
  try {
    const result = await pool.query('SELECT * FROM plots WHERE plot_id = $1', [req.params.id]);
    if (result.rows.length === 0) return res.status(404).json({ error: 'Plot not found' });
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ---------- Advisories ----------
app.get('/api/plots/:id/advisories', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM advisories_given WHERE plot_id = $1 ORDER BY generated_at DESC',
      [req.params.id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/advisories', async (req, res) => {
  const { plot_id, recommended_date, recommended_hours, reason } = req.body;
  try {
    const result = await pool.query(
      `INSERT INTO advisories_given (plot_id, recommended_date, recommended_hours, reason)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [plot_id, recommended_date, recommended_hours, reason]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ---------- Irrigation actual events ----------
app.get('/api/plots/:id/irrigation', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM irrigation_actual WHERE plot_id = $1 ORDER BY irrigated_on DESC',
      [req.params.id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/irrigation', async (req, res) => {
  const { plot_id, advisory_id, irrigated_on, hours_applied } = req.body;
  try {
    const result = await pool.query(
      `INSERT INTO irrigation_actual (plot_id, advisory_id, irrigated_on, hours_applied)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [plot_id, advisory_id, irrigated_on, hours_applied]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ---------- Sensor health (triggers trigger here) ----------
app.post('/api/sensors/:id/health', async (req, res) => {
  const { status } = req.body;
  try {
    const result = await pool.query(
      `INSERT INTO sensor_health_log (sensor_id, status) VALUES ($1, $2) RETURNING *`,
      [req.params.id, status]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/sensors/:plotId', async (req, res) => {
  try {
    const result = await pool.query(
      `SELECT s.*, h.status, h.logged_at
       FROM sensors s
       LEFT JOIN LATERAL (
         SELECT status, logged_at FROM sensor_health_log
         WHERE sensor_id = s.sensor_id ORDER BY logged_at DESC LIMIT 1
       ) h ON true
       WHERE s.plot_id = $1`,
      [req.params.plotId]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ---------- Yield outcomes ----------
app.post('/api/yield', async (req, res) => {
  const { plot_id, season_label, predicted_yield, actual_yield } = req.body;
  try {
    const result = await pool.query(
      `INSERT INTO yield_outcomes (plot_id, season_label, predicted_yield, actual_yield)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [plot_id, season_label, predicted_yield, actual_yield]
    );
    res.status(201).json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ---------- Yield outcomes (for chart) ----------
app.get('/api/plots/:id/yield', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM yield_outcomes WHERE plot_id = $1 ORDER BY recorded_at DESC LIMIT 1',
      [req.params.id]
    );
    res.json(result.rows[0] || null);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ---------- Fault diagnosis (calls the stored procedure) ----------
app.post('/api/diagnose', async (req, res) => {
  const { plot_id, outcome_id } = req.body;
  try {
    const result = await pool.query(
      'SELECT diagnose_yield_fault($1, $2) AS verdict',
      [plot_id, outcome_id]
    );
    res.json(result.rows[0]);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/plots/:id/verdicts', async (req, res) => {
  try {
    const result = await pool.query(
      'SELECT * FROM fault_verdicts WHERE plot_id = $1 ORDER BY generated_at DESC',
      [req.params.id]
    );
    res.json(result.rows);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.get('/api/health', (req, res) => res.json({ status: 'ok' }));

const PORT = process.env.PORT || 4000;
app.listen(PORT, () => console.log(`Server running on port ${PORT}`));
