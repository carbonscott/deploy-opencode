# VAMAS XPS Data Handler

Parse VAMAS (ISO 14976) files from XPS, AES, and other surface analysis instruments.

## Core Operations

### List Blocks in File
```python
from vamas import Vamas

vms = Vamas("data.vms")
for i, block in enumerate(vms.blocks):
    print(f"{i}: {block.block_identifier} - {block.sample_identifier}")
```

### Extract Spectrum Data
```python
from vamas import Vamas
import numpy as np

vms = Vamas("data.vms")
block = vms.blocks[0]  # Select block by index

# Calculate energy axis
num_x = block.num_y_values // block.num_corresponding_variables
kinetic_energy = np.array([block.x_start + i * block.x_step for i in range(num_x)])

# Convert to binding energy (Al Ka source = 1486.6 eV)
binding_energy = 1486.6 - kinetic_energy

# Get intensity
intensity = np.array(block.corresponding_variables[0].y_values)
```

### Plot XPS Spectrum
```python
import matplotlib.pyplot as plt

plt.plot(binding_energy, intensity)
plt.xlabel('Binding Energy (eV)')
plt.ylabel('Intensity (counts)')
plt.gca().invert_xaxis()  # XPS convention
plt.title(block.block_identifier)
plt.savefig('spectrum.png', dpi=150)
```

## Using the Parser Script

The `vamas_parser.py` script provides CLI access:

```bash
# List all blocks
source /sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/env.sh && nano_isaac_run python /sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac/scripts/vamas_parser.py data.vms --list

# Get file metadata
source /sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/env.sh && nano_isaac_run python /sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac/scripts/vamas_parser.py data.vms --info

# Extract spectrum as JSON
source /sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/env.sh && nano_isaac_run python /sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac/scripts/vamas_parser.py data.vms --block 0 --json

# Export to CSV
source /sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/env.sh && nano_isaac_run python /sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac/scripts/vamas_parser.py data.vms --block 5 --export spectrum.csv
```

## VAMAS Block Structure

Each block contains:
- `block_identifier`: Region name (e.g., "O 1s", "Ag 3d", "Survey")
- `sample_identifier`: Sample label/conditions
- `technique`: Measurement type (XPS, AES, UPS, etc.)
- `x_start`, `x_step`: Energy axis parameters
- `corresponding_variables`: List with intensity, transmission, etc.

Access pattern:
```python
block.block_identifier      # "O 1s"
block.sample_identifier     # "Sample at 300K"
block.technique            # "XPS"
block.analysis_source_characteristic_energy  # X-ray source energy
block.analyzer_pass_energy_or_retard_ratio_or_mass_res  # Pass energy
```

## Common XPS Parameters

| Parameter | Typical Al Ka | Mg Ka |
|-----------|---------------|-------|
| Source Energy | 1486.6 eV | 1253.6 eV |
| Work Function | ~4.5 eV | ~4.5 eV |

Binding Energy = Source Energy - Kinetic Energy - Work Function

## Batch Processing Example

Process all blocks of a specific type:
```python
from vamas import Vamas
import numpy as np

vms = Vamas("data.vms")
o1s_spectra = []

for block in vms.blocks:
    if block.block_identifier == "O 1s":
        num_x = block.num_y_values // block.num_corresponding_variables
        ke = np.array([block.x_start + i * block.x_step for i in range(num_x)])
        intensity = np.array(block.corresponding_variables[0].y_values)
        o1s_spectra.append({
            'sample': block.sample_identifier,
            'be': 1486.6 - ke,
            'intensity': intensity
        })
```

## Export to DataFrame

```python
import pandas as pd

# Create DataFrame from spectrum
df = pd.DataFrame({
    'binding_energy_eV': binding_energy,
    'intensity': intensity
})
df.to_csv('spectrum.csv', index=False)
```

## Troubleshooting

**Multiple y-value arrays**: VAMAS stores multiple variables (intensity, transmission). Always check `num_corresponding_variables`:
```python
num_x = block.num_y_values // block.num_corresponding_variables
```

**Energy units**: Check `block.x_label` and `block.x_units` - may be Kinetic or Binding energy.

**Large values (1e+037)**: Placeholder for undefined values in VAMAS format - ignore these.

## References

See `references/xps_interpretation.md` for XPS data interpretation guidance.
