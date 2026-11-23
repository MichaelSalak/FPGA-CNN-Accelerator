#!/usr/bin/env python3
"""
Compare completed RTL activation dumps with TFLite reference layer by layer.

Command:
python compare_inference.py FPGA-CNN-Accelerator/cnn_project/cnn_project.sim/sim_1/behav/xsim/inference_outputs.txt `
    reference_outputs.txt --layers 1

"""
import argparse
from pathlib import Path
import sys


def parse_layers(path):
    """Return {layer_number: (opcode, [signed activation values])}.

    An interrupted trailing record without END_LAYER is ignored. Malformed
    completed records and duplicate layer numbers are rejected.
    """
    layers = {}
    record = None
    mode = None
    with path.open(encoding='utf-8') as stream:
        for lineno, raw in enumerate(stream, 1):
            line = raw.strip()
            if not line or line.startswith('#'):
                continue
            parts = line.split()
            key = parts[0]
            if key == 'LAYER':
                if len(parts) != 2:
                    raise ValueError(f'{path}:{lineno}: malformed LAYER')
                # An earlier unfinished record may be followed by a new one.
                number = int(parts[1])
                record = {'number': number, 'values': [], 'opcode': None,
                          'elements': None, 'data_seen': False}
                mode = 'header'
            elif record is None:
                # Ignore preamble outside records.
                continue
            elif key == 'END_LAYER':
                if len(parts) != 2 or int(parts[1]) != record['number']:
                    raise ValueError(f'{path}:{lineno}: END_LAYER number mismatch')
                if not record['data_seen'] or record['opcode'] is None or record['elements'] is None:
                    raise ValueError(f'{path}:{lineno}: incomplete layer header')
                if len(record['values']) != record['elements']:
                    raise ValueError(f"{path}:{lineno}: layer {record['number']} declared "
                                     f"{record['elements']} elements but has {len(record['values'])}")
                number = record['number']
                if number in layers:
                    raise ValueError(f'{path}:{lineno}: duplicate layer {number}')
                layers[number] = (record['opcode'], record['values'])
                record = None
                mode = None
            elif mode == 'data':
                if len(parts) != 1:
                    raise ValueError(f'{path}:{lineno}: expected one signed activation per line')
                try:
                    value = int(line, 10)
                except ValueError as exc:
                    raise ValueError(f'{path}:{lineno}: invalid activation {line!r}') from exc
                if not -128 <= value <= 127:
                    raise ValueError(f'{path}:{lineno}: activation outside INT8 range: {value}')
                record['values'].append(value)
            elif key == 'OPCODE' and len(parts) == 2:
                record['opcode'] = int(parts[1])
            elif key == 'ELEMENTS' and len(parts) == 2:
                record['elements'] = int(parts[1])
                if record['elements'] < 0:
                    raise ValueError(f'{path}:{lineno}: negative element count')
            elif key == 'DATA' and len(parts) == 1:
                record['data_seen'] = True
                mode = 'data'
            elif key in ('BUFFER', 'BASE'):
                pass  # RTL physical placement differs from logical TFLite output.
            else:
                raise ValueError(f'{path}:{lineno}: unexpected line {line!r}')
    if record is not None:
        print(f"Note: ignoring unfinished trailing layer {record['number']} in {path}")
    return layers



def parse_final_output(path):
    """Return (dtype, values) from a completed FINAL_OUTPUT record.

    Returns None if no completed record exists.
    """
    dtype = None
    elements = None
    values = []
    in_record = False
    in_data = False
    completed = False

    with path.open(encoding="utf-8") as stream:
        for lineno, raw in enumerate(stream, 1):
            line = raw.strip()

            if not line or line.startswith("#"):
                continue

            if line == "FINAL_OUTPUT":
                if in_record or completed:
                    raise ValueError(
                        f"{path}:{lineno}: duplicate FINAL_OUTPUT"
                    )
                in_record = True
                continue

            if not in_record:
                continue

            if line == "END_FINAL_OUTPUT":
                if dtype is None or elements is None or not in_data:
                    raise ValueError(
                        f"{path}:{lineno}: incomplete FINAL_OUTPUT"
                    )

                if len(values) != elements:
                    raise ValueError(
                        f"{path}:{lineno}: expected {elements} final values, "
                        f"found {len(values)}"
                    )

                completed = True
                in_record = False
                break

            if in_data:
                try:
                    value = int(line, 10)
                except ValueError as exc:
                    raise ValueError(
                        f"{path}:{lineno}: invalid final value {line!r}"
                    ) from exc

                if dtype == "UINT8" and not 0 <= value <= 255:
                    raise ValueError(
                        f"{path}:{lineno}: UINT8 value out of range: {value}"
                    )
                if dtype == "INT8" and not -128 <= value <= 127:
                    raise ValueError(
                        f"{path}:{lineno}: INT8 value out of range: {value}"
                    )

                values.append(value)

            else:
                parts = line.split()

                if len(parts) == 2 and parts[0] == "DTYPE":
                    dtype = parts[1].upper()
                    if dtype not in ("UINT8", "INT8"):
                        raise ValueError(
                            f"{path}:{lineno}: unsupported dtype {dtype}"
                        )

                elif len(parts) == 2 and parts[0] == "ELEMENTS":
                    elements = int(parts[1])
                    if elements < 1:
                        raise ValueError(
                            f"{path}:{lineno}: invalid element count"
                        )

                elif line == "DATA":
                    in_data = True

                else:
                    raise ValueError(
                        f"{path}:{lineno}: unexpected line {line!r}"
                    )

    return (dtype, values) if completed else None



