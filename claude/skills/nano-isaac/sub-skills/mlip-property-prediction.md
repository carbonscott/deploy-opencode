# MLIP Property Prediction

Compute missing energetic parameters on the fly using MACE-MP-0, a universal machine learning interatomic potential, dispatched to Modal for GPU access.

## When to Use

- The reaction parameters database returned `not_found` for a needed energy
- The user asks about a surface/adsorbate combination not in the pre-computed database
- Comparing energetics across sites or surfaces for hypothesis testing
- Quick screening before committing to expensive DFT calculations

**Always caveat results as MLIP screening estimates, not DFT-quality.**

**Note:** This capability requires a Modal account. It is available for users who have their own Modal credentials configured.

---

## Available Calculations

| Calculation | Description | Typical Runtime | Reliability |
|---|---|---|---|
| Adsorption energy | E_ads = E(slab+ads) - E(slab) - E(molecule) | 10-30 sec | Good for common adsorbates on transition metals |
| Surface energy | E_surf = (E(slab) - n*E(bulk)) / (2*A) | 5-15 sec | Good |
| Geometry optimization | Relax a structure to local minimum | 5-30 sec | Good |
| Single-point energy | Energy at fixed geometry | 1-5 sec | Good |

Runtimes assume a cached Modal image on a T4 GPU. First run builds the image (~60s).

---

## Modal Script Pattern

Every generated script follows the same structure: a self-contained Modal app with a `MACEWorker` class that loads the model once via `@modal.enter()`.

### Image Definition

Always use this exact image definition. MACE weights are baked in at build time so containers start fast.

```python
import modal

image = modal.Image.debian_slim(python_version="3.11").pip_install(
    "torch>=2.1", "mace-torch", "ase", "numpy", "scipy"
).run_commands(
    "python -c \"from mace.calculators import mace_mp; mace_mp(model='medium', device='cpu')\""
)

app = modal.App("isaac-mlip-DESCRIPTION", image=image)
```

Replace `DESCRIPTION` with something identifying the calculation (e.g., `isaac-mlip-oh-ag110`).

### Class with One-Time Model Loading

```python
@app.cls(gpu="T4", timeout=600)
class MACEWorker:
    @modal.enter()
    def load_model(self):
        from mace.calculators import mace_mp
        self.calc = mace_mp(model="medium", dispersion=False, device="cuda")

    @modal.method()
    def compute(self):
        # ... calculation code here, using self.calc ...
        pass

@app.local_entrypoint()
def main():
    worker = MACEWorker()
    worker.compute.remote()
```

The `@modal.enter()` method runs once when the container starts. All `@modal.method()` calls on the same instance reuse `self.calc`.

### Running

**Important:** Always write and run Modal scripts directly from the main agent context. Do not delegate MLIP calculations to Task subagents — they lack the permissions to write files and execute `modal run`.

```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/nano-isaac/env.sh && nano_isaac_run modal run /tmp/nano-isaac-$USER/mlip_calc.py
```

---

## Building Structures with ASE

### Slabs

```python
from ase.build import fcc111, fcc110, fcc100
from ase.constraints import FixAtoms

# Build slab: element, supercell (x, y, layers), vacuum padding
slab = fcc110("Ag", size=(3, 3, 4), vacuum=15.0)

# Fix bottom 2 layers
z = slab.positions[:, 2]
mask = z < z.min() + 2.5  # adjust threshold per surface
slab.set_constraint(FixAtoms(mask=mask))
```

### Adsorbates

```python
from ase import Atoms
from ase.build import add_adsorbate

# Atomic adsorbate
add_adsorbate(slab, "O", height=1.5, position="hollow")

# Molecular adsorbate (OH)
oh = Atoms("OH", positions=[[0, 0, 0], [0, 0, 0.97]])
add_adsorbate(slab, oh, height=1.5, position="bridge")

# Water
h2o = Atoms("OH2", positions=[[0, 0, 0], [-0.76, 0.59, 0], [0.76, 0.59, 0]])
add_adsorbate(slab, h2o, height=2.0, position="ontop")
```

### Common Sites by Surface

| Surface | Sites |
|---------|-------|
| fcc111 | `ontop`, `bridge`, `fcc`, `hcp` |
| fcc110 | `ontop`, `longbridge`, `shortbridge`, `hollow` |
| fcc100 | `ontop`, `bridge`, `hollow` |

### Gas-Phase References

Put molecules in a large box to avoid self-interaction:

```python
mol = Atoms("OH", positions=[[0, 0, 0], [0, 0, 0.97]])
mol.center(vacuum=10.0)
```

**Reference convention:** Use the intact molecular adsorbate as the gas-phase reference — the same species that's on the surface.

| Adsorbate | Gas reference | ASE construction |
|-----------|--------------|------------------|
| O* | O atom in a box | `Atoms("O"); mol.center(vacuum=10.0)` |
| OH* | OH radical in a box | `Atoms("OH", positions=[[0,0,0],[0,0,0.97]]); mol.center(vacuum=10.0)` |
| H2O* | H2O molecule in a box | `Atoms("OH2", positions=[[0,0,0],[-0.76,0.59,0],[0.76,0.59,0]]); mol.center(vacuum=10.0)` |
| H* | H atom in a box | `Atoms("H"); mol.center(vacuum=10.0)` |

This convention gives adsorption energies that directly measure the surface bond strength. Do **not** use 1/2 O2 or 1/2 H2 as references — those mix in bond dissociation energies and make the numbers harder to compare across species or use in CRN rate expressions.

