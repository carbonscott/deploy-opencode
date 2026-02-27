#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Detect diffraction rings in X-ray detector images using ELSD.

ELSD (Ellipse and Line Segment Detector, ECCV 2012) finds arc fragments
in 2D image space without needing a center guess.  Post-processing
(sample arc points → optimize center → radial histogram peaks) yields
center + ring radii suitable for spatial-calib-xray fitting.

Usage:
    uv run scripts/elsd_detect.py IMAGE.npy -o rings.json --viz /tmp/overlay.png
    uv run scripts/elsd_detect.py IMAGE.npy --clip-low 2 --clip-high 99 --scale log1p
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np


# ---------------------------------------------------------------------------
# 1. ELSD binary management
# ---------------------------------------------------------------------------

def ensure_elsd_binary(elsd_dir):
    """Check for ELSD binary; auto-compile if missing.

    Tries ``-llapack -lblas`` first (standard Linux), falls back to
    versioned ``.so.3`` paths (SLAC SDF workaround).

    Returns path to the ``elsd`` executable.
    """
    binary = os.path.join(elsd_dir, "elsd")
    if os.path.isfile(binary) and os.access(binary, os.X_OK):
        return binary

    srcs = "elsd.c valid_curve.c process_curve.c process_line.c write_svg.c"
    src_files = srcs.split()
    for f in src_files:
        if not os.path.isfile(os.path.join(elsd_dir, f)):
            raise FileNotFoundError(f"ELSD source file missing: {os.path.join(elsd_dir, f)}")

    # Try standard link flags first
    cmd_std = f"cc -o elsd {srcs} -llapack -lblas -lm"
    result = subprocess.run(cmd_std, shell=True, cwd=elsd_dir,
                            capture_output=True, text=True)
    if result.returncode == 0:
        print("Compiled ELSD with -llapack -lblas", file=sys.stderr)
        return binary

    # Fallback: versioned .so paths (SLAC SDF)
    cmd_sdf = (f"cc -o elsd {srcs} "
               "/usr/lib64/liblapack.so.3 /usr/lib64/libblas.so.3 -lm")
    result = subprocess.run(cmd_sdf, shell=True, cwd=elsd_dir,
                            capture_output=True, text=True)
    if result.returncode == 0:
        print("Compiled ELSD with versioned .so paths", file=sys.stderr)
        return binary

    raise RuntimeError(
        f"Failed to compile ELSD.\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )


# ---------------------------------------------------------------------------
# 2. Preprocessing: npy → 8-bit PGM
# ---------------------------------------------------------------------------

def preprocess_npy_to_pgm(npy_path, pgm_path, clip_low=2, clip_high=99,
                           scale="log1p", gap_fill=False):
    """Load .npy → scale → percentile clip → 8-bit PGM.

    Args:
        npy_path: Path to 2D .npy detector image.
        pgm_path: Output P5 PGM path.
        clip_low: Lower percentile for contrast clipping (of nonzero pixels).
        clip_high: Upper percentile for contrast clipping.
        scale: Intensity scaling — ``"log1p"`` or ``"linear"``.
        gap_fill: If True, fill zero/negative pixels with median of valid pixels.

    Returns:
        (img_raw, img_8bit) — original float array and preprocessed uint8 array.
    """
    img = np.load(npy_path).astype(np.float64)
    if img.ndim != 2:
        raise ValueError(f"Expected 2D array, got shape {img.shape}")
    img_raw = img.copy()

    # Clip negatives
    img = np.clip(img, 0, None)

    # Scale
    if scale == "log1p":
        img = np.log1p(img)
    elif scale != "linear":
        raise ValueError(f"Unknown scale: {scale!r}")

    # Percentile clipping on nonzero pixels
    nonzero = img[img > 0]
    if len(nonzero) == 0:
        raise ValueError("Image has no positive pixels")
    p_low, p_high = np.percentile(nonzero, [clip_low, clip_high])
    img = np.clip(img, p_low, p_high)
    img = (img - p_low) / (p_high - p_low)

    # Optional gap fill
    if gap_fill:
        gap_mask = img_raw <= 0
        img[gap_mask] = np.median(img[~gap_mask])

    # 8-bit
    img_8bit = (img * 255).astype(np.uint8)

    # Write P5 PGM
    h, w = img_8bit.shape
    with open(pgm_path, "wb") as f:
        f.write(f"P5\n{w} {h}\n255\n".encode())
        f.write(img_8bit.tobytes())

    return img_raw, img_8bit


# ---------------------------------------------------------------------------
# 3. Run ELSD
# ---------------------------------------------------------------------------

def run_elsd(binary, pgm_path, work_dir=None):
    """Run ELSD binary on a PGM file.

    ELSD writes ``ellipses.txt`` to its cwd, so we copy the PGM into a
    temporary directory and run there.

    Returns:
        Path to ``ellipses.txt``.
    """
    if work_dir is None:
        work_dir = tempfile.mkdtemp(prefix="elsd_")

    pgm_basename = os.path.basename(pgm_path)
    work_pgm = os.path.join(work_dir, pgm_basename)
    if os.path.abspath(pgm_path) != os.path.abspath(work_pgm):
        shutil.copy2(pgm_path, work_pgm)

    result = subprocess.run(
        [binary, pgm_basename],
        cwd=work_dir, capture_output=True, text=True, timeout=120,
    )
    if result.returncode != 0:
        raise RuntimeError(f"ELSD failed:\n{result.stderr}")

    print(result.stdout.strip(), file=sys.stderr)

    ell_path = os.path.join(work_dir, "ellipses.txt")
    if not os.path.isfile(ell_path):
        raise FileNotFoundError(f"ELSD did not produce ellipses.txt in {work_dir}")
    return ell_path


# ---------------------------------------------------------------------------
# 4. Parse ellipses.txt
# ---------------------------------------------------------------------------

def parse_ellipses(path):
    """Parse ELSD 7-column ellipses.txt.

    Each line: cx cy a b theta ang_start ang_end
    (all floats; theta and angles in radians)

    Returns:
        List of dicts with keys: cx, cy, a, b, theta, ang_start, ang_end.
    """
    arcs = []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) != 7:
                continue
            vals = [float(x) for x in parts]
            arcs.append({
                "cx": vals[0], "cy": vals[1],
                "a": vals[2], "b": vals[3],
                "theta": vals[4],
                "ang_start": vals[5], "ang_end": vals[6],
            })
    return arcs


