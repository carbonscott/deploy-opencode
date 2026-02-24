# Spectrum Analysis

## When to Use

- User provides experimental XPS data
- Simulated spectrum doesn't match experiment
- Diagnosing discrepancies between prediction and observation
- Analyzing time-series data for beam damage
- Testing hypotheses about surface chemistry

## Comparing Expected vs Observed Spectra

### Step 1: Establish Expected Spectrum

Determine what the spectrum *should* look like based on:
- Simulation results (species concentrations + binding energies)
- Literature values for this system
- Previous experiments under similar conditions
- Binding energy lookups for expected species

### Step 2: Compare Key Features

Look at:
1. **Peak positions**: Are peaks at expected binding energies?
2. **Relative intensities**: Do peak ratios match?
3. **Unexpected features**: Peaks where none should be?
4. **Missing features**: Expected peaks that are absent?

### Step 3: Diagnose Discrepancies

Common causes of mismatch:

| Symptom | Possible Cause | How to Check |
|---------|----------------|--------------|
| Peaks shifted ~0.5-1 eV | Surface charging | Check metal reference peak |
| Extra/unexpected peaks | Different species than modeled | Check sample prep, search literature |
| Broader peaks | Multiple environments | Higher spectral resolution needed |
| Peak at 284-285 eV | Adventitious carbon | Always present, ignore or subtract |
| Peak at 531.5-533 eV | SiOx contamination | Check Si 2p region |
| Peak changes over time | Beam damage | Analyze time series |

## Time-Series Analysis

When user provides spectra over time:

```
Stable spectra -> NOT beam damage
Evolving spectra -> Possible beam damage or slow kinetics
```

### Beam Damage Signatures

- **Reduction**: Metal oxide -> metal (peak shifts lower)
- **Desorption**: Adsorbate peaks decrease
- **Decomposition**: New peaks appear
- **Rate**: Changes accelerate with flux

### Ruling Out Beam Damage

```python
# Pseudo-code for time series analysis
def analyze_time_series(spectra_list):
    """
    Check if spectra change over time.
    Returns: 'stable', 'evolving', or 'degrading'
    """
    for i in range(len(spectra_list) - 1):
        diff = compare_spectra(spectra_list[i], spectra_list[i+1])
        if diff > threshold:
            return 'evolving'
    return 'stable'
```

## Spectral Interpretation Guidelines

### O 1s Region (528-536 eV)

Typical binding energy ranges for oxygen species (exact values vary by surface):

| Binding Energy Range | Species | Notes |
|----------------------|---------|-------|
| 528-529 eV | Lattice oxide | Bulk oxide formation |
| ~529-531 eV | O* (atomic) | Site-dependent |
| ~530-532 eV | OH* | Often overlaps with other species |
| ~531-532 eV | H-bonded complexes | OH-H2O*, O-H2O* |
| ~532-533 eV | H2O* | Molecular water |
| ~533-534 eV | H2O(ice) | Multilayer/ice |
| ~535 eV | H2O(g) | Gas phase |

**Important**: Look up specific binding energies for your surface from data sources - values shift by surface and site.

### Peak Overlap Issues

Adjacent species can be difficult to resolve:
- O* vs OH*: often ~1 eV separation
- OH* vs H-bonded: often ~0.5-0.7 eV separation
- Need instrumental resolution <0.5 eV to fully resolve

## Contamination Detection

### Carbon Contamination
- **Adventitious carbon**: 284-285 eV in C 1s
- Always present, usually ~0.5-1 ML equivalent
- Not necessarily a problem unless it interferes

### Silicon Contamination
- **SiOx**: 531.5-533 eV in O 1s (overlaps with OH*, H2O*)
- Check Si 2p region (~103 eV for SiO2)
- Common at high T and near-ambient pressures

### Oxygen Background
- O* can form from O2 dissociation
- Rapidly reacts with H2O: O* + H2O -> 2OH*
- May shift expected distribution toward OH*

## Workflow for Mismatch Diagnosis

```
1. User reports mismatch
   |
2. Generate simulation at their conditions
   |
3. Compare: which peaks disagree?
   |
4. Check for simple issues:
   - Charging? -> Check reference
   - Contamination? -> Check Si 2p, C 1s
   |
5. Check for kinetic issues:
   - Time-series available? -> Analyze for beam damage
   |
6. Investigate further:
   - Ask about sample prep history
   - Ask about characterization data (LEED, STM)
   - Search literature for this surface/system
   |
7. Still doesn't match?
   - Consider alternative surface models
   - Consider novel chemistry not in database
```

## Example Diagnostic Dialogue

**User**: "My spectrum shows more intensity at lower binding energy than expected"

**Analysis steps**:
1. Verify which surface model was used for simulation
2. Ask about experimental conditions and sample prep history
3. Check for contamination indicators (C 1s, Si 2p)
4. Ask if time-series data is available to check stability
5. Consider whether alternative surface models might apply
6. Search literature for similar observations on this surface
7. Generate new simulation with revised parameters if needed

**Key questions to ask**:
- What was the sample preparation procedure?
- Do you have characterization data (LEED, STM)?
- Are the spectra stable over time?
- What pressure/temperature conditions were used?

## Current Limitations

- No automated spectrum fitting (qualitative comparison only)
- No uncertainty quantification
- Relies on user-provided descriptions of spectra
- Future: direct spectral data upload and quantitative comparison
