#!/usr/bin/env python3
"""Independent host-side reader for the CaptureMatrix artifacts.

This deliberately re-implements the band sampling in Python instead of trusting the in-app
analyzer. If the two disagree, the measurement is wrong and the evidence doc must say so.

    Research/Scripts/analyze_capture.py <png> [--bands N] [--geometry color|text]

Band geometry mirrors Research/CaptureMatrix/Sources/Bands.swift. Keep the two in step.
"""
import argparse
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: python3 -m pip install pillow")

# (index, name, expected rgb or None, is_text_band)
BANDS = [
    (0, "1 plain colour (control)", (229, 25, 25), False),
    (1, "2 AVSBDL capture=ON", (38, 191, 64), False),
    (2, "3 AVSBDL capture=OFF", (242, 216, 25), False),
    (3, "4 secure-layer swap", (38, 102, 242), False),
    (4, "5 secure UITextField", None, True),
    (5, "6 secure-layer swap DISABLED (control)", (38, 102, 242), False),
    (6, "7 plain UITextField (calibration)", None, True),
    (7, "8 AVSBDL capture=ON + black shield", (38, 191, 64), False),
]

SENTINEL = (200, 0, 160)
TOLERANCE = 40


def classify(mean, expected):
    if expected is None:
        return "N/A(no-colour-signal)", -1.0
    distance = max(abs(mean[i] - expected[i]) for i in range(3))
    if distance <= TOLERANCE:
        return "LEAKED(visible)", distance
    sentinel_distance = max(abs(mean[i] - SENTINEL[i]) for i in range(3))
    if sentinel_distance <= TOLERANCE:
        return "SENTINEL-SHOWS(transparent)", distance
    if max(mean) < 32:
        return "NO-LEAK(black)", distance
    return "UNKNOWN", distance


def sample(im, rect):
    """rect in normalised (0-1) image coordinates -> list of (r,g,b)."""
    w, h = im.size
    x0, y0 = int(rect[0] * w), int(rect[1] * h)
    x1, y1 = int(rect[2] * w), int(rect[3] * h)
    pixels = []
    for y in range(y0, y1, 3):
        for x in range(x0, x1, 3):
            pixels.append(im.getpixel((x, y))[:3])
    return pixels


def band_rects(index, count, kind):
    """Colour rect or text strip of one band, in normalised image coordinates."""
    top = index / count
    height = 1.0 / count
    if kind == "color":
        fx0, fy0, fx1, fy1 = 0.76, 0.50, 0.94, 0.72
    else:
        fx0, fy0, fx1, fy1 = 0.28, 0.40, 0.72, 0.62
    return (fx0, top + fy0 * height, fx1, top + fy1 * height)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("png")
    parser.add_argument("--bands", type=int, default=len(BANDS))
    parser.add_argument("--label", default=None)
    args = parser.parse_args()

    im = Image.open(args.png).convert("RGB")
    w, h = im.size
    count = args.bands
    label = args.label or args.png
    print(f"=== {label} ({w}x{h}, {count} bands) ===")

    for index, name, expected, is_text in BANDS[:count]:
        if is_text:
            pixels = sample(im, band_rects(index, count, "text"))
            total = len(pixels)
            dark = sum(1 for p in pixels if max(p) < 90)
            ratio = 100.0 * dark / total if total else 0.0
            verdict = "TEXT-LEAKED" if ratio > 0.5 else "TEXT-BLANKED"
            print(f"  {name:<40} text dark={dark}/{total} ({ratio:5.2f}%) -> {verdict}")
        else:
            pixels = sample(im, band_rects(index, count, "color"))
            total = len(pixels)
            if not total:
                print(f"  {name:<40} NO SAMPLES")
                continue
            mean = tuple(round(sum(p[i] for p in pixels) / total) for i in range(3))
            verdict, distance = classify(mean, expected)
            print(f"  {name:<40} meanRGB={str(mean):<16} delta={distance:6.1f} -> {verdict}")


if __name__ == "__main__":
    main()
