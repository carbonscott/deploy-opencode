# Binding Energies Lookup

## When to Use

- User asks what species to expect in XPS
- User mentions a surface + adsorbate system
- You need binding energies to generate a CRN
- You're interpreting experimental XPS peaks

## Usage

Reference the data directly from the binding energies JSON file:

```python
import json

# Load binding energies
with open('/sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac/binding_energies.json') as f:
    be_data = json.load(f)

# Get O 1s binding energies for Ag(110)
surface = "Ag(110)"
core_level = "O_1s"
species = be_data["binding_energies"][surface][core_level]

for name, info in species.items():
    print(f"{name}: {info['energy_eV']} eV")
```

## Data Format

```json
{
  "binding_energies": {
    "Ag(110)": {
      "O_1s": {
        "O*": {"energy_eV": 530.0, "site": "hollow"},
        "OH*": {"energy_eV": 530.9, "site": "bridge"},
        ...
      }
    }
  }
}
```

## Using in CRN Generation

When building a CRN, create species with these binding energies:

```python
from dtcs.spec.xps import XPSSpeciesManager

sm = XPSSpeciesManager()

# Use the exact binding energies from lookup
o = sm.make_species('O', 530.0, color='aqua')      # O* binding energy
oh = sm.make_species('OH', 530.9, color='red')     # OH* binding energy
h2o = sm.make_species('H2O', 532.2, color='blue')  # H2O* binding energy
```

## Available Data

Current database includes:
- Ag(110): O 1s binding energies for water chemistry species
- Ag(110)-(1x2): O 1s binding energies for reconstructed surface
- Ag(111): O 1s binding energies for water chemistry species
- Cu(111): O 1s and C 1s binding energies

To add new surfaces, edit the JSON file following the existing schema.

## Gotchas

1. **Surface naming in data file**: Use `Ag(110)` with parentheses
2. **Core level format**: Use `O_1s` with underscore
3. **Gas phase species**: H2O(g) is typically at ~535 eV, well separated from adsorbates
4. **Combined species**: Some entries are "combined" species (e.g., OH_combined = OH + OH-H2O) for XPS fitting purposes
