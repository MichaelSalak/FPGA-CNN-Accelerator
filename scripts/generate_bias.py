#!/usr/bin/env python3
"""Generate 32-bit signed bias ROM and Markdown address map for the 72-op model.

Uses model_analysis_raw.txt for operator/tensor mapping and reads exact int32
bias constants from the .tflite FlatBuffer. No TensorFlow dependency.

Command: 
python generate_bias.py `
    --raw model_analysis_raw.txt `
    --tflite ecto-trigger/model_weights/4/quant/4_int8.tflite `
    --mem bias.mem `
    --map bias_address_map.md

ROM layout: one 8-hex-digit, two's-complement int32 per line.
"""
import argparse
import re
import struct
from pathlib import Path

OP_RE = re.compile(r'^OP (\d+) code (\d+) inputs \[([^]]*)\] outputs \[([^]]*)\]')
TENSOR_RE = re.compile(r'^\s+(\d+) .*? (\[[^]]*\]) dtype (\d+) scales (\d+) scale0')
CODES = {0: 'CONV_2D', 1: 'DEPTHWISE_CONV_2D', 2: 'ADD',
         3: 'PAD', 4: 'MEAN', 5: 'FULLY_CONNECTED',
         6: 'LOGISTIC', 7: 'QUANTIZE'}
BIAS_OPS = {'CONV_2D', 'DEPTHWISE_CONV_2D', 'FULLY_CONNECTED'}


def parse_raw(path):
    ops = []
    current = None
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        m = OP_RE.match(line)
        if m:
            index, code = map(int, m.group(1, 2))
            current = {'index': index, 'type': CODES.get(code, f'CODE_{code}'),
                       'inputs': [int(x) for x in re.findall(r'-?\d+', m.group(3))],
                       'outputs': [int(x) for x in re.findall(r'-?\d+', m.group(4))],
                       'tensors': {}}
            ops.append(current)
        elif current is not None:
            t = TENSOR_RE.match(line)
            if t:
                current['tensors'][int(t.group(1))] = {
                    'shape': [int(x) for x in re.findall(r'-?\d+', t.group(2))],
                    'dtype': int(t.group(3)),
                    'scale_count': int(t.group(4))}
    if len(ops) != 72 or [o['index'] for o in ops] != list(range(72)):
        raise ValueError('Expected 72 operators OP 0..71')
    return ops


class FlatBuffer:
    """Minimal, bounds-checked FlatBuffer reader for TFLite tensor/buffer data."""
    def __init__(self, path):
        self.data = Path(path).read_bytes()
        if len(self.data) < 8 or self.data[4:8] != b'TFL3':
            raise ValueError('Expected a TFL3 TensorFlow Lite FlatBuffer')

    def unpack(self, fmt, offset):
        if offset < 0 or offset + struct.calcsize(fmt) > len(self.data):
            raise ValueError(f'FlatBuffer offset outside file: {offset}')
        return struct.unpack_from(fmt, self.data, offset)[0]

    def u32(self, off): return self.unpack('<I', off)
    def i32(self, off): return self.unpack('<i', off)
    def u16(self, off): return self.unpack('<H', off)
    def u8(self, off): return self.unpack('<B', off)

    def field(self, table, index):
        vt = table - self.i32(table)
        vt_size = self.u16(vt)
        pos = vt + 4 + 2 * index
        if pos + 2 > vt + vt_size:
            return None
        displacement = self.u16(pos)
        return table + displacement if displacement else None

    def ref(self, off):
        return off + self.u32(off) if off is not None else None

    def vector(self, table, field_index):
        off = self.ref(self.field(table, field_index))
        if off is None:
            return None, 0
        return off + 4, self.u32(off)

    def vector_table(self, table, field_index, i):
        start, count = self.vector(table, field_index)
        if start is None or not 0 <= i < count:
            raise ValueError(f'Invalid table index {i} in field {field_index}')
        return self.ref(start + 4 * i)

    def int_vector(self, table, field_index):
        start, count = self.vector(table, field_index)
        return [] if start is None else [self.i32(start + 4 * i) for i in range(count)]

    def tensor_metadata(self):
        root = self.u32(0)
        subgraph = self.vector_table(root, 2, 0)
        tensors_start, tensor_count = self.vector(subgraph, 0)
        buffers_start, buffer_count = self.vector(root, 4)
        tensors = []
        for i in range(tensor_count):
            tensor = self.vector_table(subgraph, 0, i)
            dtype_field = self.field(tensor, 1)
            dtype = self.u8(dtype_field) if dtype_field is not None else 0
            buffer_field = self.field(tensor, 2)
            buffer_index = self.u32(buffer_field) if buffer_field is not None else 0
            if buffer_index >= buffer_count:
                raise ValueError(f'Tensor {i} references nonexistent buffer {buffer_index}')
            buffer = self.vector_table(root, 4, buffer_index)
            data_start, data_count = self.vector(buffer, 0)
            data = b'' if data_start is None else self.data[data_start:data_start + data_count]
            if len(data) != data_count:
                raise ValueError(f'Truncated tensor {i} data')
            tensors.append({'shape': self.int_vector(tensor, 0),
                            'dtype': dtype, 'data': data})
        return tensors


