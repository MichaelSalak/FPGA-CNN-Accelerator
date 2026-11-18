#!/usr/bin/env python3
"""Generate 332-bit layer_config.mem and an auditable Markdown address map.

Command:
python generate_layer_config.py `
--raw model_analysis_raw.txt `
--tflite ecto-trigger/model_weights/4/quant/4_int8.tflite `
--buffers activation_buffer_assignment.md `
--weights weight_address_map.md `
--biases bias_address_map.md `
--requant requant_address_map.md `
--mem layer_config.mem `
--map layer_config_address_map.md

Requires generate_bias.py alongside this script (FlatBuffer reader). No TensorFlow needed.
Bit packing is MSB-first in FIELDS order. Review opcode mapping and stride semantics
against the RTL controller before using in hardware.
"""

import argparse
import re
import struct
from pathlib import Path
from generate_bias import FlatBuffer, parse_raw

# (field, width), MSB to LSB; totals exactly 332 bits.
FIELDS = [
 ('opcode',4),('depthwise_mode',1),('kernel_size',3),
 ('input_buffer',2),('output_buffer',2),('input_base',18),('output_base',18),
 ('input_height',16),('input_width',16),('input_channels',16),
 ('output_height',16),('output_width',16),('output_channels',16),
 ('stride_2',1),('pad_top',2),('pad_bottom',2),('pad_left',2),('pad_right',2),
 ('input_row_stride',18),('output_col_step',18),('output_row_step',18),
 ('weight_base',17),('bias_base',12),('requant_base',18),
 ('input_zero_point',8),('output_zero_point',8),
 ('activation_min',8),('activation_max',8),
 ('input2_buffer',2),('input2_base',18),('input2_zero_point',8),('element_count',18),
]
assert sum(w for _,w in FIELDS)==332
OPCODES = {'CONV_2D':0,'DEPTHWISE_CONV_2D':0,'ADD':1,'PAD':2,'MEAN':3,'FULLY_CONNECTED':4}
BUF={'A':0,'B':1,'C':2}

def read_rom_map(path, column):
    rows={}
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        if not re.match(r'^\|\s*\d+\s*\|',line):continue
        cells=[x.strip() for x in line.strip().strip('|').split('|')]
        op=int(cells[0]); base=cells[column]
        rows[op]=0 if base in ('—','-','') else int(base.replace(',',''))
    if set(rows)!=set(range(1,70)):
        raise ValueError(f'{path}: expected OP 1..69, got {len(rows)}')
    return rows

def read_assignments(path):
    rows={}
    for line in Path(path).read_text(encoding='utf-8').splitlines():
        if not re.match(r'^\|\s*\d+\s*\|',line):continue
        c=[x.strip() for x in line.strip().strip('|').split('|')]
        def parse(s):
            m=re.fullmatch(r'(\d+)\s*/\s*([ABC])',s)
            return (int(m[1]),m[2]) if m else None
        rows[int(c[0])]={'a':parse(c[2]),'b':parse(c[3]),'out':parse(c[4])}
    if set(rows)!=set(range(1,70)):
        raise ValueError('Buffer assignment must contain OP 1..69')
    return rows

def flat_ops(fb):
    root=fb.u32(0); sg=fb.vector_table(root,2,0)
    return [fb.vector_table(sg,3,i) for i in range(72)]

def option(fb,table,field,fmt='B',default=0):
    loc=fb.field(table,field)
    return fb.unpack('<'+fmt,loc) if loc is not None else default

def get_options(fb,op_table):
    return fb.ref(fb.field(op_table,4))

def zp_and_scale(fb,tid):
    root=fb.u32(0); sg=fb.vector_table(root,2,0)
    t=fb.vector_table(sg,0,tid)
    q=fb.ref(fb.field(t,4))
    if q is None: raise ValueError(f'Tensor {tid} has no quantization parameters')
    starts,n=fb.vector(q,3) # zero_point: vector<int64>
    if n!=1:raise ValueError(f'Tensor {tid} zero point count {n} != 1')
    zp=fb.unpack('<q',starts)
    ss,m=fb.vector(q,2) # scale: vector<float32>
    if m!=1:raise ValueError(f'Tensor {tid} scale count {m} != 1')
    scale=fb.unpack('<f',ss)
    return int(zp),float(scale)

def shape_for(op,tid):
    if tid not in op['tensors']:raise ValueError(f'OP {op["index"]} missing tensor {tid}')
    return op['tensors'][tid]['shape']

def nhwc(shape):
    if len(shape)==4 and shape[0]==1:return tuple(shape[1:])
    if len(shape)==2 and shape[0]==1:return (1,1,shape[1])

def pad_constant(fb,tid):
    t=fb.tensor_metadata()[tid]
    if t['dtype']!=2 or t['shape']!=[4,2] or len(t['data'])!=32:
        raise ValueError('PAD tensor must be int32 [4,2]')
    return list(struct.unpack('<8i',t['data']))

