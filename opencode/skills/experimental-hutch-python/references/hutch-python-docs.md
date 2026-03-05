# Hutch Python Comprehensive Documentation

This document provides a complete reference for hutch-python, the standardized framework for managing LCLS beamline control environments.

## Table of Contents

1. [Getting Started](#1-getting-started)
2. [Configuration (conf.yml)](#2-configuration-confyml)
3. [Startup Sequence](#3-startup-sequence)
4. [Navigation & Namespaces](#4-navigation--namespaces)
5. [Device Loading](#5-device-loading)
6. [Lightpath / BeamPath](#6-lightpath--beampath)
7. [DAQ (Data Acquisition)](#7-daq-data-acquisition)
8. [Bluesky Scanning](#8-bluesky-scanning)
9. [Presets System](#9-presets-system)
10. [Object Configuration](#10-object-configuration)
11. [Experiment Files](#11-experiment-files)
12. [Debugging & Logging](#12-debugging--logging)
13. [Bug Reporting](#13-bug-reporting)
14. [Utilities](#14-utilities)
15. [Setting Up a New Hutch](#15-setting-up-a-new-hutch)
16. [Jupyter Notebook Setup](#16-jupyter-notebook-setup)
17. [External Dependencies](#17-external-dependencies)

---

## 1. Getting Started

### Starting a Session

Hutch directories are located at `/reg/g/pcds/pyps/apps/hutch-python/xxx`. Each hutch provides two main scripts:

| Script | Purpose |
|--------|---------|
| `xxxpython` | Launch interactive session or run scripts |
| `xxxenv` | Set up environment without launching session |

### Command Line Options

```bash
xxxpython                    # Standard launch
xxxpython --exp <expname>    # Override active experiment
xxxpython --sim              # Start with simulated DAQ
xxxpython --debug            # Enable debug mode with increased logging
xxxpython --sim --debug      # Combine options
```

### Environment Setup

**Central Install (Managed):**
```bash
# Activate environment
source /reg/g/pcds/pyps/conda/py36env.sh

# Specify version
source /reg/g/pcds/pyps/conda/py36env.sh $ENVNAME

# View available environments
conda env list
```

**Personal Development Install:**
```bash
conda install hutch-python -c pcds-tag -c defaults -c conda-forge
```

---

## 2. Configuration (conf.yml)

The `conf.yml` file is the central configuration for each hutch.

### Configuration Keys

| Key | Type | Description |
|-----|------|-------------|
| `hutch` | string | Hutch name (e.g., "xpp") |
| `db` | string | Path to happi device database |
| `load` | string/list | Modules to import (e.g., "xpp.beamline") |
| `load_level` | string | Device loading depth |
| `experiment` | dict | Override experiment (proposal/run) |
| `obj_config` | string | Path to object configuration file |
| `daq_type` | string | DAQ type: 'lcls1', 'lcls1-sim', 'lcls2', 'nodaq' |
| `daq_host` | string | DAQ collection host (required for lcls2) |
| `daq_platform` | dict | Platform configuration with "default" key |
| `exclude_devices` | list | Devices to exclude from loading |
| `additional_devices` | dict | Additional devices from other beamlines |

### Loading Levels

| Level | Description |
|-------|-------------|
| `UPSTREAM` | Hutch devices + devices upstream |
| `STANDARD` | UPSTREAM + devices sharing beamline field (default) |
| `ALL` | All devices in database |

### Example Configuration

```yaml
hutch: xpp
db: /reg/g/pcds/pyps/apps/hutch-python/device_config/db.json

load:
  - xpp.beamline
  - xpp.my_module

load_level: STANDARD

experiment:
  proposal: ls25
  run: 16

obj_config: /cds/group/pcds/pyps/apps/hutch-python/xxx/tabs.yml

exclude_devices:
  - crix_cryo_y
  - at2k2_calc

additional_devices:
  tmo_sqr1_search:
    beamline: TMO
    device_class: pcdsdevices.sqr1.SQR1
  las_search:
    name: LAS
  crix_search:
    name: crix_*
```

---

## 3. Startup Sequence

When `xxxpython` is called, the following initialization occurs:

### 1. Common Startup
- Set up log files, debug state, sim state
- Read `cfg.yml`
- Display `xxxpython` banner
- Create `RunEngine` as `RE`
- Create `plans` object (aliased to `p`)
- Create `daq` object
- Create `scan_pvs` object

### 2. Database Load
- Load devices from `db` in `cfg.yaml` using happi
- Create `xxx_beampath` object using lightpath
- Create cameras from camviewer config

### 3. Beamline Load
- Import all objects from modules under `load` key
- Convention: `xxx.beamline`

### 4. Experiment Load
- Auto-select hutch's current experiment (if not in cfg.yml)
- Create user objects from questionnaire
- Import and instantiate `User` class
- Attach questionnaire objects to `User()`
- Set object as `x` and `user`

### 5. Groups Load
- Group `EpicsMotor` objects → `motors` (aliased to `m`)
- Group `Slits` objects → `slits` (aliased to `s`)
- Group by metadata → tab-accessible (e.g., `xxx.dg1.name`)
- Group all → `all_objects` (aliased to `a`)

### 6. Finish
- Create `_debug` objects
- Enable input, output, error logger
- Enter IPython terminal

---

## 4. Navigation & Namespaces

### Global Namespace Access

All devices are loaded into the global namespace:

```python
# Direct access by name
print(mfx_dg1_pim.inserted)  # Returns True/False
print(mfx_dg1_pim.position)
```

### Device Groupings

Devices are automatically grouped by class and position:

```python
# Iterate through all slits
for slit in slits:
    print(slit.name, slit.position)

# Iterate through devices at a location
for device in mfx.dg1:
    print(device.name)
```

### Namespace Utilities

```python
from pcdsdevices.device_types import GateValve
from hutch_python.namespace import class_namespace, tree_namespace

# Create custom grouping by class
valves = class_namespace(GateValve)
for valve in valves:
    print(valve.name, valve.position)
```

### Convenience Aliases

| Alias | Full Name | Description |
|-------|-----------|-------------|
| `m` | `motors` | All EpicsMotor objects |
| `s` | `slits` | All Slits objects |
| `p` | `plans` | Bluesky plans |
| `a` | `all_objects` | All loaded objects |
| `x` | `user` | User/experiment object |

---

## 5. Device Loading

Devices come from three sources:

### 1. Happi Device Database

Permanent beamline instrumentation stored centrally:

```python
# View device metadata
mfx_dg1_pim.md.show_info()
```

Output shows: prefix, device_class, beamline, z position, stand, system, etc.

### 2. LCLS User Questionnaire

Experiment-specific devices from PCDS setup page. Modify via questionnaire and reload session.

```python
# Questionnaire device metadata
shield_x.md.show_info()
```

### 3. Beamline Files

Custom devices in `xxx/beamline.py`:

```python
# In beamline.py
from xxx.beamline import *
```

Controlled by `__all__` list.

### Virtual Module Cache

Database objects accessible via runtime-generated module:

```python
from mfx.db import RE, mfx_attenuator
from bluesky.plans import scan

RE(scan([], mfx_attenuator, 0, 1, 10))
```

A `db.txt` file lists all loaded devices in order.

---

## 6. Lightpath / BeamPath

The `hutch_beampath` object provides physical beamline mapping:

```python
mfx_beampath.show_devices()
```

Output table shows: Name, Prefix, Position, Beamline, Removed status.

### Common Device API

All lightpath devices share this interface:

| Attribute/Method | Description |
|-----------------|-------------|
| `.position` | Current position/state |
| `.inserted` | Boolean - is device inserted? |
| `.removed` | Boolean - is device removed? |
| `.insert()` | Insert the device |
| `.remove()` | Remove the device |

---

## 7. DAQ (Data Acquisition)

The DAQ object controls data acquisition. Only one session can control the DAQ at a time.

### Basic Usage

```python
# Connect to DAQ
daq.connect()

# Run for 120 events
daq.begin(events=120, wait=True)
daq.end_run()

# Run for 1 second with recording and auto-end
daq.begin(duration=1, record=True, end_run=True)
daq.wait()

# Return control to GUI
daq.disconnect()
```

### DAQ Methods

| Method | Description |
|--------|-------------|
| `connect()` | Connect to DAQ |
| `begin(events=N)` | Start a run for N events |
| `begin(duration=N)` | Start a run for N seconds |
| `begin_infinite()` | Start infinite run |
| `end_run()` | Explicitly close a run |
| `wait()` | Wait for data collection |
| `disconnect()` | Return control to GUI |
| `preconfig()` | Pre-configure for use in scans |
| `configure(events=N)` | Configure event count |

### Scan PVs

Auxiliary PVs for organizing run tables (disabled by default):

```python
from pcdsdaq.scan_vars import ScanVars

scan_pvs = ScanVars("XPP:SCAN", name="scan_pvs", RE=RE)
scan_pvs.enable()
```

---

## 8. Bluesky Scanning

### RunEngine

The `RE` (RunEngine) executes all scans:

```python
from bluesky import RunEngine
RE = RunEngine({})
```

### Plan Namespaces

| Object | Description |
|--------|-------------|
| `bp` | Full plans ready to use |
| `bps` | Plan stubs (building blocks) |
| `bpp` | Plan preprocessors (wrappers) |
| `re` | Functions that run without passing to RE |

### Common Plans

**Count (Simple Detector Reading):**
```python
RE(bp.count([det], num=5))
```

**Scan (Motor Scan):**
```python
# Scan motor from -5 to 5 in 10 steps
RE(bp.scan([det], motor, -5, 5, num=10))

# Without a detector
RE(bp.scan([], motor, -5, 5, num=10))
```

**Adaptive Scan (Variable Step Size):**
```python
RE(bp.adaptive_scan([det], 'det', motor,
                    start=-15,
                    stop=10,
                    min_step=0.01,
                    max_step=5,
                    target_delta=.05,
                    backstep=True))
```

### DAQ Integration

**Method 1: DAQ Wrapper (Continuous)**
```python
RE(bpp.daq_wrapper(bp.scan([det], motor, -5, 5, num=10)))
```

**Method 2: DAQ as Detector (Per-Step)**
```python
daq.configure(events=120)
RE(bp.scan([daq, det], motor, -5, 5, num=10))
```

**Method 3: Using preconfig**
```python
daq.preconfig(events=120)
RE(scan([daq], motor, 0, 10, 11))
```

**Method 4: Custom Plans**
```python
yield from bps.trigger_and_read(daq)
```

---

## 9. Presets System

Save and manage motor position presets.

### Adding Presets

```python
# Permanent preset (all experiments)
reflaser.presets.add_hutch('tt', 42.1, comment='Add timetool in pos')

# Experiment-specific preset
reflaser.presets.add_exp_here('sample_pos', 10.5, comment='Sample position')
```

### Using Presets

```python
# Check preset position
reflaser.wm_tt()

# Move to preset
reflaser.mv_tt(wait=True)
```

### Managing Presets

```python
# View all active presets
reflaser.presets.positions  # Returns: namespace(refl=20.0, tt=40.0)

# Update preset position
reflaser.presets.positions.tt.update_pos(40.0, comment='Fix it again')

# Deactivate preset
reflaser.presets.positions.tt.deactivate()

# View preset history
reflaser.presets.tt.history
```

### Storage

Presets stored in YAML files:
- Permanent: `presets/beamline/<motor>.yml`
- Experiment: `presets/<experiment>/<motor>.yml`

---

## 10. Object Configuration

Customize object behavior after instantiation via YAML.

### Configuration File

Referenced in `conf.yml`:
```yaml
obj_config: /cds/group/pcds/pyps/apps/hutch-python/xxx/tabs.yml
```

### Directives

**tab_whitelist** - Reveal items in tab-completion:
```yaml
gon_sx:
  tab_whitelist:
    - kind
```

**tab_blacklist** - Hide items from tab-completion:
```yaml
at2l0:
  tab_blacklist:
    - blade_01
```

**replace_tablist** - Replace entire tab completion list:
```yaml
fast_motor1:
  replace_tablist:
    - position
```

**kind** - Modify ophyd kind (hinted vs config):
```yaml
at2l0:
  kind:
    at2l0: hinted
    blade_01: hinted
    blade_02: config
```

### Order of Operations

1. Tab whitelist
2. Tab blacklist
3. Replace tablist
4. Kind modifications

### Example Configuration

```yaml
# Device-specific
at2l0:
  tab_whitelist:
    - kind
  tab_blacklist:
    - blade_01
  kind:
    blade_01: hinted

# Class-based
pcdsdevices.epics_motor.IMS:
  tab_whitelist:
    - kind
```

---

## 11. Experiment Files

### Directory Structure

Experiments stored in `experiments/` directory:
- File naming: `experiments/{proposal}{run}.py` (lowercase)
- Example: `experiments/ls2516.py` for proposal LS25, run 16

### User Class Pattern

```python
# In experiments/ls2516.py
class User:
    def __init__(self):
        # Setup experiment-specific objects, plans, macros
        pass
```

### Loading

```python
from experiments.ls2516 import User
user = User()
x = user  # Alias
```

### Questionnaire Integration

Objects from CDS questionnaire automatically:
- Created based on questionnaire entries
- Attached to `User()` object
- Available in main namespace

### Override Experiment

In `conf.yml`:
```yaml
experiment:
  proposal: ls25
  run: 16
```

Or command line:
```bash
hutch-python --exp ls2516
```

---

## 12. Debugging & Logging

### Log Files

Logs stored in `logs/` directory, sorted by date/time.

### Default Filtering

- Spam-heavy loggers automatically filtered
- Warnings redirected to logging module
- Ophyd subscription exceptions demoted to DEBUG
- Ophyd INFO messages demoted to DEBUG

### Debug Tools

All available via `logs` namespace:

```python
# Toggle debug mode
logs.debug_mode(True)   # Enable
logs.debug_mode(False)  # Disable
print(logs.debug_mode())  # Check status

# Context manager for debug blocks
with logs.debug_context():
    buggy_function(arg)

# Enable debug for specific devices
logs.log_objects(important_device)
logs.log_objects_off()  # Reset
```

### Console Logging

```python
# Get/set console level
logs.get_console_level_name()
logs.set_console_level('DEBUG')

# Get log info
logs.get_log_directory()
logs.get_session_logfiles()
```

### Filtering

```python
# Silence specific device
logs.filter.blacklist.append(noisy_device.name)

# Unsilence spammy device
logs.filter.whitelist.append(important_noisy_device.name)

# File-specific filters
logs.file_filter.blacklist.append(device.name)
```

### PCDS-wide Logging

Integration with Grafana/ElasticSearch:

```python
import logging
pcds_logger = logging.getLogger('pcds-logging')
pcds_logger.info('I dropped the sample')

try:
    1/0
except ZeroDivisionError:
    pcds_logger.exception('This specific thing went wrong')
```

---

## 13. Bug Reporting

### Report a Bug

```python
# As function
report_bug(n_commands=10)

# As IPython magic
%report_bug my_buggy_function()
```

### Information Collected

- One-line problem description
- Verbose explanation
- Contact name
- Operator commands
- CONDA environment
- Relevant logfiles
- Terminal capture output
- Development mode packages

### Output

Issues posted to: https://github.com/pcdshub/Bug-Reports

---

## 14. Utilities

### safe_load

Wrap code to prevent bad submodules from interrupting load:

```python
from hutch_python.utils import safe_load

with safe_load('divide by zero'):
    1/0  # Completes with warning, visible in debug mode
```

### class_namespace

Create object groupings by type:

```python
from hutch_python.namespace import class_namespace

integers = class_namespace(int)
integers.three  # Access grouped objects
list(integers)  # Iterate in alphabetical order
```

### functools.partial for Scan Variants

```python
from bluesky.plans import scan
from functools import partial
from hutch.db import my_motor

my_scan = partial(scan, [], my_motor)
RE(my_scan(0, 100, num=10))
```

### Other Utilities

| Function | Description |
|----------|-------------|
| `hutch_banner()` | Display startup banner |
| `get_current_experiment()` | Get experiment info |
| `find_object()` | Locate specific object |
| `find_class()` | Locate class by type |
| `extract_objs()` | Extract objects from namespace |

---

## 15. Setting Up a New Hutch

### Create Hutch Repository

```bash
cd /reg/g/pcds/pyps/apps/hutch-python
hutch-python --create hutchname

# Initialize git
git init
git add *
git commit -m "Initial commit"

# Add remote
git remote add origin https://github.com/pcdshub/hutchname.git
git push origin master
```

### Configure Devices

Add devices using happi client:

```python
import happi
client = happi.Client(path='my/clone/device_config/db.json')

from happi.containers import Slits
my_slits = Slits(name='my_slits', prefix='MY:SLITS:01', beamline='TST')
client.add_device(my_slits)
```

### GitHub Integration

Create `.web.cfg` file with credentials for GitHub issue reporting.

### Update Launch Scripts

1. Run `hutch-python --create hutchname` with latest environment
2. Copy generated scripts into your checkout
3. Create branch, commit, push, make PR

---

## 16. Jupyter Notebook Setup

### Environment Setup

```bash
# Source hutch environment
source /cds/group/pcds/pyps/apps/hutch-python/xpp/xppenv

# Register kernel (one-time)
python -m ipykernel install --user --name=pcds-5.8.0

# Start notebook server
jupyter-notebook
```

**Note:** For DAQ control, run jupyter-notebook on the same host as DAQ.

### Manual Component Setup

**Virtual Module Cache:**
```python
from hutch_python.cache import LoadCache
cache = LoadCache("xpp.db")
```

**Ophyd Settings:**
```python
from hutch_python.ophyd_settings import setup_ophyd
setup_ophyd()
```

**RunEngine:**
```python
from bluesky import RunEngine
from bluesky.callbacks.best_effort import BestEffortCallback

RE = RunEngine({})
bec = BestEffortCallback()
bec.disable_plots()
RE.subscribe(bec)
cache(RE=RE, bec=bec)
```

**DAQ (LCLS1):**
```python
from pcdsdaq.daq.original import Daq
daq = Daq(RE=RE, hutch_name="xpp")
cache(daq=daq)
```

**Bluesky Plans:**
```python
from hutch_python.plan_wrappers import initialize_wrapper_namespaces
from hutch_python import plan_defaults

re = initialize_wrapper_namespaces(RE=RE, plan_namespace=plan_defaults.plans, daq=daq)
bp = plan_defaults.plans
bps = plan_defaults.plan_stubs
bpp = plan_defaults.preprocessors
cache(re=re, bp=bp, bps=bps, bpp=bpp)
```

**Happi Devices:**
```python
from happi import Client
client = Client.from_config()
xpp_sb3_pim = client.load_device(name="xpp_sb3_pim")
```

**Questionnaire Objects:**
```python
from types import SimpleNamespace
from hutch_python.qs_load import get_qs_objs

qs_objs = get_qs_objs("xppc00121")
qs = SimpleNamespace(**qs_objs)
```

**Beamline Load:**
```python
from xpp.beamline import *
```

**Experiment File:**
```python
from hutch_python.exp_load import get_exp_objs
x = get_exp_objs("c00121", ask_on_failure=False)
```

---

## 17. External Dependencies

### SLAC Modules

| Module | Description | Documentation |
|--------|-------------|---------------|
| `pcdsdaq` | DAQ control and bluesky integration | https://pcdshub.github.io/pcdsdaq |
| `pcdsdevices` | LCLS device classes and APIs | https://pcdshub.github.io/pcdsdevices |
| `happi` | Device database management | https://pcdshub.github.io/happi |

### NSLS-II Modules

| Module | Description | Documentation |
|--------|-------------|---------------|
| `bluesky` | RunEngine, plans, execution | https://nsls-ii.github.io/bluesky |
| `ophyd` | Device architecture and design | https://nsls-ii.github.io/ophyd |

### Additional Resources

- hutch-python: https://pcdshub.github.io/hutch-python
- lightpath: https://pcdshub.github.io/lightpath
- PCDS libraries: https://pcdshub.github.io

---

## Quick Reference

### Common Commands

```python
# Session info
hutch_banner()

# Device access
device.position
device.inserted
device.remove()
device.insert()
device.md.show_info()

# Scanning
RE(bp.count([det], num=5))
RE(bp.scan([det], motor, start, stop, num=N))

# DAQ
daq.connect()
daq.begin(events=120)
daq.end_run()

# Presets
motor.presets.add_hutch('name', value)
motor.mv_name()
motor.wm_name()

# Debugging
logs.debug_mode(True)
logs.log_objects(device)
report_bug()
```

### Aliases

| Short | Full | Description |
|-------|------|-------------|
| `RE` | RunEngine | Scan executor |
| `m` | motors | All motors |
| `s` | slits | All slits |
| `p` | plans | Bluesky plans |
| `a` | all_objects | Everything |
| `x` | user | Experiment user object |
| `bp` | bluesky.plans | Full plans |
| `bps` | bluesky.plan_stubs | Building blocks |
| `bpp` | bluesky.preprocessors | Plan wrappers |
