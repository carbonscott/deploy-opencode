# Integration with spatial-calib-xray

## What the tool does

`spatial-calib-xray` (https://github.com/carbonscott/spatial-calib-xray) fits concentric circles
to X-ray diffraction ring patterns for detector geometry calibration. It uses Levenberg-Marquardt
least-squares optimization (via `lmfit`) to refine initial parameter guesses to subpixel accuracy.

## What it needs from you

`OptimizeConcentricCircles` requires initial guesses for:
- **cx**: beam center x (pixels, along axis=1 in numpy)
- **cy**: beam center y (pixels, along axis=0 in numpy)
- **r**: list of radii for each concentric circle (pixels)

```python
from spatial_calib_xray.model import OptimizeConcentricCircles

model = OptimizeConcentricCircles(cx=cx, cy=cy, r=radii, num=1000)
res = model.fit(img_normalized)
model.report_fit(res)
```

## How the optimizer works

The residual function samples pixel values along each circle and computes:
```
residual = sampled_pixel_values - image_max
```
It minimizes this residual, meaning it tries to place circles on the **brightest** pixels.

### Critical implication for ring selection

The optimizer assumes rings are **bright intensity peaks**. This means:

1. **Rings must be bright relative to surroundings** — faint rings with low signal-to-noise
   will contribute noisy residuals that may destabilize the fit.

2. **Panel gaps will confuse the optimizer** — if a circle passes through detector panel gaps
   (dark pixels), the optimizer sees those as "far from maximum" and may distort the fit.
   For multi-panel detectors (CSPAD, ePix10k2M), prefer rings that have good angular coverage
   across active panels.

3. **A few strong rings beat many weak ones** — 3-5 clean rings typically converge better than
   10+ rings where half are noisy.

## Image preprocessing

The tool expects a normalized image:
```python
img = np.load("detector_mean.npy")
img = (img - np.mean(img)) / np.std(img)
```

## Using find_rings.py output as initial guesses

The `--fit` flag automates the full detection-to-fitting pipeline:

```bash
uv run scripts/find_rings.py IMAGE.npy --fit --for-fitting --viz rings.png -o rings.json
```

This runs `OptimizeConcentricCircles` on the recommended rings and adds
`fitted_center_x`, `fitted_center_y`, and `fitted_radii` to the JSON output.
Image normalization is done over valid pixels only (critical for multi-panel
detectors with large zero regions).

## Which rings to select — guidance

When reviewing `find_rings.py` output, think like an intern examining the image:

### Good rings for fitting
- **High fit_score** (>0.4): bright, prominent, well above background
- **Complete arcs**: the ring is visible around most of its circumference
- **Clean separation**: not blended with neighboring rings
- **On active detector area**: not crossing large panel gaps

### Bad rings for fitting
- **Faint outer rings**: low intensity, barely above noise — these add noise to the fit
- **Rings crossing panel gaps**: optimizer samples dark gap pixels and gets confused
- **Artifact rings**: features from panel edges, beamstop scatter, or detector artifacts
  that look ring-like in the radial profile but aren't true diffraction rings
- **Very inner rings** (near beamstop): may be partially occluded or distorted

### Rules of thumb
- Start with 3-5 strongest rings (highest fit_score)
- If the fit converges well, optionally add more rings for redundancy
- For multi-panel detectors, visually verify that selected rings have good panel coverage
- The optimizer is robust to ~10-20% error in initial radius and ~50px error in center