# ---------------------------------------------------------------------------
# 5. Sample points from arcs
# ---------------------------------------------------------------------------

def sample_points_from_arcs(arcs, img_shape, min_r=5, max_r=1500):
    """Sample (x, y) points along each detected arc.

    Applies the ellipse parametric equation with rotation, filters points
    outside image bounds and arcs with extreme radii.

    Returns:
        (Nx2 numpy array of (x, y) points, n_arcs_used).
    """
    h, w = img_shape
    all_points = []

    n_used = 0
    for arc in arcs:
        a, b = arc["a"], arc["b"]
        if a < min_r or a > max_r:
            continue

        n_used += 1
        xc, yc = arc["cx"], arc["cy"]
        rot = arc["theta"]
        ang_start, ang_end = arc["ang_start"], arc["ang_end"]

        # 2 points per degree of arc
        arc_span = abs(ang_end - ang_start)
        n_pts = max(3, int(np.degrees(arc_span) * 2))
        thetas = np.linspace(ang_start, ang_end, n_pts)

        cos_rot, sin_rot = np.cos(rot), np.sin(rot)
        for t in thetas:
            px = a * np.cos(t)
            py = b * np.sin(t)
            px_rot = px * cos_rot - py * sin_rot + xc
            py_rot = px * sin_rot + py * cos_rot + yc
            if 0 <= px_rot < w and 0 <= py_rot < h:
                all_points.append([px_rot, py_rot])

    if len(all_points) == 0:
        return np.empty((0, 2)), 0
    return np.array(all_points), n_used


