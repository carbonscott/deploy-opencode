# CRN Generation

## When to Use

- User wants to simulate what species should appear on a surface
- You need to predict XPS spectral features at given conditions
- Comparing expected vs observed spectra
- Testing hypotheses about surface chemistry

---

## Quick Start: Minimal Working Example

Run this to verify DTCS is working:

```python
"""Minimal DTCS test: A + B <-> C reaction"""
from dtcs.spec.xps import XPSSpeciesManager
from dtcs.spec.crn.bulk import CRNSpec, Rxn, Conc

sm = XPSSpeciesManager()
a = sm.make_species('A', 530.0, color='red')
b = sm.make_species('B', 531.0, color='blue')
c = sm.make_species('C', 532.0, color='green')

crn = CRNSpec(
    Rxn(a + b, c, k=1.0),      # A + B -> C
    Rxn(c, a + b, k=0.5),      # C -> A + B
    Conc(a, 1.0),
    Conc(b, 1.0),
    sm,
    time=10,
)

cts = crn.simulate()

# Get results as DataFrame
df = cts.df
print(df.tail())

# Get final concentrations
final = df.iloc[-1]
print(f"\nFinal: A={final['A']:.3f}, B={final['B']:.3f}, C={final['C']:.3f}")
```

Save to `/tmp/nano-isaac-$USER/simulation.py` and run with:
```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/env.sh && nano_isaac_run python /tmp/nano-isaac-$USER/simulation.py
```

---

## Two-Phase Workflow

**Important**: CRN generation is a collaborative process. The user is a domain expert who should validate the chemistry before simulation.

### Phase 1: Propose CRN for User Review

Before writing any code, present the proposed reaction network in human-readable notation:

```
For this system, I'm proposing the following reaction network:

H2O(g) + O* <-> O-H2O*        (water adsorption on atomic oxygen)
H2O(g) + OH* <-> OH-H2O*      (water adsorption on hydroxyl)
O-H2O* <-> 2OH*               (dissociation)
O-H2O* -> H2O* + O*          (diffusion/separation)
OH-H2O* -> H2O* + OH*        (diffusion/separation)
H2O(g) <-> H2O*               (molecular adsorption)
OH-H2O* + H2O(g) <-> H2O_multi*  (multilayer formation)

Does this capture the chemistry you expect?
```

**Wait for user confirmation before proceeding to Phase 2.**

### Phase 2: Translate to DTCS Code

Only after user approval, generate the DTCS Python code and run the simulation.

---

## Human-Readable CRN Notation

Use standard chemical notation that domain experts will recognize:

| Notation | Meaning |
|----------|---------|
| `A + B <-> C` | Reversible reaction |
| `A + B -> C` | Irreversible reaction |
| `X*` | Surface-adsorbed species |
| `X(g)` | Gas-phase species |
| `2X*` | Stoichiometric coefficient |

Include brief annotations explaining each reaction's role (adsorption, dissociation, diffusion, etc.)

---

## DTCS Implementation

### Core Imports

```python
from dtcs.spec.xps import XPSSpeciesManager
from dtcs.spec.crn.bulk import CRNSpec, Rxn, RevRxn, Conc, ConcEq
```

| Component | Purpose |
|-----------|---------|
| `XPSSpeciesManager` | Creates species with XPS binding energies |
| `Rxn(reactants, products, k=rate)` | Irreversible reaction: A -> B |
| `RevRxn(reactants, products, k=k_fwd, k2=k_rev)` | Reversible reaction: A <-> B |
| `Conc(species, amount)` | Initial concentration |
| `ConcEq(combined, a + b)` | Combine species for output (e.g., group by BE) |
| `CRNSpec(...)` | Assembles reactions and runs simulation |

### Rate Constants

DTCS uses these formulas to convert activation/Gibbs energies to rate constants (from `dtcs/spec/crn/rxn_abc.py`):

```python
# Surface reactions (not pressure-dependent):
k = exp(-0.1 * Ea / (kB * T))

# Adsorption from gas phase (pressure-dependent):
k = (P / 0.1 torr) * exp(-0.1 * Ea / (kB * T))
```

Where:
- `Ea` = activation energy in eV (negative = exothermic/barrierless)
- `kB` = 8.617e-5 eV/K (Boltzmann constant)
- `T` = temperature in Kelvin
- `P` = pressure in torr
- The factor `0.1` is a DTCS convention that scales rates to reasonable ODE solver ranges

**Computing rate constants from activation energies:**

```python
import math

kB = 8.617333262145e-5  # eV/K
T = 298.15  # K
P_torr = 0.1  # torr

factor = 0.1 / (kB * T)  # ~3.89 at 298 K

def rate_surface(Ea):
    """For surface reactions (dissociation, diffusion)."""
    return math.exp(-factor * Ea)

def rate_adsorption(Ea, P_torr):
    """For gas adsorption reactions."""
    return (P_torr / 0.1) * math.exp(-factor * Ea)

# Example: Ea = -0.3 eV (exothermic)
k = rate_surface(-0.3)  # k = 3.21
```

