"""
Convert image to ICO with multiple resolutions.

Equivalent to for example:
magick "icon.png" -define icon:auto-resize=16,32,48,64,128,256 -compress zip "icon.ico"

Usage (other image types might also work):
    python create_icon.py input.png output.ico
    python create_icon.py input.png  # Creates input.ico
"""

import sys
from pathlib import Path

from PIL import Image


def create_icon(image_path, output_path, icon_sizes=(256, 128, 64, 48, 32, 16)):
    """
    Standard conversion of an image to a multi-size ICO.
    """

    img = Image.open(image_path).convert("RGBA")

    # resize to max size
    max_size = max(img.width, img.height)

    layers = [
        img.resize((round(size * img.width / max_size), round(size * img.height / max_size)), Image.Resampling.LANCZOS)
        for size in icon_sizes
    ]

    layers[0].save(output_path, format="ICO", sizes=[(s, s) for s in icon_sizes], append_images=layers[1:])


if __name__ == "__main__":
    image_path = sys.argv[1] if len(sys.argv) > 1 else None
    output_path = sys.argv[2] if len(sys.argv) > 2 else None

    # Determine input path if undefined (first png in directory)
    if image_path is None:
        import glob

        png_s = glob.glob("*.png")
        if len(png_s) == 0:
            print(__doc__)
            sys.exit(1)
        image_path = png_s[0]
        image_path = Path(image_path)
    else:
        image_path = Path(image_path)
        if not image_path.exists():
            raise FileNotFoundError(f"Input file not found: {image_path}")

    # Determine output path if undefined
    if output_path is None:
        output_path = image_path.with_suffix(".ico")
    else:
        output_path = Path(output_path)

    try:
        create_icon(image_path, output_path)
        print(f"Generated: {output_path}")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)
