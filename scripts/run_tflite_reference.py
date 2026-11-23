#!/usr/bin/env python3
"""Run Ecto-Trigger TFLite ops 0..71 and export one intermediate-output file.

The FPGA .mem input already contains the INT8 result of op 0 (QUANTIZE).
The TFLite interpreter must execute op 0 itself, so reconstruct its UINT8
input by XORing each INT8 byte with 0x80. Both sides are bit-exact.

Output records match the RTL testbench LAYER/OPCODE/BUFFER/BASE/ELEMENTS/DATA/END_LAYER layout.
The reference uses BUFFER REFERENCE and BASE 0 (logical output, not physical BRAM).
Requires: numpy and either tensorflow or tflite-runtime.

Command:
python run_tflite_reference.py images/img1.mem --model ecto-trigger/model_weights/4/quant/4_int8.tflite --output reference_outputs.txt

"""
import argparse
from pathlib import Path
import sys

import numpy as np


def load_interpreter(model_path):
    import tensorflow as tf
    interpreter_type = tf.lite.Interpreter
    resolver_type = tf.lite.experimental.OpResolverType

    kwargs = {
        "model_path": str(model_path),
        "experimental_preserve_all_tensors": True,
    }
    # Disable automatic default delegates so intermediate tensors remain
    # accessible and the op sequence matches the flatbuffer model.
    if hasattr(resolver_type, "BUILTIN_WITHOUT_DEFAULT_DELEGATES"):
        kwargs["experimental_op_resolver_type"] = (
            resolver_type.BUILTIN_WITHOUT_DEFAULT_DELEGATES
        )
    return interpreter_type(**kwargs)


def read_mem(path, expected_count):
    values = []
    with path.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.split("//", 1)[0].split("#", 1)[0].strip()
            if not line:
                continue
            for token in line.split():
                try:
                    value = int(token, 16)
                except ValueError as exc:
                    raise ValueError(f"{path}:{line_no}: invalid hex byte {token!r}") from exc
                if not 0 <= value <= 255:
                    raise ValueError(f"{path}:{line_no}: expected a byte, got {token!r}")
                values.append(value)
    if len(values) != expected_count:
        raise ValueError(f"Input .mem has {len(values)} bytes, expected {expected_count}")
    return np.asarray(values, dtype=np.uint8)


OPCODES = {"CONV_2D": 0, "DEPTHWISE_CONV_2D": 0, "ADD": 1,
           "PAD": 2, "MEAN": 3, "FULLY_CONNECTED": 4}


def write_layer(f, op_number, op_name, data):
    if data.dtype not in (np.dtype("uint8"), np.dtype("int8")):
        raise ValueError(f"Op {op_number} has unsupported tensor dtype {data.dtype}")
    values = np.asarray(data).reshape(-1)
    signed_values = values.view(np.int8) if values.dtype == np.uint8 else values
    f.write(f"LAYER {op_number}\n")
    f.write(f"OPCODE {OPCODES.get(op_name.upper(), -1)}\n")
    f.write("BUFFER REFERENCE\n")
    f.write("BASE 0\n")
    f.write(f"ELEMENTS {values.size}\n")
    f.write("DATA\n")
    for v in signed_values:
        f.write(f"{int(v)}\n")
    f.write(f"END_LAYER {op_number}\n")
    f.flush()
    return values.size


