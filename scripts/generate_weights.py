#!/usr/bin/env python3
"""Generate signed int8 weight ROM and per-operation address map from a TFLite model.

Command:
python generate_weights.py `
    --raw model_analysis_raw.txt `
    --tflite ecto-trigger/model_weights/4/quant/4_int8.tflite `
    --mem weights.mem `
    --map weight_address_map.md

ROM: one two-hex-digit signed int8 weight per address, in original TFLite
flat-buffer tensor order (no transposition). CONV_2D is OHWI; depthwise
is [1, KH, KW, C]; FULLY_CONNECTED is [OUT, IN].
"""
import argparse
import math
from pathlib import Path

# Reuse the validated raw-analysis parser and bounds-checked FlatBuffer reader
# from generate_bias.py, which should be in the same scripts/ directory.
from generate_bias import FlatBuffer, parse_raw

WEIGHT_OPS = {'CONV_2D', 'DEPTHWISE_CONV_2D', 'FULLY_CONNECTED'}


def count_weights(op):
    if op['type'] not in WEIGHT_OPS:
        return 0
    if len(op['inputs']) < 2 or op['inputs'][1] < 0:
        raise ValueError(f'OP {op["index"]}: missing weight tensor')
    tid = op['inputs'][1]
    if tid not in op['tensors']:
        raise ValueError(f'OP {op["index"]}: missing weight metadata for tensor {tid}')
    shape = op['tensors'][tid]['shape']
    if not shape or any(d <= 0 for d in shape):
        raise ValueError(f'OP {op["index"]}: invalid weight shape {shape}')
    if op['type'] == 'CONV_2D' and len(shape) != 4:
        raise ValueError(f'OP {op["index"]}: CONV_2D expected OHWI weights')
    if op['type'] == 'DEPTHWISE_CONV_2D' and (len(shape) != 4 or shape[0] != 1):
        raise ValueError(f'OP {op["index"]}: DEPTHWISE expected [1,KH,KW,C]')
    if op['type'] == 'FULLY_CONNECTED' and len(shape) != 2:
        raise ValueError(f'OP {op["index"]}: FC expected [OUT,IN]')
    return math.prod(shape)


def allocate(ops):
    entries, cursor = [], 0
    for op in ops:
        if op['index'] in (0, 70, 71):
            continue
        count = count_weights(op)
        entries.append({'op': op, 'base': cursor if count else None, 'count': count})
        cursor += count
    if len(entries) != 69:
        raise ValueError('Expected 69 configured operations')
    return entries, cursor


def read_weights(entry, tensors):
    op = entry['op']
    if entry['count'] == 0:
        return b''
    tid = op['inputs'][1]
    if tid >= len(tensors):
        raise ValueError(f'OP {op["index"]}: tensor {tid} outside model')
    tensor = tensors[tid]
    expected_shape = op['tensors'][tid]['shape']
    if tensor['dtype'] != 9:  # TensorType.INT8
        raise ValueError(f'OP {op["index"]}: weights must be int8; got type {tensor["dtype"]}')
    if tensor['shape'] != expected_shape:
        raise ValueError(f'OP {op["index"]}: shape mismatch {tensor["shape"]} vs {expected_shape}')
    if len(tensor['data']) != entry['count']:
        raise ValueError(f'OP {op["index"]}: expected {entry["count"]} bytes; got {len(tensor["data"])}')
    return tensor['data']


def write_map(entries, total, path):
    lines = [
        '# Weight ROM address map', '',
        'Each ROM address selects one signed **8-bit** weight (two\'s-complement).',
        'Addresses are **weight indices**, not byte offsets. The `.mem` file contains one 2-digit hex byte per line.',
        'Weights are copied directly from the TFLite model without transposition.', '',
        '**Indexing within each operation:**', '',
        '- `CONV_2D` TFLite `[O, KH, KW, I]`: `base + (((o*KH + kh)*KW + kw)*I + i)`.',
        '- `DEPTHWISE_CONV_2D` TFLite `[1, KH, KW, C]`: `base + ((kh*KW + kw)*C + c)`.',
        '- `FULLY_CONNECTED` TFLite `[O, I]`: `base + o*I + i`.',
        '- `ADD`, `PAD`, `MEAN`: no weight entries.', '',
        '| TFLite OP | Operation type | Weight base address | Number of entries | Weight shape |',
        '|---:|---|---:|---:|---|',
    ]
    for e in entries:
        op = e['op']
        base = str(e['base']) if e['base'] is not None else '—'
        shape = str(op['tensors'][op['inputs'][1]]['shape']) if e['count'] else '—'
        lines.append(f'| {op["index"]} | {op["type"]} | {base} | {e["count"]} | `{shape}` |')
    lines += [
        '', f'**Total: {total:,} entries × 8 bits = {total:,} bits ({total:,} bytes).**', '',
        'OP 0 (input QUANTIZE), OP 70 (LOGISTIC), and OP 71 (output QUANTIZE) are excluded.',
        'A base of — means the operation has no weights.',
        'The maximum address must fit the RTL weight address width.',
    ]
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--raw', default='model_analysis_raw.txt')
    parser.add_argument('--tflite', help='Original .tflite file, required for .mem output')
    parser.add_argument('--mem', default='mem/weights.mem')
    parser.add_argument('--map', default='docs/weight_address_map.md')
    args = parser.parse_args()

    ops = parse_raw(args.raw)
    entries, total = allocate(ops)
    if total > 1 << 17:
        raise ValueError(f'{total} weights exceed the 17-bit weight address space')
    write_map(entries, total, args.map)
    print(f'Wrote {args.map}: {len(entries)} operations, {total} weight records')
    if not args.tflite:
        print('No .tflite supplied: skipped .mem generation')
        return

    tensors = FlatBuffer(args.tflite).tensor_metadata()
    data = b''.join(read_weights(e, tensors) for e in entries)
    if len(data) != total:
        raise ValueError('Weight ROM size mismatch')
    path = Path(args.mem)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(''.join(f'{byte:02X}\n' for byte in data), encoding='ascii')
    print(f'Wrote {path}: {total} signed int8 weights')


if __name__ == '__main__':
    main()
