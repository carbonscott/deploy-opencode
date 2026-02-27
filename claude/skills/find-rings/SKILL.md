---
name: find-rings
description: >
  Detect diffraction rings in X-ray detector images (.npy files) and provide
  initial parameter guesses (center + radii) for spatial-calib-xray's
  OptimizeConcentricCircles fitting. Use when users ask to find rings, detect
  diffraction rings, identify powder rings, provide calibration initial guesses,
  or prepare ring parameters for geometry fitting. Triggers on: diffraction rings,
  powder rings, ring detection, ring finding, calibration rings, find rings,
  concentric circles, initial guess, spatial calibration.
---

# Ring Detection for X-ray Diffraction Images

## Environment Setup

Every bash command must source the environment first:

```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/env.sh
```

The `find_rings_run` wrapper executes commands in the managed venv (numpy, Pillow, scipy, spatial-calib-xray).

Script locations:
- `/sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/scripts/elsd_detect.py` (ELSD detection)
- `/sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/scripts/find_rings.py` (fitting refinement)

## Quick Start

```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/env.sh

# Detect rings (ELSD-based)
find_rings_run python /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/scripts/elsd_detect.py IMAGE.npy --viz /tmp/overlay.png -o rings.json

# Refine with spatial-calib-xray optimizer
find_rings_run python /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/scripts/find_rings.py IMAGE.npy --from-json rings.json --fit --viz-fitted /tmp/fitted.png -o fitted.json
```

## Three-Stage Workflow

```
  Stage 0              Stage 1                    Stage 2
  --------             ----------                 ----------
  Render PNG  -->  ELSD Detection  -->  Precise Fitting
  Eye-test it      + Eye-test loop      + Eye-test fitted
  Rings visible?   Circles align?       Center shift OK?
       |                  |                    |
       No -> STOP          No -> RETRY           No -> Use initial
       Yes -> continue     (up to 4x)           Yes -> Done
```

## Stage 0: Image Assessment

Before running detection, render the image to see what you're working with.

**Inline rendering snippet** (run this via Bash tool):
```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/env.sh
find_rings_run python -c "
import numpy as np; from PIL import Image
img = np.load('IMAGE.npy').astype(float)
img = np.clip(img, 0, None); img = np.log1p(img)
nz = img[img > 0]; p99 = np.percentile(nz, 99)
img = np.clip(img, 0, p99); img = (img / p99 * 255).astype(np.uint8)
Image.fromarray(img).save('/tmp/assess.png')
"
```

Then **Read** `/tmp/assess.png` and assess:
- Are diffraction rings visible? (concentric arcs in the image)
- Is the image mostly noise, saturated, or blank?

**Decision:**
- Rings visible -> proceed to Stage 1
- No rings visible -> **stop honestly**. Tell the user:
  > "I examined the image and don't see clear diffraction rings. This could mean
  > the sample didn't diffract, the exposure was too short, or the detector was
  > misconfigured. Ring detection won't produce useful results on this image."

## Stage 1: ELSD Detection with Eye-Test Loop

Run the detection script:

```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/env.sh
find_rings_run python /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/scripts/elsd_detect.py IMAGE.npy --viz /tmp/overlay.png -o /tmp/rings.json
```

Then **Read** `/tmp/overlay.png` and assess: do the colored circles align with visible ring features?

### Quality Gates

| Metric                  | Good  | Retry | Fail |
|-------------------------|-------|-------|------|
| ELSD arcs found         | > 50  | 10-50 | < 10 |
| Strong peaks (score>50) | >= 3  | 1-2   | 0    |
| Center within image     | yes   | edge  | out  |

### Retry Strategy (up to 4 attempts)

If the initial run doesn't pass quality gates, try these parameter variants in order:

1. **Lower clipping** -- catches faint rings:
   `--clip-low 1 --clip-high 99.5`

2. **Linear scale** -- better for images without extreme dynamic range:
   `--scale linear --clip-low 5 --clip-high 98`

3. **Gap-filled** -- fills detector gaps with median (helps if gaps fragment arcs):
   `--gap-fill`

4. **Aggressive** -- all three combined:
   `--clip-low 1 --clip-high 99.5 --gap-fill`

After 4 failed attempts, **stop honestly** -- the image likely doesn't have detectable rings, or ELSD isn't suitable for it.

### Lower the score threshold only if needed

If the quality gate says "Retry" because you have 1-2 peaks with score > 50 but you can see more rings in the overlay, try lowering the threshold:
```bash
find_rings_run python /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/scripts/elsd_detect.py IMAGE.npy --min-peak-score 20 --viz /tmp/overlay.png -o /tmp/rings.json
```

## Stage 2: Precise Fitting

Once Stage 1 produces good initial guesses, refine them:

```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/env.sh
find_rings_run python /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/scripts/find_rings.py IMAGE.npy --from-json /tmp/rings.json --fit --viz-fitted /tmp/fitted.png -o /tmp/fitted.json
```

**Read** `/tmp/fitted.png` for final validation.