def _arc_center_hint(arcs, img_shape, min_r=30, max_r=800):
    """Compute a robust initial center hint from arc center coordinates.

    Uses the median of arc centers (filtered to reasonable radii) as a
    starting point for the grid search.  Falls back to image center.
    """
    h, w = img_shape
    centers = []
    for arc in arcs:
        a = arc["a"]
        if a < min_r or a > max_r:
            continue
        cx, cy = arc["cx"], arc["cy"]
        # Arc center should be within image bounds (generous margin)
        if -w * 0.5 < cx < w * 1.5 and -h * 0.5 < cy < h * 1.5:
            centers.append([cx, cy])
    if len(centers) < 3:
        return w / 2.0, h / 2.0
    centers = np.array(centers)
    return float(np.median(centers[:, 0])), float(np.median(centers[:, 1]))


# ---------------------------------------------------------------------------
# 6. Fit center
# ---------------------------------------------------------------------------

def _score_center(cx, cy, points, max_r=900, bin_width=2):
    """Score a candidate center by sharpness of radial histogram peaks.

    Score = sum of squared peak heights in the radial histogram.
    """
    from scipy.ndimage import uniform_filter1d
    from scipy.signal import find_peaks

    dx = points[:, 0] - cx
    dy = points[:, 1] - cy
    radii = np.sqrt(dx**2 + dy**2)

    bins = np.arange(0, max_r, bin_width)
    hist, bin_edges = np.histogram(radii, bins=bins)
    hist_smooth = uniform_filter1d(hist.astype(float), size=3)

    peaks, props = find_peaks(hist_smooth, height=2, distance=8, prominence=1.0)
    if len(peaks) == 0:
        return 0.0
    peak_heights = hist_smooth[peaks]
    return float(np.sum(peak_heights**2))


def fit_center(points, img_shape, arcs=None):
    """Find beam center via grid search + Nelder-Mead optimization.

    Uses the median of arc centers as the initial hint for the grid search,
    then searches within +/- 250 px of that hint.  Nelder-Mead refines
    to sub-pixel precision.

    Returns:
        (cx, cy) as floats.
    """
    from scipy.optimize import minimize

    h, w = img_shape

    # Get starting hint from arc centers (or image center as fallback)
    if arcs is not None:
        hint_cx, hint_cy = _arc_center_hint(arcs, img_shape)
    else:
        hint_cx, hint_cy = w / 2.0, h / 2.0

    # Grid search: +/- 250 px around hint, step 20
    radius = 250
    step = 20
    x_lo = max(0, int(hint_cx - radius))
    x_hi = min(w, int(hint_cx + radius))
    y_lo = max(0, int(hint_cy - radius))
    y_hi = min(h, int(hint_cy + radius))

    best_score = 0
    best_cx, best_cy = hint_cx, hint_cy
    for cx in range(x_lo, x_hi, step):
        for cy in range(y_lo, y_hi, step):
            s = _score_center(cx, cy, points)
            if s > best_score:
                best_score = s
                best_cx, best_cy = float(cx), float(cy)

    print(f"Arc center hint: cx={hint_cx:.0f}, cy={hint_cy:.0f}", file=sys.stderr)
    print(f"Grid search best: cx={best_cx:.0f}, cy={best_cy:.0f}, "
          f"score={best_score:.0f}", file=sys.stderr)

    # Nelder-Mead refinement
    def neg_score(params):
        return -_score_center(params[0], params[1], points)

    result = minimize(neg_score, [best_cx, best_cy], method="Nelder-Mead",
                      options={"xatol": 0.5, "fatol": 0.1, "maxiter": 200})
    cx_opt, cy_opt = result.x
    print(f"Nelder-Mead refined: cx={cx_opt:.1f}, cy={cy_opt:.1f}", file=sys.stderr)

    return float(cx_opt), float(cy_opt)


# ---------------------------------------------------------------------------
# 7. Extract ring radii
# ---------------------------------------------------------------------------

