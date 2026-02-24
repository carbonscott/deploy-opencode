# Reaction Parameters Database

Query DFT-calculated activation energies for surface reactions. This database follows Catalysis Hub conventions for surface naming and reaction notation.

**Important:** Use the CLI commands below to query the database. Do not read the underlying data files directly.

## Commands

### List Available Surfaces

```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/env.sh && nano_isaac_run python /sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac/scripts/reaction_db.py list-surfaces --element Ag
```

Returns all surfaces for a given element:
```json
{
  "surfaces": ["Ag(100)", "Ag(110)", "Ag(111)", "Ag(211)", ...]
}
```

### List Reactions for a Surface

```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/env.sh && nano_isaac_run python /sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac/scripts/reaction_db.py list-reactions --surface "Ag(110)"
```

Returns available reactions:
```json
{
  "surface": "Ag(110)",
  "reactions": [
    "H2O(g) + * -> H2O*",
    "H2O(g) + O* -> O-H2O*",
    "O-H2O* -> 2OH*",
    ...
  ]
}
```

### Get Activation Energy

```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/env.sh && nano_isaac_run python /sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac/scripts/reaction_db.py get-barrier --surface "Ag(110)" --reaction "O-H2O* -> 2OH*"
```

Returns activation energies and thermodynamics:
```json
{
  "Ea_fwd": 0.36,
  "Ea_rev": 1.0,
  "dE": -0.64,
  "site": "hollow",
  "surface": "Ag(110)",
  "reaction": "O-H2O* -> 2OH*",
  "reference": "DFT-PBE, this work"
}
```

## Reaction Notation

Reactions use standard surface science notation:
- `*` = adsorbed species (e.g., `O*`, `OH*`, `H2O*`)
- `(g)` = gas phase (e.g., `H2O(g)`)
- `->` = reaction direction

Use `list-reactions` to see the exact format for available reactions.

## Handling Missing Data

If a surface or reaction isn't in the database:
```json
{
  "status": "not_found",
  "message": "No parameters available for Ag(100).",
  "suggestions": [
    "Search literature via Edison",
    "Compute an MLIP estimate using the mlip_property_prediction skill",
    "Request DFT calculation"
  ]
}
```

## Energy Units

All energies are in **eV**:
- `Ea_fwd`: Forward activation energy (barrier from reactants)
- `Ea_rev`: Reverse activation energy (barrier from products)
- `dE`: Reaction energy (negative = exothermic)

## Using in Kinetic Models

Convert activation energies to rate constants:

```python
import math

KB = 8.617e-5  # eV/K
NU = 1e13      # attempt frequency (1/s)

def rate_constant(Ea, T):
    """Arrhenius rate constant at temperature T (Kelvin)."""
    if Ea <= 0:
        return NU  # Barrierless
    return NU * math.exp(-Ea / (KB * T))

# Example: O-H2O* -> 2OH* at 298 K
k = rate_constant(0.36, 298)  # ~8e6 /s
```

For adsorption reactions, scale by pressure:
```python
P0 = 1e-3  # Reference pressure (Torr)

def adsorption_rate(Ea, T, P):
    """Pressure-dependent adsorption rate."""
    k = rate_constant(Ea, T)
    return k * (P / P0)
```
