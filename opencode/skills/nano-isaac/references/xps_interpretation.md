# XPS Data Interpretation Guide

## Common Core Level Binding Energies

| Element | Core Level | Binding Energy (eV) | Notes |
|---------|------------|---------------------|-------|
| C | 1s | 284.8 | Adventitious carbon reference |
| O | 1s | 530-534 | Metal oxides ~530, organic ~532 |
| N | 1s | 397-403 | Nitride ~397, organic ~400 |
| S | 2p | 162-170 | Sulfide ~162, sulfate ~168 |
| Ag | 3d5/2 | 368.2 | Metallic silver |
| Au | 4f7/2 | 84.0 | Metallic gold |
| Pt | 4f7/2 | 71.2 | Metallic platinum |
| Pd | 3d5/2 | 335.4 | Metallic palladium |
| Cu | 2p3/2 | 932.6 | Metallic copper |
| Fe | 2p3/2 | 706.8 | Metallic iron |
| Ni | 2p3/2 | 852.7 | Metallic nickel |
| Ti | 2p3/2 | 453.8 | Metallic titanium |
| Si | 2p | 99.3 | Elemental silicon |

## Chemical Shift Interpretation

Chemical shifts indicate oxidation state and bonding environment:
- Higher binding energy -> more positive oxidation state
- Lower binding energy -> more negative/metallic state

Example O 1s interpretation:
- 529-530 eV: Metal oxide (M-O)
- 531-532 eV: Hydroxide (M-OH), carbonyl (C=O)
- 533-534 eV: Adsorbed water, organic C-O

## Background Subtraction Methods

### Shirley Background
Most common for XPS. Iterative calculation based on peak area.

### Linear Background
Simple but can underestimate peak areas.

### Tougaard Background
Physically motivated, accounts for inelastic scattering.

## Peak Fitting Basics

Common line shapes:
- **Gaussian**: Instrument broadening
- **Lorentzian**: Natural lifetime broadening
- **Voigt**: Convolution of Gaussian and Lorentzian
- **Doniach-Sunjic**: Asymmetric peaks for metals

Spin-orbit splitting ratios:
- p levels: 1:2 (p1/2:p3/2)
- d levels: 2:3 (d3/2:d5/2)
- f levels: 3:4 (f5/2:f7/2)

## Quantification

Atomic percentage calculation:
```
At% = (Ipeak / RSF) / sum(Ii / RSFi) * 100
```

Where RSF = Relative Sensitivity Factor (instrument-dependent)

## Survey vs High-Resolution Scans

- **Survey scan**: Wide energy range (0-1200 eV), element identification
- **High-resolution**: Narrow range around specific peaks, chemical state analysis

## Data Quality Checks

1. Check C 1s position for charging (should be ~284.8 eV)
2. Verify Auger parameter for chemical state
3. Compare peak ratios to expected stoichiometry
4. Check for satellite peaks (shake-up, plasmon loss)

## Common Artifacts

- **Charging**: Shifts all peaks to higher BE, use flood gun or reference
- **X-ray satellites**: Ghost peaks from non-monochromated sources
- **Differential charging**: Peak broadening on insulators
- **Beam damage**: Changes in peak shape/position during acquisition