def extract_ring_radii(points, cx, cy, min_peak_score=50, max_rings=20,
                       max_r=900, bin_width=2):
    """Extract ring radii from the radial histogram of sampled points.

    Args:
        points: Nx2 array of (x, y) arc sample points.
        cx, cy: Beam center.
        min_peak_score: Minimum histogram peak height to keep.
        max_rings: Maximum number of rings to return.

    Returns:
        List of dicts: {radius, score, n_points}.
    """
    from scipy.ndimage import uniform_filter1d
    from scipy.signal import find_peaks

    dx = points[:, 0] - cx
    dy = points[:, 1] - cy
    radii = np.sqrt(dx**2 + dy**2)

    bins = np.arange(0, max_r, bin_width)
    hist, bin_edges = np.histogram(radii, bins=bins)
    bin_centers = (bin_edges[:-1] + bin_edges[1:]) / 2.0
    hist_smooth = uniform_filter1d(hist.astype(float), size=3)

    peaks, props = find_peaks(hist_smooth, height=2, distance=8, prominence=1.0)
    if len(peaks) == 0:
        return []

    rings = []
    for idx in peaks:
        score = float(hist_smooth[idx])
        r = float(bin_centers[idx])
        # Count points within +/- 1 bin of this radius
        n_pts = int(np.sum((radii >= r - bin_width) & (radii < r + bin_width)))
        rings.append({"radius": round(r, 1), "score": round(score, 1),
                       "n_points": n_pts})

    # Filter by score, sort by score descending, limit count
    rings = [r for r in rings if r["score"] >= min_peak_score]
    rings.sort(key=lambda r: r["score"], reverse=True)
    rings = rings[:max_rings]
    # Re-sort by radius for display
    rings.sort(key=lambda r: r["radius"])
    return rings


# ---------------------------------------------------------------------------
# 8. Save overlay visualization
# ---------------------------------------------------------------------------