def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('rtl', nargs='?', type=Path, default=Path('inference_outputs.txt'),
                        help='RTL output log (default: inference_outputs.txt)')
    parser.add_argument('reference', nargs='?', type=Path, default=Path('reference_outputs.txt'),
                        help='TFLite reference log (default: reference_outputs.txt)')
    parser.add_argument('--layers', type=int, default=None,
                        help='Compare only layers 1 through N (default: all completed RTL layers)')
    parser.add_argument('--max-examples', type=int, default=5,
                        help='Maximum mismatched element examples to print per layer')
    args = parser.parse_args()
    if args.layers is not None and args.layers < 1:
        parser.error('--layers must be at least 1')
    if args.max_examples < 0:
        parser.error('--max-examples cannot be negative')

    try:
        rtl = parse_layers(args.rtl)
        reference = parse_layers(args.reference)

        rtl_final = parse_final_output(args.rtl)
        ref_final = parse_final_output(args.reference)
    except (OSError, ValueError) as exc:
        print(f'ERROR: {exc}', file=sys.stderr)
        return 2

    if args.layers is not None:
        wanted = list(range(1, args.layers + 1))
    else:
        wanted = sorted(rtl)
        if not wanted:
            print('ERROR: no completed RTL layers found', file=sys.stderr)
            return 2
        if wanted != list(range(1, max(wanted) + 1)):
            print('ERROR: RTL completed layers are not contiguous from layer 1', file=sys.stderr)
            return 2

    failed = 0
    compared = 0
    total_mismatches = 0
    first_mismatch = None
    print(f'Checking {len(wanted)} layer(s): RTL={args.rtl} reference={args.reference}')
    for layer in wanted:
        if layer not in rtl or layer not in reference:
            missing = []
            if layer not in rtl:
                missing.append('RTL')
            if layer not in reference:
                missing.append('reference')
            print(f'LAYER {layer:02d}: FAIL (missing completed record in {", ".join(missing)})')
            failed += 1
            continue
        rtl_opcode, rtl_values = rtl[layer]
        ref_opcode, ref_values = reference[layer]
        problems = []
        if rtl_opcode != ref_opcode:
            problems.append(f'opcode RTL={rtl_opcode}, ref={ref_opcode}')
        if len(rtl_values) != len(ref_values):
            problems.append(f'element count RTL={len(rtl_values)}, ref={len(ref_values)}')
        mismatches = 0
        examples = []
        for index, (actual, expected) in enumerate(zip(rtl_values, ref_values)):
            if actual != expected:
                mismatches += 1
                if first_mismatch is None:
                    first_mismatch = (layer, index, actual, expected)
                if len(examples) < args.max_examples:
                    examples.append((index, actual, expected))
        total_mismatches += mismatches
        if problems or mismatches:
            failed += 1
            print(f'LAYER {layer:02d}: FAIL ({len(rtl_values)} RTL values, {mismatches} mismatches' +
                  (f'; {"; ".join(problems)}' if problems else '') + ')')
            for index, actual, expected in examples:
                print(f'  index {index}: RTL={actual}, TFLite={expected}')
        else:
            print(f'LAYER {layer:02d}: PASS ({len(rtl_values)} values)')
            compared += 1



    # Final inference output comparison
    final_failed = False

    # The RTL implements 69 configured layers, followed by
    # LOGISTIC and QUANTIZE postprocessing.
    check_final = args.layers is None or args.layers >= 69

    if check_final:
        print("\nFINAL INFERENCE OUTPUT")

        if rtl_final is None or ref_final is None:
            missing = []
            if rtl_final is None:
                missing.append("RTL")
            if ref_final is None:
                missing.append("TFLite")

            print(
                f"  FAIL: missing FINAL_OUTPUT record in "
                f"{', '.join(missing)}"
            )
            final_failed = True

        else:
            rtl_dtype, rtl_values = rtl_final
            ref_dtype, ref_values = ref_final

            if rtl_dtype != ref_dtype:
                print(
                    f"  FAIL: dtype mismatch "
                    f"RTL={rtl_dtype}, TFLite={ref_dtype}"
                )
                final_failed = True

            if len(rtl_values) != len(ref_values):
                print(
                    f"  FAIL: element count mismatch "
                    f"RTL={len(rtl_values)}, "
                    f"TFLite={len(ref_values)}"
                )
                final_failed = True

            for index, (actual, expected) in enumerate(
                zip(rtl_values, ref_values)
            ):
                match = actual == expected

                print(f"  Output {index}:")
                print(f"    RTL:    {actual}")
                print(f"    TFLite: {expected}")
                print(f"    Match:  {'PASS' if match else 'FAIL'}")

                if not match:
                    final_failed = True

            print(
                f"FINAL RESULT: "
                f"{'FAIL' if final_failed else 'PASS'}"
            )
    else:
        print("\nFINAL INFERENCE OUTPUT: SKIPPED (partial inference)")




    print(f'\nSUMMARY: {compared} passed, {failed} failed; {total_mismatches} differing activation values')
    if first_mismatch is not None:
        layer, index, actual, expected = first_mismatch
        print(f'FIRST MISMATCH: layer={layer} index={index} RTL={actual} TFLite={expected}')
    if failed or final_failed:
        return 1

    print("All requested layers match bit-for-bit.")

    if check_final:
        print("Final inference output matches TFLite exactly.")
    return 0


if __name__ == '__main__':
    sys.exit(main())
