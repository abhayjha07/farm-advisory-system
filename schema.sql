-- ============================================================
-- AI-Powered Irrigation Advisory System for Sugarcane Crop
-- Database: PostgreSQL
-- Includes: Advisory Accountability & Fault Diagnosis logic
-- ============================================================

DROP TABLE IF EXISTS fault_verdicts CASCADE;
DROP TABLE IF EXISTS yield_outcomes CASCADE;
DROP TABLE IF EXISTS irrigation_actual CASCADE;
DROP TABLE IF EXISTS advisories_given CASCADE;
DROP TABLE IF EXISTS sensor_health_log CASCADE;
DROP TABLE IF EXISTS sensors CASCADE;
DROP TABLE IF EXISTS rainfall_log CASCADE;
DROP TABLE IF EXISTS plots CASCADE;
DROP TABLE IF EXISTS farmers CASCADE;

-- ============================================================
-- CORE ENTITIES
-- ============================================================

CREATE TABLE farmers (
    farmer_id       SERIAL PRIMARY KEY,
    name            VARCHAR(100) NOT NULL,
    mobile_number   VARCHAR(15) UNIQUE NOT NULL,
    village         VARCHAR(100),
    taluk           VARCHAR(100),
    district        VARCHAR(100),
    registered_on   DATE DEFAULT CURRENT_DATE
);

CREATE TABLE plots (
    plot_id         SERIAL PRIMARY KEY,
    farmer_id       INTEGER NOT NULL REFERENCES farmers(farmer_id) ON DELETE CASCADE,
    plot_code       VARCHAR(20) NOT NULL,
    area_acres      NUMERIC(6,2) NOT NULL CHECK (area_acres > 0),
    crop_variety    VARCHAR(50) DEFAULT 'Co 86032',
    planting_date   DATE NOT NULL,
    soil_type       VARCHAR(50),
    latitude        NUMERIC(9,6),
    longitude       NUMERIC(9,6),
    UNIQUE (farmer_id, plot_code)
);

CREATE TABLE sensors (
    sensor_id       SERIAL PRIMARY KEY,
    plot_id         INTEGER NOT NULL REFERENCES plots(plot_id) ON DELETE CASCADE,
    sensor_type     VARCHAR(30) NOT NULL CHECK (sensor_type IN ('soil_moisture','temperature','humidity')),
    installed_on    DATE DEFAULT CURRENT_DATE
);

