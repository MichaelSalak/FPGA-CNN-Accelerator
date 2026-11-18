#!/usr/bin/env python3
"""Generate TFLite-style Q31 requantization records and an operator address map.

Requires numpy and either tensorflow or tflite_runtime for --tflite mode.
Raw analysis alone supports address-map generation, NOT complete per-channel scales.

Command: 

python generate_requant.py `
    --raw model_analysis_raw.txt `
    --tflite ecto-trigger/model_weights/4/quant/4_int8.tflite `
    --mem requant.mem `
    --map requant_address_map.md

"""
import argparse
import math
import re
from pathlib import Path

OP_RE = re.compile(r'^OP (\d+) code (\d+) inputs \[([^]]*)\] outputs \[([^]]*)\]')
TENSOR_RE = re.compile(r'^\s+(\d+) .*? (\[[^]]*\]) dtype (\d+) scales (\d+) scale0 (\[[^]]*\]) zero0 (\[[^]]*\]) axis (\d+) buffer (\d+)')
CODES = {0:'CONV_2D',1:'DEPTHWISE_CONV_2D',2:'ADD',3:'PAD',4:'MEAN',5:'FULLY_CONNECTED',6:'LOGISTIC',7:'QUANTIZE'}


def parse_raw(path):
    ops = []
    current = None
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        m = OP_RE.match(line)
        if m:
            idx, code = map(int, m.group(1, 2))
            current = dict(index=idx, type=CODES.get(code, f'CODE_{code}'),
                           inputs=[int(v) for v in re.findall(r'-?\d+', m.group(3))],
                           outputs=[int(v) for v in re.findall(r'-?\d+', m.group(4))], tensors=[])
            ops.append(current)
        elif current is not None:
            t = TENSOR_RE.match(line)
            if t:
                shape = [int(v) for v in re.findall(r'-?\d+', t.group(2))]
                current['tensors'].append(dict(id=int(t.group(1)), shape=shape,
                                               scale_count=int(t.group(4))))
    if len(ops) != 72 or [o['index'] for o in ops] != list(range(72)):
        raise ValueError('Expected the 72 operators OP 0..71 from this model')
    return ops


def record_count(op):
    typ = op['type']
    if typ in ('CONV_2D', 'DEPTHWISE_CONV_2D'):
        # Quantized filter has one weight scale per output channel.
        weight_id = op['inputs'][1]
        t = next(t for t in op['tensors'] if t['id'] == weight_id)
        return t['scale_count']
    return {'ADD':3, 'PAD':0, 'MEAN':1, 'FULLY_CONNECTED':1}.get(typ, 0)


def allocate(ops):
    entries = []
    cursor = 0
    for op in ops:
        if op['index'] in (0,70,71):
            continue
        n = record_count(op)
        entries.append(dict(op=op, base=cursor if n else None, count=n))
        cursor += n
    assert len(entries) == 69
    return entries, cursor


def quantize_multiplier(real):
    """TFLite QuantizeMultiplier: signed Q31 multiplier and signed binary shift."""
    if not math.isfinite(real) or real <= 0:
        raise ValueError(f'Invalid real multiplier: {real}')
    significand, shift = math.frexp(real)
    q = math.floor(significand * (1 << 31) + 0.5)
    if q == 1 << 31:
        q //= 2
        shift += 1
    if not -128 <= shift <= 127:
        raise ValueError(f'Shift {shift} cannot fit signed int8')
    return q, shift


def load_tflite_quant(path):
    import tensorflow as tf
    interpreter = tf.lite.Interpreter(model_path=str(path))
    # Tensor details include per-axis quantization parameters,
    # including those for constant weight tensors.
    details = {
        int(t['index']): t
        for t in interpreter.get_tensor_details()
    }
    return details


