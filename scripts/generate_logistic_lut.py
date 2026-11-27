"""Generate 256-entry quantized sigmoid LUT for OP70, mathematical reference.
For exact TFLite kernel entries, run with --model logistic_only.tflite
(an isolated one-input one-output LOGISTIC operator extracted from original model).
"""
import argparse
import math
from pathlib import Path

import numpy as np

INPUT_SCALE = np.float32(0.08192142844200134)
INPUT_ZERO_POINT = -12
OUTPUT_SCALE = 1.0 / 256.0
OUTPUT_ZERO_POINT = -128


def mathematical_lut():
    result = []
    for q in range(-128, 128):
        x = float(np.float32(q - INPUT_ZERO_POINT) * INPUT_SCALE)
        p = 1.0 / (1.0 + math.exp(-x))
        # np.rint uses nearest-even; ties are not expected for this table
        y = int(np.rint(p / OUTPUT_SCALE)) + OUTPUT_ZERO_POINT
        result.append(max(-128, min(127, y)))
    return result


def tflite_lut(model_path):
    import tensorflow as tf
    interpreter = tf.lite.Interpreter(model_path=str(model_path))
    interpreter.allocate_tensors()
    inp = interpreter.get_input_details()[0]
    out = interpreter.get_output_details()[0]
    if inp['dtype'] != np.int8 or out['dtype'] != np.int8:
        raise ValueError('Expected int8 input and output')
    if tuple(inp['shape']) != (1, 1) or tuple(out['shape']) != (1, 1):
        raise ValueError('Expected isolated scalar LOGISTIC with shape [1,1]')
    values = []
    for q in range(-128, 128):
        interpreter.set_tensor(inp['index'], np.array([[q]], dtype=np.int8))
        interpreter.invoke()
        values.append(int(interpreter.get_tensor(out['index'])[0, 0]))
    return values



# python generate_logistic_lut.py --model logistic_only.tflite --out logistic_lut.mem

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--model', help='Optional isolated LOGISTIC TFLite model for kernel-exact LUT')
    parser.add_argument('--out', default='logistic_lut.mem')
    args = parser.parse_args()
    values = tflite_lut(args.model) if args.model else mathematical_lut()
    Path(args.out).write_text(''.join(f'{v & 255:02x}\n' for v in values))
    print('Wrote', len(values), 'entries to', args.out)
    print('Source:', 'TFLite interpreter' if args.model else 'mathematical sigmoid approximation')
    print('Input 61 ->', values[61 + 128], f'(0x{values[61 + 128] & 255:02x})')
