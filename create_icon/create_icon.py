"""
Convert image to ICO with multiple resolutions.

Usage (other image types might also work):
    python create_icon.py input.png {optional:output.ico}

Equivalent to for example:
magick "icon.png" -define icon:auto-resize=16,32,48,64,128,256 -compress zip "icon.ico"


"""

import sys
from pathlib import Path

from PIL import Image


def create_icon(
    image_path,
    output_path,
    icon_sizes=(256, 128, 64, 48, 32, 16),
    background_color=(0, 0, 0, 0),  # transparent
):
    """
    Convert an image into a multi-resolution .ico file with padding
    to preserve aspect ratio (no distortion).

    background_color=(0, 0, 0, 0) means transparent background
    """

    src = Image.open(image_path).convert("RGBA")
    src_w, src_h = src.size

    layers = []

    for size in icon_sizes:
        # scale factor: fit longest side into "size"
        scale = size / max(src_w, src_h)
        new_w = round(src_w * scale)
        new_h = round(src_h * scale)

        resized = src.resize((new_w, new_h), Image.Resampling.LANCZOS)

        # create square canvas and center the resized image
        canvas = Image.new("RGBA", (size, size), background_color)
        offset_x = (size - new_w) // 2
        offset_y = (size - new_h) // 2
        canvas.paste(resized, (offset_x, offset_y), resized)

        layers.append(canvas)

    # save as multi-size ICO
    layers[0].save(
        output_path,
        format="ICO",
        sizes=[(s, s) for s in icon_sizes],
        append_images=layers[1:],
    )


if __name__ == "__main__":
    image_path = sys.argv[1] if len(sys.argv) > 1 else None
    output_path = sys.argv[2] if len(sys.argv) > 2 else None

    # Determine input path if undefined (first png in directory)
    if image_path is None:
        import glob

        png_s = glob.glob("*.png")
        if len(png_s) == 0:
            print("""[Error] No png file found in directory.

Usage:
    python create_icon.py input.png {optional:output.ico}
(other image types might also work)
""")
            print("Aborting. Press enter to exit.")
            input()
            sys.exit(1)

        image_path = png_s[0]
        image_path = Path(image_path)
    else:
        image_path = Path(image_path)
        if not image_path.exists():
            print(f"[Error] Input file not found: {image_path}")
            print("Aborting. Press enter to exit.")
            input()
            sys.exit(1)

    # Determine output path if undefined
    if output_path is None:
        output_path = image_path.with_suffix(".ico")
    else:
        output_path = Path(output_path)

    try:
        create_icon(image_path, output_path)
        sys.exit(0)
    except Exception as e:
        print(f"[Error] {e}")
        print("Aborting. Press enter to exit.")
        input()
        sys.exit(1)
