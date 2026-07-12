-- 1. Create a clean dedicated space for our warehouse tables
CREATE SCHEMA IF NOT EXISTS core_dw;

-- 2. Build the Clean Patient Table
DROP TABLE IF EXISTS core_dw.dim_patients CASCADE;
CREATE TABLE core_dw.dim_patients (
    patient_id VARCHAR(50) PRIMARY KEY,
    birth_date DATE NOT NULL,
    death_date DATE,
    gender CHAR(1),
    race VARCHAR(30),
    state VARCHAR(30)
);

-- 3. Build the Clean Encounter Table
DROP TABLE IF EXISTS core_dw.fact_encounters CASCADE;
CREATE TABLE core_dw.fact_encounters (
    encounter_id VARCHAR(50) PRIMARY KEY,
    patient_id VARCHAR(50),
    encounter_class VARCHAR(30),
    start_time TIMESTAMP NOT NULL,
    stop_time TIMESTAMP,
    base_encounter_cost NUMERIC(12, 2),
    total_claim_cost NUMERIC(12, 2),
    payer_coverage NUMERIC(12, 2)
);



-- Insert cleaned data into the core warehouse table
INSERT INTO core_dw.dim_patients (patient_id, birth_date, death_date, gender, race, state)
SELECT 
    id AS patient_id,
    CAST(birthdate AS DATE) AS birth_date,
    CAST(NULLIF(deathdate, '') AS DATE) AS death_date,
    gender,
    race,
    state
FROM public.stg_patients;


-- Insert cleaned data into the core warehouse encounter table
INSERT INTO core_dw.fact_encounters (
    encounter_id, 
    patient_id, 
    encounter_class, 
    start_time, 
    stop_time, 
    base_encounter_cost, 
    total_claim_cost, 
    payer_coverage
)
SELECT 
    id AS encounter_id,
    patient AS patient_id,
    encounterclass AS encounter_class,
    CAST(start AS TIMESTAMP) AS start_time,
    CAST(stop AS TIMESTAMP) AS stop_time,
    CAST(base_encounter_cost AS NUMERIC(12,2)) AS base_encounter_cost,
    CAST(total_claim_cost AS NUMERIC(12,2)) AS total_claim_cost,
    CAST(payer_coverage AS NUMERIC(12,2)) AS payer_coverage
FROM public.stg_encounters;


SELECT COUNT(*) FROM core_dw.fact_encounters;    -- should be 321,518



-- Chronological Logic Breaks (The Time-Travel Anomaly)

CREATE SCHEMA IF NOT EXISTS data_qa;

-- Drop table if it exists to allow re-runs
DROP TABLE IF EXISTS data_qa.audit_chronological_errors;

-- Build the audit log table
CREATE TABLE data_qa.audit_chronological_errors AS
SELECT 
    encounter_id,
    patient_id,
    encounter_class,
    start_time,
    stop_time,
    -- Case statement to tag the specific type of temporal violation
    CASE 
        WHEN stop_time < start_time THEN 'Discharge Before Admission'
        WHEN stop_time IS NULL AND encounter_class != 'ambulatory' THEN 'Missing Discharge Date on Acute Care'
        ELSE 'Valid Timeline'
    END AS anomaly_type
FROM core_dw.fact_encounters
WHERE stop_time < start_time OR (stop_time IS NULL AND encounter_class != 'ambulatory');


SELECT anomaly_type, COUNT(*) 
FROM data_qa.audit_chronological_errors 
GROUP BY anomaly_type;    -- Should be none




-- Detecting Duplicate Procedure Billing

-- Drop table if it exists to allow clean re-runs
DROP TABLE IF EXISTS data_qa.audit_duplicate_procedures;

