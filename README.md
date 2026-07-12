# Healthcare Data Engineering Pipeline

An enterprise-grade, end-to-end Extract-Load-Transform (ELT) data pipeline designed to ingest, process, and analyze clinical and financial electronic health record (EHR) data. 

Built using Python for automated streaming ingestion and PostgreSQL for relational modeling, this repository implements a strongly-typed warehouse architecture, automated Data Quality (QA) engines, and executive-level analytics views.

---

## 🏗️ Architecture Overview

The system operates under a three-tier relational schema designed to isolate raw ingestion from production reporting:

1. **Staging Layer (`public.stg_*`)**: A flexible landing zone for raw transactional data.
2. **Core Warehouse (`core_dw.*`)**: A production-level schema with strict data typing, structural constraints, and primary keys.
3. **Data Quality Room (`data_qa.*`)**: An isolated audit trail monitoring for logical errors, duplicate billing, and synchronization gaps.

---

## 📈 Executive Analytics Summary

By migrating over 430,000 corporate clinical transactions, the pipeline surfaced high-value metrics impacting hospital profitability and compliance.

### 1. Clinical Quality: 30-Day Readmission
* **Total Tracked Discharges:** 9,584
* **Identified Critical Readmissions:** 2,524
* **Systemic Readmission Rate:** 26.34%

### 2. Financial Performance Matrix

| Department | Total Visits | Gross Billed | Insurer Payouts | Leakage (Outstanding) | Coverage Ratio |
| :--- | :---: | :---: | :---: | :---: | :---: |
| **Wellness** | 156,219 | $20.1M | $12.5M | $7.6M | 62.30% |
| **Ambulatory** | 86,069 | $11.1M | $5.0M | $6.0M | 45.33% |
| **Outpatient** | 58,367 | $7.5M | $2.0M | $5.4M | 27.80% |
| **Inpatient** | 9,584 | $1.09M | $0.38M | $0.71M | 34.76% |
| **Emergency** | 7,233 | $0.93M | $0.38M | $0.54M | 41.15% |
| **Urgent Care** | 4,056 | $0.52M | $0.00 | $0.52M | 0.00% |

#### Key Insights
* **Urgent Care Deficit:** The Urgent Care track shows a 0.00% insurance coverage metric, identifying a major billing or transmission fault.
* **Outpatient Write-offs:** Outpatient processing generates $7.5M in bills but captures only 27.80% in reimbursement.

---

## 🛠️ Technical Implementation

### Ingestion Pipeline (`01_stage_ingestion.py`)
A Python engine managing infrastructure connectivity, header normalization, and streaming ingestion. It utilizes strict `dtype=str` typing to prevent data truncation of standardized medical identifiers.

### Core Transformations & Analytics (`02_core_transform_and_analytics.sql`)
SQL-based server-side execution of data type conversions and auditing.
* **Advanced Windowing:** Utilizes `LEAD()` functions for chronological timeline tracking to avoid recursive self-joins.
* **QA Validation:** Implements `ROW_NUMBER()` partitioning to isolate duplicate, overlapping, or orphaned billing records before they hit the reporting layer.

---
