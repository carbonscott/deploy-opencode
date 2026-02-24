# Catalysis Fundamentals

## When to Use

This skill provides background knowledge for interpreting experiments and having informed conversations with researchers. Reference it when:

- Starting a conversation about a new experimental system
- Explaining why certain species appear in spectra
- Discussing reaction mechanisms
- Interpreting unexpected results

---

## Ambient-Pressure XPS (AP-XPS)

**What it is:** X-ray photoelectron spectroscopy performed at near-ambient pressures (mTorr to Torr range), allowing observation of surfaces under reactive gas environments.

**Why it matters:** Traditional XPS requires ultra-high vacuum, which means you can't see what surfaces look like under realistic reaction conditions. AP-XPS lets you watch chemistry happen in real-time.

**What you measure:** Core-level binding energies of atoms at/near the surface. Each chemical species has a characteristic binding energy based on its local environment.

**Key regions for catalysis:**
- **O 1s** (528-536 eV): Oxygen-containing species - atomic O, OH, H2O, carbonates, oxides
- **C 1s** (282-292 eV): Carbon species - CO, CO2, carbonates, adventitious carbon
- **Metal core levels**: Oxidation state of the catalyst

---

## Water Chemistry on Metal Surfaces

Water dissociation on metals is a fundamental process in electrocatalysis. The key species are:

| Species | Notation | Description |
|---------|----------|-------------|
| Molecular water | H2O* | Intact water adsorbed on surface |
| Hydroxyl | OH* | Water that lost one H |
| Atomic oxygen | O* | Fully dissociated oxygen |
| H-bonded complexes | OH-H2O*, O-H2O* | Hydrogen-bonded networks |
| Multilayer water | H2O(ice) | Ice-like overlayers at high coverage |

**Key reaction:** O* + H2O -> 2OH* (extremely fast on most metals)

This means if you have any atomic oxygen on the surface and expose it to water, it immediately converts to hydroxyl. Pure O* is rarely seen under water-rich conditions.

---

## CO2 Reduction Reaction (CO2RR)

Converting CO2 to useful products (CO, formate, methanol, ethanol, ethylene) using electrochemistry.

**Key surfaces:** Cu (makes multi-carbon products), Ag and Au (make CO), Sn and Bi (make formate)

**Relevant XPS species:**
- CO2* (physisorbed or chemisorbed)
- CO* (key intermediate on path to C2+ products)
- Carbonate (CO3 2-, surface poison or intermediate)
- Various CHxO intermediates

**Oxide-derived catalysts:** Many high-performing catalysts are prepared by oxidizing then reducing the metal, leaving a "reconstructed" or defective surface with unique activity.

---

## Oxygen Evolution Reaction (OER)

Splitting water to make O2 (the anode reaction in water electrolysis).

**Key surfaces:** IrO2, RuO2, NiFe oxides, perovskites

**Relevant species:**
- Metal-OH
- Metal-O
- Metal-OOH (hydroperoxide intermediate)
- Lattice oxygen participation

---

## Interpreting XPS Spectra

**Peak positions:** Each species appears at a characteristic binding energy. Higher oxidation states generally shift to higher binding energy.

**Peak intensities:** Proportional to surface concentration (with caveats about depth sensitivity and cross-sections).

**Peak shapes:**
- Symmetric Gaussian/Lorentzian for simple cases
- Asymmetric for metallic states
- Multiple components indicate multiple species

**What to look for:**
1. Which peaks are present? -> What species are on the surface?
2. Relative intensities -> What's the dominant species?
3. Shifts from expected positions -> Electronic effects, different sites?
4. Changes over time or with conditions -> Dynamic evolution

---

## Common Pitfalls

**Beam damage:** X-rays can modify the surface. Check by comparing spectra at same spot over time.

**Adventitious carbon:** Random carbon contamination appears ~284-285 eV. Almost always present.

**Charging:** Insulating samples can accumulate charge, shifting all peaks. Check reference peaks.

**Depth averaging:** XPS probes ~1-3 nm. Surface and subsurface species contribute differently.

---

## Unit Conventions

- **Binding energy:** eV (electron volts)
- **Pressure:** Torr or mbar (1 Torr ~ 1.33 mbar)
- **Temperature:** Usually Celsius in conversation, Kelvin in calculations
- **Coverage:** Monolayers (ML) or fractional (0-1)
- **Activation energy:** eV or kJ/mol (1 eV = 96.5 kJ/mol)