def scales(details, tensor_id):
    if tensor_id not in details:
        raise ValueError(f'Missing TFLite tensor {tensor_id}')
    arr = details[tensor_id]['quantization_parameters']['scales']
    if len(arr) == 0:
        raise ValueError(f'Tensor {tensor_id} has no quantization scale')
    return [float(v) for v in arr]


def compute_records(op, details):
    typ = op['type']
    ids = op['inputs']
    out = op['outputs'][0]
    si = scales(details, ids[0])[0]
    so = scales(details, out)[0]
    if typ in ('CONV_2D', 'DEPTHWISE_CONV_2D', 'FULLY_CONNECTED'):
        ws = scales(details, ids[1])
        n = record_count(op)
        if len(ws) != n:
            raise ValueError(f'OP {op["index"]}: expected {n} weight scales, got {len(ws)}')
        return [quantize_multiplier(si * sw / so) for sw in ws]
    if typ == 'ADD':
        sb = scales(details, ids[1])[0]
        twice_max = 2.0 * max(si, sb)
        # Matches TFLite reference ADD with LEFT_SHIFT=20.
        return [quantize_multiplier(si / twice_max),
                quantize_multiplier(sb / twice_max),
                quantize_multiplier(twice_max / ((1 << 20) * so))]
    if typ == 'MEAN':
        input_shape = next(t['shape'] for t in op['tensors'] if t['id'] == ids[0])
        if len(input_shape) != 4:
            raise ValueError('MEAN expected NHWC input')
        spatial_count = input_shape[1] * input_shape[2]
        return [quantize_multiplier(si / (spatial_count * so))]
    if typ == 'PAD':
        return []
    raise ValueError(f'Unsupported configured operation: {typ}')


def write_map(entries, total, path):
    lines = ['# Requantization ROM address map', '',
             'Each ROM address selects one 40-bit `{multiplier[31:0], shift[7:0]}` record.',
             'The shift is a signed int8 in two\'s-complement; positive values denote left shifts.',
             'Addresses are **record indices**, not byte offsets.', '',
             '| TFLite OP | Operation type | Requant base address | Number of entries |',
             '|---:|---|---:|---:|']
    for e in entries:
        op = e['op']
        base = str(e['base']) if e['base'] is not None else '—'
        lines.append(f'| {op["index"]} | {op["type"]} | {base} | {e["count"]} |')
    lines.extend(['', f'**Total: {total} records × 40 bits = {total * 40} bits ({total * 5} bytes).**', '',
                  'OP 0 (input QUANTIZE), OP 70 (LOGISTIC), and OP 71 (output QUANTIZE) are excluded.',
                  'MEAN incorporates division by 4×5=20 in its single multiplier.',
                  'ADD record order: input A, input B, output.'])
    Path(path).write_text('\n'.join(lines) + '\n', encoding='utf-8')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--raw', default='model_analysis_raw.txt')
    p.add_argument('--tflite', help='Full model required to generate accurate per-channel multipliers')
    p.add_argument('--mem', default='requant.mem')
    p.add_argument('--map', default='requant_address_map.md')
    args = p.parse_args()
    ops = parse_raw(args.raw)
    entries, total = allocate(ops)
    write_map(entries, total, args.map)
    print(f'Wrote {args.map}: {len(entries)} operators, {total} requant records')
    if not args.tflite:
        print('No .tflite supplied: skipped .mem generation (raw file truncates per-channel scales).')
        return
    details = load_tflite_quant(args.tflite)
    records = []
    for entry in entries:
        op = entry['op']
        computed = compute_records(op, details)
        if len(computed) != entry['count']:
            raise ValueError(f'OP {op["index"]}: record count mismatch')
        records.extend(computed)
    assert len(records) == total
    # 8 hex digits for Q31 multiplier, then 2 for signed shift.
    Path(args.mem).write_text(''.join(f'{m & 0xffffffff:08X}{s & 0xff:02X}\n' for m,s in records), encoding='ascii')
    print(f'Wrote {args.mem}: {len(records)} 40-bit records')

if __name__ == '__main__':
    main()
