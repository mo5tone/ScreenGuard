#!/usr/bin/env python3
"""Alignment-aware fidelity check for the feasibility measurement.

The in-app probe compares a fixed region of the pushed image against a fixed region of the
readback. That is honest but pessimistic: a display layer resamples (videoGravity = .resize), so a
one-or-two-pixel offset across high-contrast glyphs and a 1px grid produces a large mean error even
for a perfect reproduction. This script searches a small offset window and reports both numbers, so
the doc can state fidelity without overstating or understating it.

    Research/Scripts/fidelity_check.py <source.png> <capture.png>
"""
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required")

# The reference layer is the BOTTOM half of the window (see FeasibilityProbe).
WINDOW_REGION = (0.06, 0.58, 0.88, 0.37)


def crop(im, region):
    w, h = im.size
    return im.crop((int(region[0] * w), int(region[1] * h),
                    int((region[0] + region[2]) * w), int((region[1] + region[3]) * h)))


def mean_abs_error(a, b):
    """Mean absolute per-channel error, in 0-255 units."""
    pa, pb = a.load(), b.load()
    w, h = a.size
    total = 0
    count = 0
    for y in range(0, h, 2):
        for x in range(0, w, 2):
            ca, cb = pa[x, y], pb[x, y]
            total += (abs(ca[0] - cb[0]) + abs(ca[1] - cb[1]) + abs(ca[2] - cb[2])) / 3
            count += 1
    return total / count if count else -1


def main():
    source_path, capture_path = sys.argv[1], sys.argv[2]
    source = Image.open(source_path).convert("RGB")
    capture = Image.open(capture_path).convert("RGB")

    # The source image is the content for ONE layer, so map the window region into it.
    sx, sy, sw, sh = WINDOW_REGION
    source_region = (sx, sy * 2 - 1, sw, sh * 2)

    src = crop(source, source_region)
    cap = crop(capture, WINDOW_REGION)
    # Resample the source down to the capture's scale so sizes match.
    src_small = src.resize(cap.size, Image.LANCZOS)

    print(f"source {source.size} region {source_region} -> {src.size} -> resampled {src_small.size}")
    print(f"capture {capture.size} region {WINDOW_REGION} -> {cap.size}")

    zero = mean_abs_error(src_small, cap)
    print(f"\nmean abs channel error at zero offset : {zero:.2f}")

    best = (zero, 0, 0)
    for dy in range(-4, 5):
        for dx in range(-4, 5):
            shifted = Image.new("RGB", cap.size)
            shifted.paste(src_small, (dx, dy))
            err = mean_abs_error(shifted, cap)
            if err < best[0]:
                best = (err, dx, dy)
    print(f"best offset dx={best[1]} dy={best[2]}        : {best[0]:.2f}")
    print(f"improvement from alignment            : {zero - best[0]:.2f}")

    # Sanity: what does a solid-colour worst case look like, for scale?
    print("\nreference: mean abs error between two unrelated solid colours (black vs white) = 255.00")
    print("reference: a 1px misalignment across a hard edge can add 30-60 to the mean")


if __name__ == "__main__":
    main()
