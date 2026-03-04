"""Generate PWA icons and favicon from the Digivice SVG.

Produces:
  www/icons/icon-192.png          - 192x192 standard (white strokes, transparent bg)
  www/icons/icon-512.png          - 512x512 standard (white strokes, transparent bg)
  www/icons/icon-maskable-192.png - 192x192 maskable (white strokes, #1a1a2e bg)
  www/icons/icon-maskable-512.png - 512x512 maskable (white strokes, #1a1a2e bg)
  www/favicon.ico                 - 32x32 favicon

Dependencies: svgpathtools, numpy, Pillow
Uses pure-Python SVG parsing (no native cairo needed).
"""

import os
import re
import math
import xml.etree.ElementTree as ET
import numpy as np
from PIL import Image, ImageDraw
from svgpathtools import parse_path

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROJECT_ROOT = os.path.dirname(SCRIPT_DIR)
SVG_PATH = os.path.join(PROJECT_ROOT, "www", "digivice.svg")
ICONS_DIR = os.path.join(PROJECT_ROOT, "www", "icons")
FAVICON_PATH = os.path.join(PROJECT_ROOT, "www", "favicon.ico")

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
STROKE_COLOR = (255, 255, 255, 255)  # white
MASKABLE_BG = (0x1A, 0x1A, 0x2E, 255)  # #1a1a2e

# Standard icons: icon padded to ~85% of canvas
STANDARD_SCALE = 0.85
# Maskable icons: content at ~60% of canvas (within the 80% safe zone)
MASKABLE_SCALE = 0.60

STANDARD_SIZES = [48, 72, 96, 128, 144, 152, 192, 384, 512]
MASKABLE_SIZES = [192, 512]
FAVICON_SIZE = 32

# Number of line segments per curve for smooth rendering
CURVE_STEPS = 64


def parse_transform(transform_str: str) -> np.ndarray:
    """Parse an SVG transform attribute into a 3x3 affine matrix."""
    mat = np.eye(3)
    if not transform_str:
        return mat

    # Find all transform functions
    for func_match in re.finditer(
        r"(matrix|translate|scale|rotate)\s*\(([^)]+)\)", transform_str
    ):
        func = func_match.group(1)
        vals = [float(v) for v in re.split(r"[\s,]+", func_match.group(2).strip())]

        if func == "matrix":
            a, b, c, d, e, f = vals
            t = np.array([[a, c, e], [b, d, f], [0, 0, 1]])
            mat = mat @ t
        elif func == "translate":
            tx = vals[0]
            ty = vals[1] if len(vals) > 1 else 0
            t = np.array([[1, 0, tx], [0, 1, ty], [0, 0, 1]])
            mat = mat @ t
        elif func == "scale":
            sx = vals[0]
            sy = vals[1] if len(vals) > 1 else sx
            t = np.array([[sx, 0, 0], [0, sy, 0], [0, 0, 1]])
            mat = mat @ t
        elif func == "rotate":
            angle = math.radians(vals[0])
            cos_a, sin_a = math.cos(angle), math.sin(angle)
            t = np.array([[cos_a, -sin_a, 0], [sin_a, cos_a, 0], [0, 0, 1]])
            mat = mat @ t
    return mat


def collect_paths_recursive(
    element: ET.Element, parent_transform: np.ndarray, ns: dict
) -> list:
    """Recursively collect all <path> elements with accumulated transforms."""
    results = []

    local_transform = parse_transform(element.get("transform", ""))
    accumulated = parent_transform @ local_transform

    tag = element.tag
    # Strip namespace
    if "}" in tag:
        tag = tag.split("}", 1)[1]

    if tag == "path":
        d = element.get("d", "")
        style = element.get("style", "")
        # Extract stroke-width from style
        sw_match = re.search(r"stroke-width:\s*([\d.]+)", style)
        stroke_width = float(sw_match.group(1)) if sw_match else 1.5
        if d:
            results.append((d, accumulated, stroke_width))

    for child in element:
        results.extend(collect_paths_recursive(child, accumulated, ns))

    return results