def bias_count(op):
    if op['type'] not in BIAS_OPS:
        return 0
    if len(op['inputs']) < 3 or op['inputs'][2] < 0:
        raise ValueError(f'OP {op["index"]} missing bias input')
    bias_id = op['inputs'][2]
    if bias_id not in op['tensors']:
        raise ValueError(f'OP {op["index"]} missing bias tensor metadata')
    shape = op['tensors'][bias_id]['shape']
    if len(shape) != 1 or shape[0] <= 0:
        raise ValueError(f'OP {op["index"]}: expected 1D bias tensor, got {shape}')
    return shape[0]


def allocate(ops):
    entries, cursor = [], 0
    for op in ops:
        if op['index'] in (0, 70, 71):
            continue
        n = bias_count(op)
        entries.append({'op': op, 'base': cursor if n else None, 'count': n})
        cursor += n
    if len(entries) != 69:
        raise ValueError('Expected 69 configured operators')
    return entries, cursor


def read_biases(entry, tensors):
    op = entry['op']
    if entry['count'] == 0:
        return []
    tid = op['inputs'][2]
    if tid >= len(tensors):
        raise ValueError(f'OP {op["index"]}: tensor {tid} out of range')
    t = tensors[tid]
    if t['dtype'] != 2:  # TFLite TensorType.INT32
        raise ValueError(f'OP {op["index"]}: bias tensor {tid} not int32 (type {t["dtype"]})')
    if t['shape'] != [entry['count']]:
        raise ValueError(f'OP {op["index"]}: bias shape mismatch: {t["shape"]}')
    if len(t['data']) != 4 * entry['count']:
        raise ValueError(f'OP {op["index"]}: bias byte count mismatch: {len(t["data"])}')
    return list(struct.unpack('<' + 'i' * entry['count'], t['data']))


def write_map(entries, total, path):
    lines = ['# Bias ROM address map', '',
             'Each address selects one signed **32-bit** bias value (two\'s-complement).',
             'Addresses are **word indices**, not byte offsets.',
             'Biases are stored in their original TFLite int32 accumulator units; do not rescale.',
             'Convolution/depthwise entries are in output-channel order; FC entries are in output-neuron order.', '',
             '| TFLite OP | Operation type | Bias base address | Number of entries |',
             '|---:|---|---:|---:|']
    for e in entries:
        base = str(e['base']) if e['base'] is not None else '—'
        lines.append(f'| {e["op"]["index"]} | {e["op"]["type"]} | {base} | {e["count"]} |')
    lines.extend(['', f'**Total: {total} entries × 32 bits = {total * 32} bits ({total * 4} bytes).**', '',
                  'OP 0 (input QUANTIZE), OP 70 (LOGISTIC), and OP 71 (output QUANTIZE) are excluded.',
                  'ADD, PAD, and MEAN have no bias entries.',
                  'A blank (—) base indicates no bias storage for that operation.'])
    Path(path).parent.mkdir(parents=True, exist_ok=True)
    Path(path).write_text('\n'.join(lines) + '\n', encoding='utf-8')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--raw', default='model_analysis_raw.txt')
    p.add_argument('--tflite', help='Full .tflite model required for bias values')
    p.add_argument('--mem', default='mem/bias.mem')
    p.add_argument('--map', default='docs/bias_address_map.md')
    args = p.parse_args()
    ops = parse_raw(args.raw)
    entries, total = allocate(ops)
    if args.tflite:
        tensors = FlatBuffer(args.tflite).tensor_metadata()
        values = []
        for e in entries:
            values.extend(read_biases(e, tensors))
        if len(values) != total:
            raise ValueError('Bias ROM record count mismatch')
        Path(args.mem).parent.mkdir(parents=True, exist_ok=True)
        Path(args.mem).write_text(''.join(f'{v & 0xFFFFFFFF:08X}\n' for v in values), encoding='ascii')
        print(f'Wrote {args.mem}: {len(values)} signed int32 bias records')
    else:
        print('No .tflite provided: only generating the address map')
    write_map(entries, total, args.map)
    print(f'Wrote {args.map}: {len(entries)} operations, {total} bias records')


if __name__ == '__main__':
    main()