**For pre-computed rate constants** (like the Ag(111) example), just use numeric values directly:

```python
Rxn(o + h2o_g, o_h2o, k=3.915)  # Pre-computed at specific T, P
```

For the **inverse problem** (fitting to experimental data), DTCS uses symbolic Gibbs energies — see the DTCS documentation for `fit_gibbs()`.

### Species Definition

```python
sm = XPSSpeciesManager()

# Species visible in XPS (have real binding energies)
h2o = sm.make_species('H2O', 532.2, color='blue')
oh = sm.make_species('OH', 530.9, color='red')
o = sm.make_species('O', 530.0, color='aqua')

# Intermediate species (BE=0 means "hidden", will be combined later)
oh_h2o = sm.make_species('OH-H2O_hb', 0, color='black')

# Combined species for XPS output
oh_combined = sm.make_species('OH_combined', 530.9, color='red')
```

### Running Simulations and Extracting Results

```python
crn = CRNSpec(
    # ... reactions ...
    # ... initial conditions ...
    sm,
    time=20,  # simulation time (arbitrary units)
)

cts = crn.simulate()

# Results are in a pandas DataFrame
df = cts.df
print(df.columns)  # Species names
print(df.tail())   # Last few time points

# Get final concentrations - use species OBJECTS, not strings!
final = df.iloc[-1]
print(f"O* concentration: {final[o]:.4f}")  # Use the species object, NOT 'O'

# Plot concentration vs time
cts.plot(species=[h2o, oh_combined, o_combined])

# Generate synthetic XPS spectrum
xps = cts.xps_with(species=[h2o, oh_combined, o_combined, h2o_multi])
xps.plot()
```

---

## Complete Example: Water on Ag(111)

This example is adapted from a working DTCS demo notebook.

### Phase 1: Proposed CRN

```
Proposed reaction network for water on Ag(111):

H2O(g) + O* -> O-H2O*         (1) water adsorption on O* with H-bonding
H2O(g) + OH* -> OH-H2O*       (2) water adsorption on OH* with H-bonding
O-H2O* <-> 2OH*                (3) dissociation to form hydroxyls
OH-H2O* -> H2O* + OH*         (4) complex diffusion/separation
O-H2O* -> H2O* + O*           (5) complex diffusion/separation
H2O* <-> H2O(g)                (6,7) molecular water adsorption/desorption
OH-H2O* -> OH* + H2O(g)       (8) desorption from OH-H2O complex
O-H2O* -> O* + H2O(g)         (9) desorption from O-H2O complex
OH-H2O* + H2O(g) <-> H2O_multi (10,11) multilayer formation

Initial conditions: 0.25 ML atomic oxygen, ~0.1 torr H2O, 25C
```

### Phase 2: DTCS Implementation (after user approval)

