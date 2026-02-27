#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
Refine diffraction ring parameters using spatial-calib-xray's optimizer.

Takes initial guesses (center + radii) from elsd_detect.py JSON output or
explicit CLI args, and fits them to sub-pixel precision.

Usage:
    uv run scripts/find_rings.py IMAGE.npy --from-json rings.json --fit --viz-fitted /tmp/fitted.png -o fitted.json
    uv run scripts/find_rings.py IMAGE.npy --center-x 883 --center-y 876 --radii 157,309,461,613,771 --fit
"""

import argparse
import json
import sys
import numpy as np


def run_fitting(data, valid, cx, cy, radii, num_samples=1000):
    """
    Refine center and radii using spatial-calib-xray's OptimizeConcentricCircles.

    Returns (fitted_cx, fitted_cy, fitted_radii, fit_result, model) or raises on import error.
    """
    try:
        from spatial_calib_xray.model import OptimizeConcentricCircles
    except ImportError:
        raise ImportError(
            "spatial-calib-xray is not installed. Install with:\n"
            "  uv pip install git+https://github.com/carbonscott/spatial-calib-xray.git"
        )

    # Normalize over valid pixels only (critical for multi-panel detectors)
    valid_pixels = data[valid]
    img_norm = (data - np.mean(valid_pixels)) / np.std(valid_pixels)

    model = OptimizeConcentricCircles(cx=cx, cy=cy, r=radii, num=num_samples)
    res = model.fit(img_norm)

    # Extract refined parameters
    fitted_cx = res.params['cx'].value
    fitted_cy = res.params['cy'].value
    fitted_radii = [res.params[f'r{i}'].value for i in range(len(radii))]

    return fitted_cx, fitted_cy, fitted_radii, res, model


def save_visualization(data, valid, cx, cy, rings, output_path, color_override=None):
    """Save a PNG with detected rings overlaid on the image."""
    from PIL import Image, ImageDraw

    pos = data[valid]
    vmax = np.percentile(pos, 99) if len(pos) > 0 else 1
    d_clip = np.clip(data, 0, vmax)
    d_norm = (d_clip / vmax * 255).astype(np.uint8) if vmax > 0 else np.zeros_like(d_clip, dtype=np.uint8)
    img = Image.fromarray(d_norm, mode='L').convert('RGB')
    draw = ImageDraw.Draw(img)

    for ring in rings:
        r = ring['radius']
        color = color_override or (0, 255, 0)

        for dr in np.arange(-1.0, 1.5, 0.5):
            bbox = [cx - r - dr, cy - r - dr, cx + r + dr, cy + r + dr]
            draw.ellipse(bbox, outline=color)

        lx = cx + r * 0.707 + 4
        ly = cy - r * 0.707 - 12
        h_img, w_img = data.shape
        if 0 < lx < w_img - 30 and 0 < ly < h_img:
            draw.text((lx, ly), f"{r:.1f}", fill=color)

    img.save(output_path)


def main():
    parser = argparse.ArgumentParser(
        description="Refine diffraction ring parameters using spatial-calib-xray"
    )
    parser.add_argument("input", help="Path to .npy file (2D detector image)")
    parser.add_argument("-o", "--output", help="Output JSON file with refined parameters")

    # Input mode: either --from-json or explicit --center-x/--center-y/--radii
    input_group = parser.add_mutually_exclusive_group(required=True)
    input_group.add_argument("--from-json", help="JSON file from elsd_detect.py")
    input_group.add_argument("--center-x", type=float,
                             help="Initial center x (use with --center-y and --radii)")

    parser.add_argument("--center-y", type=float, help="Initial center y")
    parser.add_argument("--radii", help="Comma-separated radii in pixels (e.g. 157,309,461)")
    parser.add_argument("--fit", action="store_true",
                        help="Run spatial-calib-xray optimizer")
    parser.add_argument("--num-samples", type=int, default=1000,
                        help="Sample points per circle for fitting (default: 1000)")
    parser.add_argument("--viz-fitted", help="Output PNG with fitted circles in green")
    args = parser.parse_args()

    # Load image
    data = np.load(args.input).astype(np.float64)
    if data.ndim != 2:
        print(f"Error: expected 2D array, got shape {data.shape}", file=sys.stderr)
        sys.exit(1)
    h, w = data.shape
    valid = data > 0
    print(f"Image: {args.input} ({w}x{h})", file=sys.stderr)

    # Parse input parameters
    if args.from_json:
        with open(args.from_json) as f:
            det = json.load(f)
        cx = det["center_x"]
        cy = det["center_y"]
        radii = det["radii"]
        if cx is None or cy is None or len(radii) == 0:
            print("Error: JSON has no valid center or radii.", file=sys.stderr)
            sys.exit(1)
    else:
        if args.center_y is None or args.radii is None:
            print("Error: --center-x requires --center-y and --radii", file=sys.stderr)
            sys.exit(1)
        cx = args.center_x
        cy = args.center_y
        radii = [float(r.strip()) for r in args.radii.split(",")]

    print(f"Initial center: cx={cx:.1f}, cy={cy:.1f}", file=sys.stderr)
    print(f"Initial radii:  {radii}", file=sys.stderr)

    result = {
        "image": args.input,
        "center_x": cx,
        "center_y": cy,
        "radii": radii,
    }

    # Run fitting
    if args.fit:
        if len(radii) < 2:
            print(f"Warning: only {len(radii)} radius/radii, need at least 2 for fitting. "
                  "Skipping --fit.", file=sys.stderr)
        else:
            try:
                fitted_cx, fitted_cy, fitted_radii, fit_res, fit_model = run_fitting(
                    data, valid, cx, cy, radii, num_samples=args.num_samples
                )

                center_shift = np.sqrt((fitted_cx - cx)**2 + (fitted_cy - cy)**2)
                bad_radii = any(r <= 0 for r in fitted_radii)
                if center_shift > 50 or bad_radii:
                    print(f"\nWarning: fit produced suspect results "
                          f"(center shifted {center_shift:.1f} px, "
                          f"negative radii: {bad_radii}). "
                          "Returning initial guesses only.", file=sys.stderr)
                    print("", file=sys.stderr)
                    fit_model.report_fit(fit_res)
                else:
                    result['fitted_center_x'] = round(fitted_cx, 4)
                    result['fitted_center_y'] = round(fitted_cy, 4)
                    result['fitted_radii'] = [round(r, 4) for r in fitted_radii]
                    print(f"\nFitted center: cx={fitted_cx:.4f}, cy={fitted_cy:.4f}",
                          file=sys.stderr)
                    print(f"Fitted radii:  {[f'{r:.2f}' for r in fitted_radii]}",
                          file=sys.stderr)
                    print(f"Delta center:  dx={fitted_cx - cx:.2f}, dy={fitted_cy - cy:.2f}",
                          file=sys.stderr)
                    print("", file=sys.stderr)
                    fit_model.report_fit(fit_res)

                    if args.viz_fitted:
                        fitted_rings = [{'radius': r} for r in fitted_radii]
                        save_visualization(data, valid, fitted_cx, fitted_cy,
                                           fitted_rings, args.viz_fitted,
                                           color_override=(0, 255, 0))
                        print(f"Saved: {args.viz_fitted}", file=sys.stderr)
            except ImportError as e:
                print(f"Error: {e}", file=sys.stderr)
                sys.exit(1)
            except Exception as e:
                print(f"Warning: fitting did not converge: {e}", file=sys.stderr)
                print("Returning initial guesses only.", file=sys.stderr)

    # Output
    json_str = json.dumps(result, indent=2)
    if args.output:
        with open(args.output, 'w') as f:
            f.write(json_str)
        print(f"Saved: {args.output}", file=sys.stderr)
    else:
        print(json_str)


if __name__ == "__main__":
    main()