def save_overlay(npy_path, cx, cy, rings, output_path):
    """Save a PNG overlay: log-scaled image with color-coded ring circles.

    Uses the original .npy (not the 8-bit PGM) so the agent sees real data.
    """
    from PIL import Image, ImageDraw

    img = np.load(npy_path).astype(np.float64)
    h, w = img.shape

    # Log-scale for display
    img_disp = np.clip(img, 0, None)
    img_disp = np.log1p(img_disp)
    nonzero = img_disp[img_disp > 0]
    if len(nonzero) > 0:
        p99 = np.percentile(nonzero, 99)
        img_disp = np.clip(img_disp, 0, p99)
        img_disp = (img_disp / p99 * 255).astype(np.uint8)
    else:
        img_disp = np.zeros((h, w), dtype=np.uint8)

    pil_img = Image.fromarray(img_disp, mode="L").convert("RGB")
    draw = ImageDraw.Draw(pil_img)

    # Color-code by score
    colors = [(255, 50, 50), (255, 165, 0), (0, 200, 255),
              (50, 255, 50), (255, 255, 0), (255, 100, 255)]

    for i, ring in enumerate(rings):
        r = ring["radius"]
        color = colors[i % len(colors)]
        for dr in np.arange(-1.0, 1.5, 0.5):
            bbox = [cx - r - dr, cy - r - dr, cx + r + dr, cy + r + dr]
            draw.ellipse(bbox, outline=color)

        # Label
        lx = cx + r * 0.707 + 4
        ly = cy - r * 0.707 - 12
        if 0 < lx < w - 40 and 0 < ly < h:
            draw.text((lx, ly), f"r={ring['radius']:.0f}", fill=color)

    # Center crosshair
    arm = 15
    draw.line([(cx - arm, cy), (cx + arm, cy)], fill=(255, 255, 255), width=2)
    draw.line([(cx, cy - arm), (cx, cy + arm)], fill=(255, 255, 255), width=2)

    pil_img.save(output_path)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(
        description="Detect diffraction rings using ELSD arc detection"
    )
    parser.add_argument("input", help="Path to .npy file (2D detector image)")
    parser.add_argument("-o", "--output", help="Output JSON file")
    parser.add_argument("--viz", help="Output PNG overlay visualization")
    parser.add_argument("--clip-low", type=float, default=2,
                        help="Lower percentile for PGM clipping (default: 2)")
    parser.add_argument("--clip-high", type=float, default=99,
                        help="Upper percentile for PGM clipping (default: 99)")
    parser.add_argument("--scale", default="log1p", choices=["log1p", "linear"],
                        help="Intensity scaling (default: log1p)")
    parser.add_argument("--gap-fill", action="store_true",
                        help="Fill detector gaps with median before ELSD")
    parser.add_argument("--min-peak-score", type=float, default=50,
                        help="Minimum histogram peak score to keep (default: 50)")
    parser.add_argument("--max-rings", type=int, default=20,
                        help="Maximum number of rings (default: 20)")
    parser.add_argument("--elsd-binary", help="Path to precompiled ELSD binary")
    args = parser.parse_args()

    # Resolve ELSD binary
    if args.elsd_binary:
        binary = args.elsd_binary
    else:
        elsd_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "elsd")
        binary = ensure_elsd_binary(elsd_dir)

    # Preprocess
    with tempfile.TemporaryDirectory(prefix="elsd_work_") as work_dir:
        pgm_path = os.path.join(work_dir, "image.pgm")
        img_raw, img_8bit = preprocess_npy_to_pgm(
            args.input, pgm_path,
            clip_low=args.clip_low, clip_high=args.clip_high,
            scale=args.scale, gap_fill=args.gap_fill,
        )
        h, w = img_raw.shape
        print(f"Image: {args.input} ({w}x{h})", file=sys.stderr)

        # Run ELSD
        ell_path = run_elsd(binary, pgm_path, work_dir=work_dir)
        arcs = parse_ellipses(ell_path)
        print(f"ELSD found {len(arcs)} arcs", file=sys.stderr)

    if len(arcs) == 0:
        print("No arcs detected — cannot find rings.", file=sys.stderr)
        result = {
            "image": args.input, "method": "elsd",
            "center_x": None, "center_y": None,
            "radii": [], "rings": [],
            "elsd_stats": {"n_arcs_total": 0, "n_arcs_used": 0,
                           "n_points_sampled": 0},
        }
    else:
        # Sample points from arcs
        points, n_arcs_used = sample_points_from_arcs(arcs, (h, w))
        n_points = len(points)
        print(f"Sampled {n_points} points from {n_arcs_used}/{len(arcs)} arcs",
              file=sys.stderr)

        if n_points < 10:
            print("Too few sampled points — cannot fit center.", file=sys.stderr)
            result = {
                "image": args.input, "method": "elsd",
                "center_x": None, "center_y": None,
                "radii": [], "rings": [],
                "elsd_stats": {"n_arcs_total": len(arcs),
                               "n_arcs_used": n_arcs_used,
                               "n_points_sampled": n_points},
            }
        else:
            # Fit center
            cx, cy = fit_center(points, (h, w), arcs=arcs)

            # Extract ring radii
            rings = extract_ring_radii(points, cx, cy,
                                       min_peak_score=args.min_peak_score,
                                       max_rings=args.max_rings)

            print(f"Center: cx={cx:.1f}, cy={cy:.1f}", file=sys.stderr)
            print(f"Found {len(rings)} rings:", file=sys.stderr)
            for i, ring in enumerate(rings):
                print(f"  Ring {i+1}: r={ring['radius']:.0f}, "
                      f"score={ring['score']:.0f}, n_pts={ring['n_points']}",
                      file=sys.stderr)

            result = {
                "image": args.input,
                "method": "elsd",
                "center_x": round(cx, 1),
                "center_y": round(cy, 1),
                "radii": [r["radius"] for r in rings],
                "rings": rings,
                "elsd_stats": {
                    "n_arcs_total": len(arcs),
                    "n_arcs_used": n_arcs_used,
                    "n_points_sampled": n_points,
                },
            }

    # Output JSON
    json_str = json.dumps(result, indent=2)
    if args.output:
        with open(args.output, "w") as f:
            f.write(json_str)
        print(f"Saved: {args.output}", file=sys.stderr)
    else:
        print(json_str)

    # Visualization
    if args.viz and result["center_x"] is not None and len(result["rings"]) > 0:
        save_overlay(args.input, result["center_x"], result["center_y"],
                     result["rings"], args.viz)
        print(f"Saved: {args.viz}", file=sys.stderr)


if __name__ == "__main__":
    main()