def clamp_activation(zp,scale,fused):
    # TFLite ActivationFunctionType NONE=0, RELU=1, RELU_N1_TO_1=2, RELU6=3
    # use explicit rounding of real output value to quantized domain
    def quant(x):
        v=x/scale+zp
        return max(-128,min(127,int(v+0.5) if v>=0 else -int(-v+0.5)))
    if fused==0:return -128,127
    if fused==1:return quant(0),127
    if fused==2:return quant(-1),quant(1)
    if fused==3:return quant(0),quant(6)
    raise ValueError(f'Unsupported fused activation {fused}')

def pack(vals):
    value=0
    for name,width in FIELDS:
        v=vals[name]
        if not -(1<<(width-1))<=v<(1<<width):
            raise ValueError(f'{name}={v} does not fit {width} bits')
        value=(value<<width)|(v&((1<<width)-1))
    return f'{value:083X}'

def make_row(op, fb, op_table, assignment, bases, tensor_to_buffer):
    idx=op['index']; typ=op['type']; ids=op['inputs']; out=op['outputs'][0]
    a=assignment['a']; b=assignment['b']; dst=assignment['out']
    if not a or not dst or a[0]!=ids[0] or dst[0]!=out:raise ValueError(f'OP {idx} tensor mismatch in buffer assignment')
    if typ=='ADD' and (not b or b[0]!=ids[1]):raise ValueError(f'OP {idx} ADD second tensor mismatch')
    if typ!='ADD' and b:raise ValueError(f'OP {idx} unexpected second activation')
    if a[1]==dst[1] or (b and b[1] in (a[1],dst[1])):raise ValueError(f'OP {idx} aliases active buffers')
    ih,iw,ic=nhwc(shape_for(op,ids[0])); oh,ow,oc=nhwc(shape_for(op,out))
    iz,isc=zp_and_scale(fb,ids[0]); oz,osc=zp_and_scale(fb,out)
    opts=get_options(fb,op_table)
    stride=1; pt=pb=pl=pr=0; kernel=1; fused=0
    if typ in ('CONV_2D','DEPTHWISE_CONV_2D'):
        wshape=shape_for(op,ids[1]); kernel=wshape[1]
        if wshape[2]!=kernel or kernel not in (1,3):raise ValueError(f'OP {idx}: unsupported kernel {wshape}')
        if opts is None:raise ValueError(f'OP {idx} missing builtin options')
        padding=option(fb,opts,0)
        sw=option(fb,opts,1,'i',1);sh=option(fb,opts,2,'i',1)
        if sw!=sh or sw not in (1,2):raise ValueError(f'OP {idx}: unsupported stride {sh},{sw}')
        stride=sw
        fused=option(fb,opts,4 if typ=='DEPTHWISE_CONV_2D' else 3)
        # SAME=0 VALID=1; explicit PAD op may precede VALID convolution.
        if padding==0:
            total_h=max(0,(oh-1)*stride+kernel-ih)
            total_w=max(0,(ow-1)*stride+kernel-iw)
            pt=total_h//2; pb=total_h-pt
            pl=total_w//2; pr=total_w-pl
        elif padding!=1:raise ValueError(f'OP {idx}: unsupported padding enum {padding}')
    elif typ=='ADD':
        fused=option(fb,opts,0) if opts is not None else 0
    elif typ=='PAD':
        pads=pad_constant(fb,ids[1]);pt,pb,pl,pr=pads[2],pads[3],pads[4],pads[5]
        if pads[0]!=0 or pads[1]!=0 or pads[6]!=0 or pads[7]!=0:raise ValueError(f'OP {idx}: unsupported PAD batch/channel padding')
        if oh!=ih+pt+pads[3] or ow!=iw+pl+pads[5]:raise ValueError(f'OP {idx}: PAD geometry mismatch')
    elif typ=='MEAN':
        if (oh,ow,oc)!=(1,1,ic):raise ValueError(f'OP {idx}: unsupported MEAN shape')
    elif typ=='FULLY_CONNECTED':
        if ic<=0:raise ValueError(f'OP {idx}: invalid FC channels')
        fused=option(fb,opts,0) if opts is not None else 0
    else:raise ValueError(f'Unsupported OP {idx}: {typ}')
    amin,amax=clamp_activation(oz,osc,fused)
    # PAD/MEAN/FC are not convolution; their activation clamps are ignored by appropriate RTL.
    vals={name:0 for name,_ in FIELDS}
    vals.update(opcode=OPCODES[typ],depthwise_mode=int(typ=='DEPTHWISE_CONV_2D'),kernel_size=kernel,
        input_buffer=BUF[a[1]],output_buffer=BUF[dst[1]],
        input_height=ih,input_width=iw,input_channels=ic,output_height=oh,output_width=ow,output_channels=oc,
        stride_2=int(stride==2),pad_top=pt,pad_bottom=pb,pad_left=pl,pad_right=pr,
        input_row_stride=iw*ic,output_col_step=oc,output_row_step=ow*oc,
        weight_base=bases['weights'][idx],bias_base=bases['biases'][idx],requant_base=bases['requant'][idx],
        input_zero_point=iz,output_zero_point=oz,activation_min=amin,activation_max=amax,
        input2_buffer=BUF[b[1]] if b else 0,
        input2_zero_point=zp_and_scale(fb,ids[1])[0] if b else 0,
        element_count=oh*ow*oc if typ=='ADD' else 0)
    return vals, (ih,iw,ic), (oh,ow,oc)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--raw',default='model_analysis_raw.txt');p.add_argument('--tflite',required=True)
    p.add_argument('--buffers',default='docs/activation_buffer_assignment.md')
    p.add_argument('--weights',default='docs/weight_address_map.md')
    p.add_argument('--biases',default='docs/bias_address_map.md')
    p.add_argument('--requant',default='docs/requant_address_map.md')
    p.add_argument('--mem',default='mem/layer_config.mem')
    p.add_argument('--map',default='docs/layer_config_address_map.md')
    args=p.parse_args()
    ops=parse_raw(args.raw);fb=FlatBuffer(args.tflite);tables=flat_ops(fb)
    alloc=read_assignments(args.buffers)
    bases={k:read_rom_map(getattr(args,k),2) for k in ('weights','biases','requant')}
    records=[];rows=[];locations={0:'A'}
    # Verify liveness: never overwrite a tensor still needed by future operations.
    future={tid for op in ops[1:70] for tid in op['inputs'][:(2 if op['type']=='ADD' else 1)]}
    for op in ops[1:70]:
        idx=op['index']; asg=alloc[idx]
        for key in ('a','b'):
            item=asg[key]
            if item and locations.get(item[0])!=item[1]:raise ValueError(f'OP {idx}: tensor {item[0]} not live in {item[1]}')
        outbuf=asg['out'][1]
        for tid,buf in locations.items():
            if buf==outbuf and any(tid in later['inputs'][:(2 if later['type']=='ADD' else 1)] for later in ops[idx+1:70]):
                raise ValueError(f'OP {idx}: output overwrites live tensor {tid} in {buf}')
        vals,ish,osh=make_row(op,fb,tables[idx],asg,bases,locations)
        records.append(pack(vals));rows.append((idx,op['type'],asg,ish,osh,vals))
        locations={tid:buf for tid,buf in locations.items() if buf!=outbuf}
        locations[op['outputs'][0]]=outbuf
    assert len(records)==69 and all(len(r)==83 for r in records)
    Path(args.mem).parent.mkdir(parents=True,exist_ok=True)
    Path(args.mem).write_text('\n'.join(records)+'\n',encoding='ascii')
    lines=['# Layer configuration ROM address map','',
       'Each record is 332 bits (83 hexadecimal digits); ROM address = TFLite OP number minus 1.',
       'Initial tensor 0 must be preloaded into buffer A. All activation bases are zero.',
       'Buffers A=0, B=1, C=2. Unused parameter addresses and second-input fields are zero.',
       'Opcode mapping: CONV and DW=0 (depthwise_mode distinguishes), ADD=1, PAD=2, MEAN=3, FC=4.',
       'The configured input_row_stride is input_width * input_channels; output_col_step is output_channels;',
       'output_row_step is output_width * output_channels.',
       'PAD stores all four explicit padding values; convolution padding fields describe implicit SAME padding.',
       '', '| ROM | TFLite OP | Type | Input | Input 2 | Output | Input H×W×C | Output H×W×C | Weight base | Bias base | Requant base |',
       '|---:|---:|---|---|---|---|---|---|---:|---:|---:|']
    for i,typ,asg,ish,osh,v in rows:
        label=lambda item: f'{item[0]}/{item[1]}' if item else '—'
        lines.append(f'| {i-1} | {i} | {typ} | {label(asg["a"])} | {label(asg["b"])} | {label(asg["out"])} | {"×".join(map(str,ish))} | {"×".join(map(str,osh))} | {v["weight_base"]} | {v["bias_base"]} | {v["requant_base"]} |')
    lines.extend(['','## Bit fields (MSB first)','', '| Field | Bits | [MSB:LSB] |','|---|---:|---|'])
    high=sum(w for _,w in FIELDS)-1
    for name,w in FIELDS:
        lines.append(f'| `{name}` | {w} | [{high}:{high-w+1}] |');high-=w
    lines.extend(['',f'**Total: {len(records)} × 332 = {len(records)*332:,} bits.**',
       '', '## Notes', '- `activation_min`/`activation_max` reflect fused activation options (NONE, RELU, RELU_N1_TO_1, RELU6).',
       '- `PAD` requires writing input zero-point into padded cells.',
       '- `MEAN` reduction count and requant multiplier are supplied separately by the MEAN module and requant ROM.', ''])
    Path(args.map).parent.mkdir(parents=True,exist_ok=True)
    Path(args.map).write_text('\n'.join(lines),encoding='utf-8')
    print(f'Wrote {args.mem}: {len(records)} x 332-bit records')
    print(f'Wrote {args.map}: {len(rows)} operator addresses')
if __name__=='__main__':main()