---

## Computing Adsorption Energy

This is the primary use case. Full pattern:

```python
@modal.method()
def compute(self):
    import json
    import time
    from ase import Atoms
    from ase.build import fcc110, add_adsorbate
    from ase.constraints import FixAtoms
    from ase.optimize import BFGS

    t_start = time.time()

    def build_slab():
        slab = fcc110("Ag", size=(3, 3, 4), vacuum=15.0)
        z = slab.positions[:, 2]
        mask = z < z.min() + 2.5
        slab.set_constraint(FixAtoms(mask=mask))
        return slab

    def relax(atoms, fmax=0.05, steps=200):
        atoms.calc = self.calc
        opt = BFGS(atoms, logfile=None)
        converged = bool(opt.run(fmax=fmax, steps=steps))
        energy = float(atoms.get_potential_energy())
        return energy, converged

    # 1. Relax clean slab
    slab_clean = build_slab()
    E_slab, _ = relax(slab_clean)

    # 2. Relax gas-phase molecule
    oh_gas = Atoms("OH", positions=[[0, 0, 0], [0, 0, 0.97]])
    oh_gas.center(vacuum=10.0)
    E_mol, _ = relax(oh_gas)

    # 3. Place adsorbate and relax
    slab_ads = build_slab()
    oh = Atoms("OH", positions=[[0, 0, 0], [0, 0, 0.97]])
    add_adsorbate(slab_ads, oh, height=1.5, position="longbridge")
    E_slab_ads, ads_converged = relax(slab_ads)

    # 4. Compute
    E_ads = E_slab_ads - E_slab - E_mol

    t_end = time.time()

    result = {
        "calculation_type": "adsorption_energy",
        "system": "OH on Ag(110) longbridge",
        "E_slab_eV": round(E_slab, 4),
        "E_molecule_gas_eV": round(E_mol, 4),
        "E_slab_adsorbate_eV": round(E_slab_ads, 4),
        "E_adsorption_eV": round(E_ads, 4),
        "converged": ads_converged,
        "units": "eV",
        "model": "MACE-MP-0 medium",
        "total_time_s": round(t_end - t_start, 1),
        "notes": "MLIP estimate — use for screening, not publication",
    }
    print(json.dumps(result, indent=2))
```

**Convention:** negative E_ads = exothermic (favorable) adsorption.

---

## JSON Output Format

All calculations must print a single JSON object to stdout. The agent parses this to extract results.

```json
{
  "calculation_type": "adsorption_energy",
  "system": "OH on Ag(110) longbridge",
  "E_adsorption_eV": -2.3623,
  "converged": true,
  "units": "eV",
  "model": "MACE-MP-0 medium",
  "total_time_s": 11.6,
  "notes": "MLIP estimate — use for screening, not publication"
}
```

Cache results to `/tmp/nano-isaac-$USER/mlip_results/` with descriptive filenames (e.g., `OH_Ag110_longbridge_adsorption.json`).

---

## Sanity Checks

Apply these after every calculation:

| Symptom | Likely Cause | Action |
|---------|-------------|--------|
| E_ads positive and large (> +1 eV) | Adsorbate didn't bind or optimization diverged | Check final structure, try different site or lower initial height |
| Optimization didn't converge in 200 steps | Unreasonable initial geometry or complex PES | Increase `steps`, report to user |
| Adsorbate desorbed during relaxation | Initial height too large or site unstable | Try lower height or different site |
| Slab atoms moved significantly | Bottom layers not constrained | Check `FixAtoms` mask |
| Energy differences > 5 eV for adsorption | Mismatched reference energies | Verify same calculator settings for all components |
| Results differ from DFT by > 0.5 eV | Normal MLIP uncertainty | Caveat to user, suggest DFT for quantitative work |

---

## Gotchas

1. **Numpy serialization**: ASE returns numpy `float32`/`float64` and numpy `bool_`, which are not JSON-serializable. Always cast with `float()` and `bool()` before building the result dict.

2. **MACE stderr noise**: MACE prints warnings about `cuequivariance`, `TORCH_FORCE_NO_WEIGHTS_ONLY_LOAD`, and dtype conversion on every load. These are harmless. When parsing script output, look for the JSON blob, not the first line of stdout.

3. **float32 vs float64**: MACE defaults to float32 for speed. This is fine for adsorption energy screening. For geometry optimization requiring high precision, pass `default_dtype="float64"` to `mace_mp()`.

4. **GPU selection**: Use `gpu="T4"` (cheapest, sufficient for MACE). `"A10G"` or `"A100"` available for larger systems (>200 atoms).

5. **Calculator reuse**: The `MACEWorker` class loads the model once. All relaxations in a single `@modal.method()` call should use `self.calc`. Do not call `mace_mp()` multiple times.

6. **Image caching**: Modal caches images after the first build. First invocation of a new script takes ~60s for image build; subsequent runs skip this. The MACE weights are baked into the image via `.run_commands()` so they don't re-download at runtime.

---

## Current Limitations

- **Model**: MACE-MP-0 "medium" only. No custom model upload in v1.
- **Accuracy**: Screening-quality, not publication-quality. Always caveat to user.
- **NEB barriers**: Not yet supported. Adsorption energies and surface energies only.
- **Surface CRN**: Only bulk CRN simulations downstream (same as existing DTCS limitation).