```python
"""
DTCS simulation: Water chemistry on Ag(111) surface.
Adapted from working demo notebook.
"""
from dtcs.spec.xps import XPSSpeciesManager
from dtcs.spec.crn.bulk import CRNSpec, Rxn, RevRxn, Conc, ConcEq

# === Create Species Manager ===
sm = XPSSpeciesManager()

# Gas phase (not observed in XPS, but needed for reactions)
h2o_g = sm.make_species('H2O_g', 535.0, color='gray', latex='H_2O_g')

# Surface species with XPS binding energies
h2o = sm.make_species('H2O', 532.2, color='blue', latex='H_2O^*')
h2o_multi = sm.make_species('multiH2O', 533.2, color='magenta', latex='H_2O_{multi}^*')

# Intermediate species (BE=0, will be combined for output)
oh = sm.make_species('OH', 0, color='red', latex='OH^*')
o = sm.make_species('O', 0, color='aqua', latex='O^*')
oh_h2o = sm.make_species('OH-H2O_hb', 0, color='black', latex='OH-H_2O^*')
o_h2o = sm.make_species('O-H2O_hb', 0, color='black', latex='O-H_2O^*')

# Combined species for XPS output (these have the real BEs)
oh_combined = sm.make_species('OH_combined', 530.9, color='red', latex='OH_{combined}^*')
o_combined = sm.make_species('O_combined', 530.0, color='aqua', latex='O_{combined}^*')
h2o_hb_combined = sm.make_species('H2O_hb_combined', 531.6, color='black', latex='H_2O_{hb}^*')

# === Build CRN with pre-computed rate constants ===
# Rate constants from DFT-derived Gibbs energies at ~0.1 torr, 298 K
crn = CRNSpec(
    Rxn(o + h2o_g, o_h2o, k=3.915042),           # (1) H2O on O* adsorption with HB
    Rxn(oh + h2o_g, oh_h2o, k=1.664002),         # (2) H2O on OH* adsorption with HB
    Rxn(o_h2o, oh + oh, k=6.220646),             # (3) O-H2O -> 2OH forward
    Rxn(oh + oh, o_h2o, k=0.160755),             # (3) 2OH -> O-H2O reverse
    Rxn(oh_h2o, h2o + oh, k=0.299507),           # (4) OH-H2O diffusion
    Rxn(o_h2o, h2o + o, k=0.167130),             # (5) O-H2O diffusion
    Rxn(h2o, h2o_g, k=0.794455),                 # (6) H2O desorption
    Rxn(h2o_g, h2o, k=0.629363),                 # (7) H2O adsorption
    Rxn(oh_h2o, oh + h2o_g, k=0.300480),         # (8) H2O on OH* desorption with HB
    Rxn(o_h2o, o + h2o_g, k=0.127713),           # (9) H2O on O* desorption with HB
    Rxn(oh_h2o + h2o_g, h2o_multi, k=1.267427),  # (10) multilayer adsorption
    Rxn(h2o_multi, oh_h2o + h2o_g, k=0.394500),  # (11) multilayer desorption

    # Combine species for XPS output
    ConcEq(oh_combined, oh + oh_h2o),
    ConcEq(o_combined, o + o_h2o),
    ConcEq(h2o_hb_combined, o_h2o + oh_h2o),

    # Initial conditions
    Conc(h2o_g, 1),      # Gas phase reservoir (normalized)
    Conc(o, 0.25),       # 0.25 ML initial oxygen coverage

    sm,
    time=20,
)

# === Run Simulation ===
cts = crn.simulate()

# === View Results ===
# Plot concentration evolution
cts.plot(species=[h2o, oh_combined, o_combined, h2o_hb_combined, h2o_multi])

# Generate XPS spectrum at final time
xps = cts.xps_with(species=[h2o, oh_combined, o_combined, h2o_hb_combined, h2o_multi])
xps.plot()

# Get final concentrations from DataFrame
# IMPORTANT: Use species OBJECTS to index, not strings!
df = cts.df
final = df.iloc[-1]
print("Final concentrations (surface species):")
print(f"  H2O* (532.2 eV):        {final[h2o]:.4f}")
print(f"  OH_combined (530.9 eV): {final[oh_combined]:.4f}")
print(f"  O_combined (530.0 eV):  {final[o_combined]:.4f}")
print(f"  H2O_hb (531.6 eV):      {final[h2o_hb_combined]:.4f}")
print(f"  multiH2O (533.2 eV):    {final[h2o_multi]:.4f}")
```

---

## Output Format

Save generated simulation scripts to `/tmp/nano-isaac-$USER/simulation.py` and run with:

```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/env.sh && nano_isaac_run python /tmp/nano-isaac-$USER/simulation.py
```

---

## Key Patterns

### Reversible reactions: Two ways to write them

**Option 1**: Use `RevRxn` with k and k2
```python
RevRxn(a + b, c, k=1.0, k2=0.5)  # A + B <-> C
```

**Option 2**: Use two separate `Rxn` calls (often clearer)
```python
Rxn(a + b, c, k=1.0)   # A + B -> C
Rxn(c, a + b, k=0.5)   # C -> A + B
```

### Hidden intermediates with ConcEq

When multiple surface species contribute to the same XPS peak:
```python
# Elementary species (BE=0, hidden)
oh = sm.make_species('OH', 0, color='red')
oh_h2o = sm.make_species('OH-H2O_hb', 0, color='black')

# Combined for output (has real BE)
oh_combined = sm.make_species('OH_combined', 530.9, color='red')

# In CRNSpec:
ConcEq(oh_combined, oh + oh_h2o)  # Sum of OH in both forms
```

---

## Gotchas

1. **Get user approval first**: Always present human-readable CRN before generating code
2. **Stoichiometry**: `A <-> 2B` means `Rxn(a, b + b, ...)`
3. **Gas phase reservoir**: H2O(g) starts at concentration 1 and stays roughly constant
4. **Hidden species**: Set BE=0 for intermediates, combine them with `ConcEq` for XPS output
5. **DataFrame columns are SymPy Symbols, not strings**: You MUST use the species object to index into the DataFrame. `final['O']` will raise `KeyError` even though it looks like 'O' is a column name. Use `final[o]` with the species object instead.
6. **Rate constants**: For forward problems, use pre-computed numbers; don't invent rate calculation formulas

## Current Limitations

- Only bulk CRN simulations (no explicit surface diffusion modeling)
- Rate constants must be pre-computed or obtained from literature/DFT
- Surfaces need binding energies from data files or literature
