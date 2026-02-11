# ELOG Copilot Database Schema (PostgreSQL)

All tables use Row-Level Security (RLS) unless noted. Results are automatically filtered by the current user's experiment permissions.

## experiments

RLS: yes

| Column | Type | Notes |
|--------|------|-------|
| experiment_id (PK) | TEXT | e.g., `mfxc00117`, `mfx100895324` |
| name | TEXT | |
| instrument | TEXT | |
| start_time, end_time | TIMESTAMPTZ | |
| pi, pi_email | TEXT | Principal investigator |
| leader_account | TEXT | |
| description | TEXT | May contain experimental config details (check alongside questionnaire) |
| slack_channels | TEXT | |
| analysis_queues | TEXT | |
| urawi_proposal | TEXT | |

## questionnaire

RLS: yes

| Column | Type | Notes |
|--------|------|-------|
| questionnaire_id (PK) | SERIAL | |
| experiment_id (FK) | TEXT | |
| proposal | TEXT | |
| category | TEXT | See Questionnaire Categories below |
| field_id, field_name, field_value | TEXT | |
| modified_time | TIMESTAMPTZ | |
| modified_uid | TEXT | |
| created_time | TIMESTAMPTZ | |

## workflows

RLS: yes

| Column | Type | Notes |
|--------|------|-------|
| workflow_id (PK) | SERIAL | |
| experiment_id (FK) | TEXT | |
| mongo_id | TEXT | |
| name | TEXT | Workflow name |
| executable | TEXT | Script or program executed |
| "trigger" | TEXT | **Reserved word** — must be double-quoted in queries |
| location | TEXT | Where analysis code is stored |
| parameters | TEXT | Configuration used |
| run_param_name, run_param_value | TEXT | |
| run_as_user | TEXT | |

## runs

RLS: yes

| Column | Type | Notes |
|--------|------|-------|
| run_id (PK) | SERIAL | |
| run_number | INTEGER | Experiment run number (1, 2, 3... within an experiment) |
| experiment_id (FK) | TEXT | |
| start_time, end_time | TIMESTAMPTZ | |

## run_production_data

RLS: yes

| Column | Type | Notes |
|--------|------|-------|
| run_data_id (PK) | SERIAL | |
| run_id (FK) | INTEGER | |
| n_events | BIGINT | |
| n_damaged, n_dropped | BIGINT | |
| prod_start, prod_end | TIMESTAMPTZ | |
| number_of_files | INTEGER | |
| total_size_bytes | BIGINT | |

## detectors

RLS: **no** (shared catalog, visible to all users)

| Column | Type | Notes |
|--------|------|-------|
| detector_id (PK) | SERIAL | |
| detector_name | TEXT | |
| description | TEXT | |

## run_detectors

RLS: yes

| Column | Type | Notes |
|--------|------|-------|
| run_detector_id (PK) | SERIAL | |
| run_id (FK) | INTEGER | |
| detector_id (FK) | INTEGER | |
| status | TEXT | |

## logbook

RLS: yes

| Column | Type | Notes |
|--------|------|-------|
| log_id (PK) | SERIAL | |
| experiment_id (FK) | TEXT | |
| run_id (FK) | INTEGER | |
| timestamp | TIMESTAMPTZ | |
| content | TEXT | |
| tags | TEXT | |
| author | TEXT | |

## run_complete_data (VIEW)

Joins `runs` and `run_production_data` to provide complete run information. Query this view first before querying `runs` or `run_production_data` directly.

RLS: inherited from `runs` and `run_production_data`

## user_experiment_access

RLS: **no** (admin-managed, not directly queried by users)

| Column | Type | Notes |
|--------|------|-------|
| id (PK) | SERIAL | |
| username | TEXT | Maps to PostgreSQL role (current_user) |
| experiment_id (FK) | TEXT | |
| access_level | TEXT | 'read', 'write', or 'admin' |
| granted_at | TIMESTAMPTZ | |
| granted_by | TEXT | |

## Questionnaire Categories

### Experimental Configuration
- `analysis` - Data analysis tools, monitoring software (AMI, psana-python), analysis frameworks
- `detector` - SLAC detector specifications (ePix10k, ePix100, orientations, environments, quantities)
- `xraytech` - X-ray techniques (XAS=X-ray Absorption, XES=X-ray Emission, WAXS, spectroscopy settings, energy resolution)
- `xray` - X-ray beam parameters (energies, pulse duration, repetition rate, bandwidth, focal spot sizes)
- `laser` - Laser specifications (wavelengths, pulse energy/duration, timing synchronization, delay ranges, beam geometries)

### Sample & Control
- `sample` - Sample delivery (jet types, reservoir volumes, nozzle sizes, temperature requirements, sample quantities)
- `contr` - Control systems (cameras, motors, temperature controllers, triggering systems)

### Planning & Compliance
- `area` - Laboratory preparation areas, contact information, shipping logistics, shift scheduling
- `data` - Data management plans, analysis milestones, collaboration agreements
- `export` - Export control compliance (military applications, nuclear technology restrictions)

### Notes
- Empty questionnaires are normal for older experiments or incomplete submissions
- Multiple experiments may share the same proposal number
- Categories use abbreviated names: `xraytech` = X-ray techniques, `contr` = control systems
- Field modifications are tracked with timestamps and user information

## Date Handling

PostgreSQL uses native `TIMESTAMPTZ` for all timestamp columns. Dates can be filtered directly:

```sql
WHERE start_time >= '2025-01-01'
WHERE start_time BETWEEN '2025-06-01' AND '2025-06-30'
WHERE start_time >= now() - interval '7 days'
```

No format conversion workarounds needed (unlike SQLite).

## Large Result Sets

1. Start with overviews - COUNT, summary statistics, date ranges before detailed extractions
2. Use focused filters - WHERE clauses, LIMIT, sampling
3. Break into sub-queries rather than single massive retrievals
4. Prioritize recent, representative, or specifically requested data first
5. Iterate from high-level patterns to specific areas of interest
