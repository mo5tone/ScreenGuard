#!/usr/bin/env python3
"""Interpret a `renderSanity` display screenshot and decide whether `preventsCapture` works.

`renderSanity` renders three display layers that differ only in the `preventsCapture` flag, each over
a SENTINEL-magenta backing:

    case A  preventsCapture = true   (flag set AFTER adding the layer)   expected rgb(229,25,25)
    case B  preventsCapture = true   (flag set BEFORE adding the layer)  expected rgb(38,191,64)
    case C  preventsCapture = false  (control, must always paint)        expected rgb(242,216,25)

The sentinel backing is what makes this decisive. A band can read one of three things, and they mean
three different things:

    expected colour -> the layer PAINTED
    sentinel magenta -> the layer painted NOTHING (contributed no pixels at all)
    black           -> the layer painted, but the capture path EXCLUDED its content

Because the backing is sentinel and never black, "black" can never be produced by a non-painting
layer. That is the whole trick: it separates "protection worked" from "nothing rendered here".

This runs on Simulator screenshots and on device screenshots alike.

    Research/Scripts/interpret_render_sanity.py <DISPLAY-ground-truth.png>
"""
import sys

try:
    from PIL import Image
except ImportError:
    sys.exit("Pillow is required: python3 -m pip install pillow")

SENTINEL = (200, 0, 160)
TOLERANCE = 40

CASES = [
    ("A", "preventsCapture=true (set AFTER add)", (229, 25, 25)),
    ("B", "preventsCapture=true (set BEFORE add)", (38, 191, 64)),
    ("C", "preventsCapture=false (control)", (242, 216, 25)),
]

PAINTED = "PAINTED"
NOT_PAINTED = "NOT-PAINTED"
EXCLUDED_BLACK = "EXCLUDED-BLACK"
OTHER = "OTHER"


def classify(mean):
    distance_expected = None
    for name, _, expected in CASES:
        if max(abs(mean[i] - expected[i]) for i in range(3)) <= TOLERANCE:
            return PAINTED, name
    distance_sentinel = max(abs(mean[i] - SENTINEL[i]) for i in range(3))
    if distance_sentinel <= TOLERANCE:
        return NOT_PAINTED, None
    if max(mean) < 32:
        return EXCLUDED_BLACK, None
    return OTHER, None


def sample_case(im, index, count=3):
    """Mean RGB of one case's band, sampled at its centre away from the label chip."""
    w, h = im.size
    top = index / count
    height = 1.0 / count
    y0 = int(h * (top + height * 0.35))
    y1 = int(h * (top + height * 0.85))
    x0, x1 = int(w * 0.15), int(w * 0.95)
    totals = [0, 0, 0]
    count_px = 0
    for y in range(y0, y1, 4):
        for x in range(x0, x1, 4):
            pixel = im.getpixel((x, y))[:3]
            for channel in range(3):
                totals[channel] += pixel[channel]
            count_px += 1
    if not count_px:
        return (0, 0, 0)
    return tuple(round(total / count_px) for total in totals)


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    path = sys.argv[1]
    im = Image.open(path).convert("RGB")
    print(f"=== renderSanity interpretation: {path} ({im.size[0]}x{im.size[1]}) ===")
    print(f"sentinel = rgb{SENTINEL}; tolerance = +/-{TOLERANCE}\n")

    results = {}
    for index, (key, label, expected) in enumerate(CASES):
        mean = sample_case(im, index)
        state, matched = classify(mean)
        results[key] = state
        detail = f" (reads case {matched})" if matched else ""
        print(f"  case {key} {label:<38} meanRGB={str(mean):<16} -> {state}{detail}")

    print()
    control = results["C"]
    protected = [results["A"], results["B"]]

    if control != PAINTED:
        print("VERDICT: GROUND-TRUTH-UNAVAILABLE")
        print("  The control case (preventsCapture=false) did not paint in this image, so this capture")
        print("  path cannot image the display at all. No conclusion about preventsCapture is possible")
        print("  from it. On a device, photograph the screen instead.")
        return 2

    if any(state == NOT_PAINTED for state in protected):
        print("VERDICT: PREVENTSCAPTURE-NOT-USABLE")
        print("  At least one protected case shows the sentinel, i.e. the layer contributed NO pixels")
        print("  anywhere - it did not merely get excluded from a capture.")
        print()
        print("  On SIMULATOR this is the known confound: preventsCapture=true stops the layer")
        print("  rendering, so a black protected band there is UNEARNED (it is the backing showing")
        print("  through a layer that never painted).")
        print()
        print("  On a DEVICE this is a genuine finding about the OS build under test: preventsCapture")
        print("  is not a usable capture-protection mechanism on this build, because the protected")
        print("  content never reaches the display at all. Record it as such - do NOT report the")
        print("  resulting blank band as protection working.")
        return 1

    print("VERDICT: PREVENTSCAPTURE-USABLE")
    for key, state in zip("AB", protected):
        if state == PAINTED:
            print(f"  case {key}: PAINTED - this capture path does NOT honour capture protection, so it")
            print("    read the layer's real colour. The layer therefore DOES render.")
        elif state == EXCLUDED_BLACK:
            print(f"  case {key}: EXCLUDED-BLACK - this capture path DOES honour capture protection and")
            print("    returned black for a layer that is rendering. This is the documented behaviour.")
    print("  In both cases the protected layer is rendering, which is what makes the corresponding")
    print("  blank band in the app-side render path attributable to protection rather than to an")
    print("  absent layer.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
