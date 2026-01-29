# ELOG Copilot Database Schema

## Experiment

| Column | Notes |
|--------|-------|
| experiment_id (PK) | e.g., `mfxc00117`, `mfx100895324` |
| name | |
| instrument | |
| start_time, end_time | |
| pi, pi_email | Principal investigator |
| leader_account | |
| description | May contain experimental config details (check alongside Questionnaire) |
| slack_channels | |
| analysis_queues | |
| urawi_proposal | |

## Questionnaire

| Column | Notes |
|--------|-------|
| questionnaire_id (PK) | |
| experiment_id (FK) | |
| proposal | |
| category | See Questionnaire Categories below |
| field_id, field_name, field_value | |
| modified_time, modified_uid | |
| created_time | |

## Workflow

| Column | Notes |
|--------|-------|
| workflow_id (PK) | |
| experiment_id (FK) | |
| mongo_id | |
| name | Workflow name |
| executable | Script or program executed |
| trigger | |
| location | Where analysis code is stored |
| parameters | Configuration used |
| run_param_name, run_param_value | |
| run_as_user | |

## Run

| Column | Notes |
|--------|-------|
| run_id (PK) | |
| run_number | Experiment run number (1, 2, 3... within an experiment) |
| experiment_id (FK) | |
| start_time, end_time | |

## RunProductionData

| Column | Notes |
|--------|-------|
| run_data_id (PK) | |
| run_id (FK) | |
| n_events | |
| n_damaged, n_dropped | |
| prod_start, prod_end | |
| number_of_files | |
| total_size_bytes | |

## Detector

| Column | Notes |
|--------|-------|
| detector_id (PK) | |
| detector_name | |
| description | |

## RunDetector

| Column | Notes |
|--------|-------|
| run_detector_id (PK) | |
| run_id (FK) | |
| detector_id (FK) | |
| status | |

## Logbook

| Column | Notes |
|--------|-------|
| log_id (PK) | |
| experiment_id (FK) | |
| run_id (FK) | |
| timestamp | |
| content | |
| tags | |
| author | |

## RunCompleteData (VIEW)

Joins Run and RunProductionData to provide complete run information. Not visible when listing tables, but exists and should be queried first.

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

SQLite limitations with non-standard date formats:
- Non-standard formats (like "MMM/DD/YYYY") are NOT automatically recognized
- `DATETIME()` failures silently return NULL
- String-based sorting of non-ISO dates produces alphabetical, not chronological ordering

Recommendations:
1. Inspect actual date formats first (sample a few rows)
2. Convert non-standard formats to ISO (YYYY-MM-DD) for comparison
3. Use simple string filters as alternatives when format is consistent

## Large Result Sets

1. Start with overviews - COUNT, summary statistics, date ranges before detailed extractions
2. Use focused filters - WHERE clauses, LIMIT, sampling
3. Break into sub-queries rather than single massive retrievals
4. Prioritize recent, representative, or specifically requested data first
5. Iterate from high-level patterns to specific areas of interest