**Sanity checks:**
- Center shift < 50 px from initial guess (otherwise suspect)
- No negative radii
- Fitted circles should visually improve on initial guesses

## Fallback: Agent Orchestration

If `elsd_detect.py` itself fails (e.g. import errors, missing scipy), you can do the steps inline:

### 1. Build ELSD manually
```bash
cd /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/scripts/elsd && make && cd -
```

### 2. Convert to PGM
```bash
source /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/env.sh
find_rings_run python -c "
import numpy as np
img = np.load('IMAGE.npy').astype(float)
img = np.clip(img, 0, None); img = np.log1p(img)
nz = img[img > 0]; lo, hi = np.percentile(nz, [2, 99])
img = np.clip(img, lo, hi); img = (img - lo) / (hi - lo)
img8 = (img * 255).astype(np.uint8)
h, w = img8.shape
with open('/tmp/image.pgm', 'wb') as f:
    f.write(f'P5\n{w} {h}\n255\n'.encode()); f.write(img8.tobytes())
"
```

### 3. Run ELSD
```bash
cd /tmp && /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/scripts/elsd/elsd image.pgm && cd -
```

### 4. Parse ellipses.txt and fit
The output is 7 columns: `cx cy a b theta ang_start ang_end` (all floats, angles in radians). Sample points along arcs using the ellipse parametric equation with rotation, compute radial histogram from a candidate center, and pick peaks. See `elsd_detect.py` source for the exact algorithm.

## Script Reference

### `elsd_detect.py` -- ELSD-based ring detection

```
source /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/env.sh
find_rings_run python /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/scripts/elsd_detect.py IMAGE.npy [options]

Options:
  -o FILE              Output JSON with center + radii
  --viz FILE           Output PNG with ring overlay
  --clip-low FLOAT     Lower percentile for PGM clipping (default: 2)
  --clip-high FLOAT    Upper percentile for PGM clipping (default: 99)
  --scale {log1p,linear}  Intensity scaling (default: log1p)
  --gap-fill           Fill detector gaps with median
  --min-peak-score FLOAT  Minimum histogram peak score (default: 50)
  --max-rings INT      Maximum rings to return (default: 20)
  --elsd-binary PATH   Path to precompiled ELSD binary
```

**Output JSON:**
```json
{
  "image": "path.npy",
  "method": "elsd",
  "center_x": 883.0,
  "center_y": 876.0,
  "radii": [157, 309, 461, 613, 771],
  "rings": [{"radius": 157, "score": 146, "n_points": 52}, "..."],
  "elsd_stats": {"n_arcs_total": 166, "n_arcs_used": 47, "n_points_sampled": 8919}
}
```

### `find_rings.py` -- Fitting refinement

```
source /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/env.sh
find_rings_run python /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/scripts/find_rings.py IMAGE.npy --from-json rings.json [options]
find_rings_run python /sdf/group/lcls/ds/dm/apps/dev/tools/find-rings/scripts/find_rings.py IMAGE.npy --center-x CX --center-y CY --radii R1,R2,R3 [options]

Options:
  -o FILE              Output JSON with refined parameters
  --from-json FILE     JSON from elsd_detect.py (mutually exclusive with --center-x)
  --center-x FLOAT     Initial center x
  --center-y FLOAT     Initial center y
  --radii STR          Comma-separated radii
  --fit                Run spatial-calib-xray optimizer
  --num-samples INT    Samples per circle (default: 1000)
  --viz-fitted FILE    Output PNG with fitted circles in green
```

## Tuning Guide

| Problem | Fix |
|---------|-----|
| Too few arcs detected | Lower `--clip-low` (try 1), raise `--clip-high` (try 99.5) |
| Too many weak rings | Raise `--min-peak-score` (try 80-100) |
| Missing faint rings | Lower `--min-peak-score` (try 20-30) |
| Detector gaps fragmenting arcs | Add `--gap-fill` |
| Very low dynamic range image | Try `--scale linear` |
| Fitting diverges | Check initial guesses visually, remove suspect radii |

## Technical Notes

### ELSD Compilation
ELSD requires LAPACK and BLAS. On SLAC SDF, `-llapack` fails because dev symlinks are missing -- the makefile uses versioned `.so.3` paths as a workaround. The script auto-compiles on first run.

### Coordinate Space
ELSD uses image coordinates: x = column, y = row, origin at top-left. The `smooth=1` Gaussian downscaling (factor 0.8) is compensated by 1.25x coordinate scaling in the ELSD output, so `ellipses.txt` coordinates are in original image pixels.

### ELSD License
ELSD is licensed under AGPL v3 (see `scripts/elsd/COPYING`). The bundled source is unmodified from the original by Viorica Patraucean (ECCV 2012).

## Integration with spatial-calib-xray

See [references/spatial-calib-xray.md](references/spatial-calib-xray.md) for:
- How to feed results into `OptimizeConcentricCircles`
- Image normalization requirements
- Guidance on which rings to select vs skip for fitting

## Dependencies

Managed by the shared venv (numpy, Pillow, scipy, spatial-calib-xray). No user installation needed.