CREATE TABLE sensor_health_log (
    log_id          SERIAL PRIMARY KEY,
    sensor_id       INTEGER NOT NULL REFERENCES sensors(sensor_id) ON DELETE CASCADE,
    status          VARCHAR(20) NOT NULL CHECK (status IN ('online','offline','faulty')),
    logged_at       TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE rainfall_log (
    rainfall_id     SERIAL PRIMARY KEY,
    plot_id         INTEGER NOT NULL REFERENCES plots(plot_id) ON DELETE CASCADE,
    rainfall_mm     NUMERIC(6,2) NOT NULL,
    recorded_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ============================================================
-- ADVISORY + ACTUAL BEHAVIOUR
-- ============================================================

CREATE TABLE advisories_given (
    advisory_id         SERIAL PRIMARY KEY,
    plot_id             INTEGER NOT NULL REFERENCES plots(plot_id) ON DELETE CASCADE,
    recommended_date    DATE NOT NULL,
    recommended_hours   NUMERIC(4,1) NOT NULL,
    reason              TEXT,
    generated_at        TIMESTAMP NOT NULL DEFAULT NOW(),
    -- set by trigger if the sensor behind this advisory was unreliable
    reliability_flag    VARCHAR(20) NOT NULL DEFAULT 'reliable'
        CHECK (reliability_flag IN ('reliable','unreliable'))
);

CREATE TABLE irrigation_actual (
    actual_id       SERIAL PRIMARY KEY,
    plot_id         INTEGER NOT NULL REFERENCES plots(plot_id) ON DELETE CASCADE,
    advisory_id     INTEGER REFERENCES advisories_given(advisory_id),
    irrigated_on    DATE NOT NULL,
    hours_applied   NUMERIC(4,1) NOT NULL
);

CREATE TABLE yield_outcomes (
    outcome_id      SERIAL PRIMARY KEY,
    plot_id         INTEGER NOT NULL REFERENCES plots(plot_id) ON DELETE CASCADE,
    season_label    VARCHAR(20) NOT NULL,
    predicted_yield NUMERIC(6,2),
    actual_yield    NUMERIC(6,2),
    recorded_at     TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE fault_verdicts (
    verdict_id      SERIAL PRIMARY KEY,
    plot_id         INTEGER NOT NULL REFERENCES plots(plot_id) ON DELETE CASCADE,
    outcome_id      INTEGER REFERENCES yield_outcomes(outcome_id),
    verdict         VARCHAR(40) NOT NULL,
    explanation     TEXT,
    generated_at    TIMESTAMP NOT NULL DEFAULT NOW()
);

-- ============================================================
-- TRIGGER 1: auto-flag advisories as unreliable
-- if the sensor behind them was offline >48 hours
-- ============================================================

CREATE OR REPLACE FUNCTION flag_unreliable_advisories()
RETURNS TRIGGER AS $$
DECLARE
    offline_hours NUMERIC;
BEGIN
    -- only check when a sensor is logged as offline
    IF NEW.status = 'offline' THEN
        SELECT EXTRACT(EPOCH FROM (NOW() - MIN(logged_at))) / 3600
        INTO offline_hours
        FROM sensor_health_log
        WHERE sensor_id = NEW.sensor_id
          AND status = 'offline'
          AND logged_at >= NOW() - INTERVAL '7 days';

        IF offline_hours >= 48 THEN
            UPDATE advisories_given
            SET reliability_flag = 'unreliable'
            WHERE plot_id = (SELECT plot_id FROM sensors WHERE sensor_id = NEW.sensor_id)
              AND generated_at >= NOW() - INTERVAL '7 days';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_flag_unreliable_advisories
AFTER INSERT ON sensor_health_log
FOR EACH ROW
EXECUTE FUNCTION flag_unreliable_advisories();

-- ============================================================
-- STORED PROCEDURE: fault diagnosis verdict for a low-yield plot
-- Logic:
--   1. Sensor Malfunction   -> advisory was flagged unreliable
--   2. Farmer Non-Compliance -> actual irrigation hours differ
--                                from advisory by more than 30%
--   3. Unavoidable Weather   -> significant rainfall occurred
--                                near the advisory date
--   4. Bad Advisory          -> none of the above, advisory itself
--                                looks like the weak link
-- ============================================================

CREATE OR REPLACE FUNCTION diagnose_yield_fault(p_plot_id INTEGER, p_outcome_id INTEGER)
RETURNS VARCHAR AS $$
DECLARE
    v_verdict VARCHAR(40);
    v_unreliable_count INTEGER;
    v_noncompliance_count INTEGER;
    v_rainfall_mm NUMERIC;
BEGIN
    SELECT COUNT(*) INTO v_unreliable_count
    FROM advisories_given
    WHERE plot_id = p_plot_id AND reliability_flag = 'unreliable';

    SELECT COUNT(*) INTO v_noncompliance_count
    FROM advisories_given a
    JOIN irrigation_actual i ON i.advisory_id = a.advisory_id
    WHERE a.plot_id = p_plot_id
      AND ABS(i.hours_applied - a.recommended_hours) > (a.recommended_hours * 0.3);

    SELECT COALESCE(SUM(rainfall_mm), 0) INTO v_rainfall_mm
    FROM rainfall_log
    WHERE plot_id = p_plot_id;

    IF v_unreliable_count > 0 THEN
        v_verdict := 'Sensor Malfunction';
    ELSIF v_noncompliance_count > 0 THEN
        v_verdict := 'Farmer Non-Compliance';
    ELSIF v_rainfall_mm > 50 THEN
        v_verdict := 'Unavoidable Weather';
    ELSE
        v_verdict := 'Bad Advisory';
    END IF;

    INSERT INTO fault_verdicts (plot_id, outcome_id, verdict, explanation)
    VALUES (
        p_plot_id, p_outcome_id, v_verdict,
        FORMAT('unreliable_advisories=%s, noncompliant_events=%s, total_rainfall_mm=%s',
               v_unreliable_count, v_noncompliance_count, v_rainfall_mm)
    );

    RETURN v_verdict;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- USEFUL VIEW: plot-level dashboard summary
-- ============================================================

CREATE OR REPLACE VIEW plot_dashboard_summary AS
SELECT
    p.plot_id,
    p.plot_code,
    f.name AS farmer_name,
    f.village,
    p.crop_variety,
    p.area_acres,
    COUNT(DISTINCT a.advisory_id) AS advisories_count,
    COUNT(DISTINCT a.advisory_id) FILTER (WHERE a.reliability_flag = 'unreliable') AS unreliable_advisories,
    MAX(i.irrigated_on) AS last_irrigation_date,
    COALESCE(SUM(r.rainfall_mm), 0) AS total_rainfall_mm
FROM plots p
JOIN farmers f ON f.farmer_id = p.farmer_id
LEFT JOIN advisories_given a ON a.plot_id = p.plot_id
LEFT JOIN irrigation_actual i ON i.plot_id = p.plot_id
LEFT JOIN rainfall_log r ON r.plot_id = p.plot_id
GROUP BY p.plot_id, p.plot_code, f.name, f.village, p.crop_variety, p.area_acres;

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX idx_plots_farmer ON plots(farmer_id);
CREATE INDEX idx_advisories_plot ON advisories_given(plot_id);
CREATE INDEX idx_irrigation_plot ON irrigation_actual(plot_id);
CREATE INDEX idx_sensor_health_sensor ON sensor_health_log(sensor_id);

-- ============================================================
-- SAMPLE SEED DATA
-- ============================================================

INSERT INTO farmers (name, mobile_number, village, taluk, district) VALUES
('Ramesh Patil', '9876543210', 'Yalakatti', 'Hukkeri', 'Belagavi'),
('Suresh Kore', '9876543211', 'Sameerwadi', 'Mudhol', 'Bagalkot');

INSERT INTO plots (farmer_id, plot_code, area_acres, crop_variety, planting_date, soil_type, latitude, longitude) VALUES
(1, 'Plot-12', 5.6, 'Co 86032', '2023-11-12', 'Black cotton soil', 16.3, 74.8),
(2, 'Plot-04', 3.2, 'Co 86032', '2024-01-05', 'Red loamy soil', 16.5, 75.1);

INSERT INTO sensors (plot_id, sensor_type) VALUES
(1, 'soil_moisture'), (1, 'temperature'), (2, 'soil_moisture');

INSERT INTO sensor_health_log (sensor_id, status, logged_at) VALUES
(1, 'online', NOW() - INTERVAL '10 days'),
(1, 'offline', NOW() - INTERVAL '3 days'),
(1, 'offline', NOW() - INTERVAL '1 day');

INSERT INTO advisories_given (plot_id, recommended_date, recommended_hours, reason, generated_at) VALUES
(1, CURRENT_DATE - 2, 2.5, 'Soil moisture low, no rainfall expected', NOW() - INTERVAL '2 days'),
(2, CURRENT_DATE - 1, 3.0, 'Water stress medium', NOW() - INTERVAL '1 day');

INSERT INTO irrigation_actual (plot_id, advisory_id, irrigated_on, hours_applied) VALUES
(1, 1, CURRENT_DATE - 2, 1.0),
(2, 2, CURRENT_DATE - 1, 3.0);

INSERT INTO rainfall_log (plot_id, rainfall_mm) VALUES
(2, 12.5);

INSERT INTO yield_outcomes (plot_id, season_label, predicted_yield, actual_yield) VALUES
(1, '2024-Kharif', 102.6, 78.4),
(2, '2024-Kharif', 98.0, 95.2);
