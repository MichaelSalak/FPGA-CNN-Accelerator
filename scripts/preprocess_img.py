#!/usr/bin/env python3
"""Convert an RGB image into a 120x160x3 signed-INT8 FPGA activation .mem file.

The model's initial UINT8 -> INT8 QUANTIZE has equal scales and zero points
127 -> -1, so the conversion is equivalent to XOR with 0x80.

Command: 
python preprocess_img.py images/img1.jpg images/img1.mem

"""
import argparse
from pathlib import Path

import cv2
import numpy as np

HEIGHT = 120
WIDTH = 160
CHANNELS = 3


def main():
    parser = argparse.ArgumentParser(description="Prepare an image for the Ecto-Trigger FPGA accelerator")
    parser.add_argument("input_image", type=Path, help="Input image (JPG, PNG, BMP, TIFF, WebP, etc.)")
    parser.add_argument("output_mem", type=Path, help="Output hexadecimal .mem file")
    parser.add_argument("--interpolation", choices=("linear", "area", "nearest", "cubic"), default="cubic",
                        help="OpenCV resize interpolation (default: cubic)")
    args = parser.parse_args()

    if not args.input_image.is_file():
        parser.error(f"Input image not found: {args.input_image}")
    if args.input_image.resolve() == args.output_mem.resolve():
        parser.error("Input and output paths must differ")

    img_bgr = cv2.imread(str(args.input_image), cv2.IMREAD_COLOR)
    if img_bgr is None:
        parser.error(f"Could not decode image: {args.input_image}")

    original_h, original_w = img_bgr.shape[:2]
    interpolation = {
        "linear": cv2.INTER_LINEAR,
        "area": cv2.INTER_AREA,
        "nearest": cv2.INTER_NEAREST,
        "cubic": cv2.INTER_CUBIC,
    }[args.interpolation]
    resized_bgr = cv2.resize(img_bgr, (WIDTH, HEIGHT), interpolation=interpolation)
    rgb = cv2.cvtColor(resized_bgr, cv2.COLOR_BGR2RGB)
    # Preserve raw byte patterns; the signed interpretation is two's-complement.
    quantized_bytes = np.bitwise_xor(rgb, np.uint8(0x80))
    assert quantized_bytes.shape == (HEIGHT, WIDTH, CHANNELS)
    assert quantized_bytes.dtype == np.uint8

    args.output_mem.parent.mkdir(parents=True, exist_ok=True)
    with args.output_mem.open("w", encoding="ascii", newline="\n") as out:
        for value in quantized_bytes.reshape(-1):
            out.write(f"{int(value):02x}\n")

    print(f"Input:  {args.input_image} ({original_w}x{original_h})")
    print(f"Output: {args.output_mem}")
    print(f"Tensor: ({HEIGHT}, {WIDTH}, {CHANNELS}), RGB, HWC, signed INT8")
    print(f"Values: {quantized_bytes.size:,} bytes, one hexadecimal byte per line")
    print("Quantization: UINT8 XOR 0x80 (scale unchanged, zero point 127 -> -1)")


if __name__ == "__main__":
    main()