-- Build the duplicate audit log table
CREATE TABLE data_qa.audit_duplicate_procedures AS
WITH ranked_procedures AS (
    SELECT 
        patient AS patient_id,
        encounter AS encounter_id,
        code AS procedure_code,
        description AS procedure_description,
        CAST(date AS TIMESTAMP) AS procedure_time,
        -- Grouping data blocks using PARTITION BY to spot recurring codes
        ROW_NUMBER() OVER (
            PARTITION BY patient, encounter, code, date 
            ORDER BY date
        ) as billing_instance_count
    FROM public.stg_procedures
)
SELECT * FROM ranked_procedures
WHERE billing_instance_count > 1; -- Show me only rows that repeated


SELECT COUNT(*) FROM data_qa.audit_duplicate_procedures; -- Should be 0





-- Identifying Orphaned Procedures i.e Treatment done that never happened (no visit records)


-- Drop table if it exists to allow clean re-runs
DROP TABLE IF EXISTS data_qa.audit_orphaned_procedures;

-- Build the orphaned procedure audit log table
CREATE TABLE data_qa.audit_orphaned_procedures AS
SELECT 
    p.patient AS patient_id,
    p.encounter AS procedure_encounter_id,
    p.code AS procedure_code,
    p.description AS procedure_description,
    e.encounter_id AS matched_warehouse_encounter_id
FROM public.stg_procedures p
LEFT JOIN core_dw.fact_encounters e 
    ON p.encounter = e.encounter_id
WHERE e.encounter_id IS NULL; -- This filter isolates the orphans!


SELECT COUNT(*) FROM data_qa.audit_orphaned_procedures; -- Should be 0




-- BUSINESS ANALYTICS & EXECUTIVE REPORTING



--Metric 1: The 30-Day Hospital Readmission Rate (Quality of Care)


-- Create a reusable reporting view for patient readmissions
CREATE OR REPLACE VIEW core_dw.view_30day_readmissions AS
WITH patient_timeline AS (
    SELECT 
        patient_id,
        encounter_id,
        encounter_class,
        start_time AS admission_date,
        stop_time AS discharge_date,
        -- Look ahead to find the next chronological admission date for this exact patient
        LEAD(start_time) OVER (
            PARTITION BY patient_id 
            ORDER BY start_time
        ) AS next_admission_date
    FROM core_dw.fact_encounters
    WHERE encounter_class = 'inpatient' -- We only care about serious hospital stays
)
SELECT 
    patient_id,
    encounter_id,
    admission_date,
    discharge_date,
    next_admission_date,
    -- Calculate how many days passed before they came back
    EXTRACT(DAY FROM (next_admission_date - discharge_date)) AS days_to_readmission,
    -- Label it: 1 if they returned within 30 days, 0 if they stayed healthy
    CASE 
        WHEN EXTRACT(DAY FROM (next_admission_date - discharge_date)) <= 30 THEN 1 
        ELSE 0 
    END AS is_30day_readmission
FROM patient_timeline;

-- Summary query to see the final executive metrics
SELECT 
    COUNT(*) as total_hospital_discharges,
    SUM(is_30day_readmission) as total_30day_readmissions,
    ROUND((SUM(is_30day_readmission)::NUMERIC / COUNT(*)::NUMERIC) * 100, 2) as readmission_rate_percentage
FROM core_dw.view_30day_readmissions;


-- Metric 2: Financial Leakage & Coverage Analysis (Money Metrics)

-- Executive Financial Performance Summary by Department
SELECT 
    encounter_class AS department,
    COUNT(*) as total_visits,
    ROUND(SUM(total_claim_cost), 2) as gross_revenue_billed,
    ROUND(SUM(payer_coverage), 2) as insurance_payouts,
    -- Calculate outstanding balance (Leakage)
    ROUND(SUM(total_claim_cost - payer_coverage), 2) as patient_outstanding_balance,
    -- Calculate what percentage of our bills are covered by insurance
    ROUND((SUM(payer_coverage) / NULLIF(SUM(total_claim_cost), 0)) * 100, 2) as insurance_coverage_ratio_pct
FROM core_dw.fact_encounters
GROUP BY encounter_class
ORDER BY gross_revenue_billed DESC;