def main():
    p = argparse.ArgumentParser(
        description="Run TFLite and export one RTL-compatible intermediate activation file"
    )
    p.add_argument("input_mem", type=Path, help="Preprocessed INT8 .mem from preprocess_img.py")
    p.add_argument("--model", type=Path, default=Path("4_int8.tflite"))
    p.add_argument("--output", type=Path, default=Path("reference_outputs.txt"))
    p.add_argument("--first-op", type=int, default=1, help="First operator to export (default: 1)")
    p.add_argument("--last-op", type=int, default=71, help="Last operator to export (default: 71)")
    args = p.parse_args()

    if not args.model.is_file():
        p.error(f"Model not found: {args.model}")
    if not args.input_mem.is_file():
        p.error(f"Input memory file not found: {args.input_mem}")

    interpreter = load_interpreter(args.model)
    interpreter.allocate_tensors()
    input_details = interpreter.get_input_details()
    output_details = interpreter.get_output_details()
    tensor_details = {int(d["index"]): d for d in interpreter.get_tensor_details()}
    ops = interpreter._get_ops_details()  # Private TFLite API; commonly available in TF Lite.

    if len(input_details) != 1:
        raise RuntimeError(f"Expected one model input, found {len(input_details)}")
    input_info = input_details[0]
    if input_info["dtype"] != np.uint8:
        raise RuntimeError(f"Expected external UINT8 input, got {input_info['dtype']}")
    shape = tuple(int(x) for x in input_info["shape"])
    if shape != (1, 120, 160, 3):
        raise RuntimeError(f"Unexpected model input shape {shape}; expected (1,120,160,3)")
    if len(ops) != 72:
        raise RuntimeError(f"Expected ops 0..71 (72 total), found {len(ops)}. Check model version.")
    if str(ops[0]["op_name"]).upper() != "QUANTIZE":
        raise RuntimeError(f"Expected op 0 QUANTIZE, got {ops[0]['op_name']}")
    if not (1 <= args.first_op <= args.last_op <= 71):
        p.error("Export range must satisfy 1 <= --first-op <= --last-op <= 71")

    op0_outputs = [int(x) for x in ops[0]["outputs"] if int(x) >= 0]
    if len(op0_outputs) != 1:
        raise RuntimeError(f"Expected one op 0 output, found {op0_outputs}")
    op0_info = tensor_details[op0_outputs[0]]
    if op0_info["dtype"] != np.int8:
        raise RuntimeError("Expected INT8 op 0 output")
    in_scale, in_zero = input_info["quantization"]
    out_scale, out_zero = op0_info["quantization"]
    if not np.isclose(in_scale, out_scale, rtol=0, atol=0) or (in_zero, out_zero) != (127, -1):
        raise RuntimeError(
            f"Cannot use XOR input conversion: input q={(in_scale,in_zero)}, "
            f"op 0 q={(out_scale,out_zero)}"
        )

    fpga_input = read_mem(args.input_mem, int(np.prod(shape)))
    external_uint8 = np.bitwise_xor(fpga_input, np.uint8(0x80)).reshape(shape)
    interpreter.set_tensor(int(input_info["index"]), external_uint8)
    interpreter.invoke()  # Executes the entire model, ops 0 through 71.

    # Verify that the interpreter's first operation regenerates the FPGA input.
    op0_actual = interpreter.get_tensor(op0_outputs[0])
    op0_bytes = np.ascontiguousarray(op0_actual).view(np.uint8).ravel()
    mismatches = int(np.count_nonzero(op0_bytes != fpga_input))
    print(f"Op 0 QUANTIZE input check: {mismatches} mismatched bytes / {fpga_input.size}")
    if mismatches:
        raise RuntimeError("Op 0 output does not match the supplied INT8 .mem; aborting")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="ascii") as output_file:
        for op_number in range(args.first_op, args.last_op + 1):
            op = ops[op_number]
            name = str(op["op_name"])
            outputs = [int(x) for x in op["outputs"] if int(x) >= 0]
            if len(outputs) != 1:
                raise RuntimeError(f"Op {op_number} {name} has {len(outputs)} outputs; handle explicitly")
            idx = outputs[0]
            try:
                data = interpreter.get_tensor(idx)
            except (ValueError, RuntimeError) as exc:
                raise RuntimeError(
                    f"Cannot retrieve tensor {idx} from op {op_number} ({name}). "
                    "Ensure experimental_preserve_all_tensors is supported and delegates are disabled."
                ) from exc
            count = write_layer(output_file, op_number, name, data)
            print(f"Op {op_number:02d} {name:22s} tensor {idx:3d} "
                  f"shape={tuple(data.shape)!s:20s} elements={count:6d}")

    print("\nFinal model output(s):")
    with args.output.open("a", encoding="ascii") as output_file:
        for out in output_details:
            data = interpreter.get_tensor(int(out["index"]))
            values = data.ravel()

            print(
                f"  {out['name']}: dtype={data.dtype}, "
                f"raw={values.tolist()}, "
                f"quantization={out['quantization']}"
            )

            # Write final output in the same format as the RTL testbench.
            output_file.write("FINAL_OUTPUT\n")
            output_file.write(f"DTYPE {data.dtype.name.upper()}\n")
            output_file.write(f"ELEMENTS {values.size}\n")
            output_file.write("DATA\n")

            for value in values:
                output_file.write(f"{int(value)}\n")

            output_file.write("END_FINAL_OUTPUT\n")
            output_file.flush()

            # Print dequantized prediction/confidence.
            if data.dtype in (np.uint8, np.int8):
                scale, zero = out["quantization"]

                if scale > 0:
                    real = (data.astype(np.float64) - zero) * scale
                    print(f"    dequantized={real.ravel().tolist()}")
                    
    print(f"\nWrote all requested operator outputs to {args.output}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        sys.exit(1)