def path_to_points(d: str, transform: np.ndarray, steps: int = CURVE_STEPS) -> list:
    """Convert an SVG path d-string to a list of polyline segments.

    Returns a list of polylines, where each polyline is a list of (x, y) tuples.
    Breaks on MoveTo commands to create separate polylines.
    """
    try:
        path = parse_path(d)
    except Exception:
        return []

    polylines = []
    current_polyline = []

    for i, segment in enumerate(path):
        # Sample the segment
        pts = []
        for t_val in np.linspace(0, 1, steps + 1):
            pt = segment.point(t_val)
            # Apply transform
            vec = np.array([pt.real, pt.imag, 1.0])
            transformed = transform @ vec
            pts.append((transformed[0], transformed[1]))

        if i == 0 or not current_polyline:
            current_polyline = list(pts)
        else:
            # Check if this segment starts where the last one ended
            last_pt = current_polyline[-1]
            first_pt = pts[0]
            dist = math.hypot(last_pt[0] - first_pt[0], last_pt[1] - first_pt[1])
            if dist > 0.01:
                # Discontinuity - start a new polyline
                if len(current_polyline) >= 2:
                    polylines.append(current_polyline)
                current_polyline = list(pts)
            else:
                # Continue the polyline (skip duplicate first point)
                current_polyline.extend(pts[1:])

    if len(current_polyline) >= 2:
        polylines.append(current_polyline)

    return polylines


def render_svg(target_size: int, scale_factor: float) -> Image.Image:
    """Render the Digivice SVG to a PIL Image at the given scale within target_size.

    The icon content is rendered at scale_factor * target_size and centered.
    Returns an RGBA image with transparent background.
    """
    tree = ET.parse(SVG_PATH)
    root = tree.getroot()

    # SVG viewBox is 0 0 24 24
    viewbox = root.get("viewBox", "0 0 24 24")
    vb_parts = [float(v) for v in viewbox.split()]
    vb_width, vb_height = vb_parts[2], vb_parts[3]

    # Calculate the rendering size for the icon content
    icon_px = int(target_size * scale_factor)
    render_scale = icon_px / max(vb_width, vb_height)

    # Offset to center in the target canvas
    offset_x = (target_size - icon_px) / 2.0
    offset_y = (target_size - icon_px) / 2.0

    # Build a base transform: scale SVG coords to pixel coords + offset
    base_transform = np.array(
        [
            [render_scale, 0, offset_x],
            [0, render_scale, offset_y],
            [0, 0, 1],
        ]
    )

    # Collect all paths with transforms
    ns = {"svg": "http://www.w3.org/2000/svg"}
    paths = collect_paths_recursive(root, base_transform, ns)

    # Create image
    # Render at 2x for antialiasing, then downscale
    aa_factor = 2
    aa_size = target_size * aa_factor
    img = Image.new("RGBA", (aa_size, aa_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    for d_str, transform, stroke_width in paths:
        # Adjust transform for antialiasing scale
        aa_transform = np.array(
            [[aa_factor, 0, 0], [0, aa_factor, 0], [0, 0, 1]]
        ) @ transform
        polylines = path_to_points(d_str, aa_transform)
        line_width = max(1, int(stroke_width * render_scale * aa_factor))

        for polyline in polylines:
            if len(polyline) < 2:
                continue
            # Draw as connected line segments
            draw.line(polyline, fill=STROKE_COLOR, width=line_width, joint="curve")

    # Downscale with antialiasing
    img = img.resize((target_size, target_size), Image.LANCZOS)
    return img


def create_standard_icon(size: int) -> Image.Image:
    """White strokes on transparent background, padded to ~85% of canvas."""
    return render_svg(size, STANDARD_SCALE)


def create_maskable_icon(size: int) -> Image.Image:
    """White strokes on dark background, content at ~60% of canvas."""
    icon = render_svg(size, MASKABLE_SCALE)
    # Create background
    bg = Image.new("RGBA", (size, size), MASKABLE_BG)
    bg.paste(icon, (0, 0), icon)
    return bg


def create_favicon() -> Image.Image:
    """32x32 favicon derived from the standard icon."""
    return create_standard_icon(FAVICON_SIZE)


def main() -> None:
    os.makedirs(ICONS_DIR, exist_ok=True)

    # Standard icons
    for size in STANDARD_SIZES:
        img = create_standard_icon(size)
        path = os.path.join(ICONS_DIR, f"icon-{size}.png")
        img.save(path, "PNG")
        print(f"  Created {path}  ({os.path.getsize(path):,} bytes)")

    # Maskable icons
    for size in MASKABLE_SIZES:
        img = create_maskable_icon(size)
        path = os.path.join(ICONS_DIR, f"icon-maskable-{size}.png")
        img.save(path, "PNG")
        print(f"  Created {path}  ({os.path.getsize(path):,} bytes)")

    # Favicon
    favicon_img = create_favicon()
    favicon_img.save(FAVICON_PATH, format="ICO", sizes=[(FAVICON_SIZE, FAVICON_SIZE)])
    print(f"  Created {FAVICON_PATH}  ({os.path.getsize(FAVICON_PATH):,} bytes)")

    print("\nAll icons generated successfully.")


if __name__ == "__main__":
    main()
