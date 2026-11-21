# Layer configuration ROM address map

Each record is 259 bits (65 hexadecimal digits); ROM address = TFLite OP number minus 1.
Initial tensor 0 must be preloaded into buffer A. All activation bases are zero.
Buffers A=0, B=1, C=2. Unused parameter addresses and second-input fields are zero.
Opcode mapping: CONV and DW=0 (depthwise_mode distinguishes), ADD=1, PAD=2, MEAN=3, FC=4.
For CONV/DW: input_row_stride = input_width * input_channels;
output_col_step = stride * input_channels; output_row_step = stride * input_row_stride.
For non-convolution operators, the step fields are unused.
PAD stores all four explicit padding values; convolution padding fields describe implicit SAME padding.

| ROM | TFLite OP | Type | Input | Input 2 | Output | Input H×W×C | Output H×W×C | Weight base | Bias base | Requant base |
|---:|---:|---|---|---|---|---|---|---:|---:|---:|
| 0 | 1 | CONV_2D | 0/A | — | 110/B | 120×160×3 | 60×80×8 | 0 | 0 | 0 |
| 1 | 2 | DEPTHWISE_CONV_2D | 110/B | — | 111/A | 60×80×8 | 60×80×8 | 216 | 8 | 8 |
| 2 | 3 | CONV_2D | 111/A | — | 112/C | 60×80×8 | 60×80×8 | 288 | 16 | 16 |
| 3 | 4 | ADD | 110/B | 112/C | 113/A | 60×80×8 | 60×80×8 | 0 | 0 | 24 |
| 4 | 5 | CONV_2D | 113/A | — | 114/B | 60×80×8 | 60×80×48 | 352 | 24 | 27 |
| 5 | 6 | PAD | 114/B | — | 115/A | 60×80×48 | 61×81×48 | 0 | 0 | 0 |
| 6 | 7 | DEPTHWISE_CONV_2D | 115/A | — | 116/B | 61×81×48 | 30×40×48 | 736 | 72 | 75 |
| 7 | 8 | CONV_2D | 116/B | — | 117/A | 30×40×48 | 30×40×8 | 1168 | 120 | 123 |
| 8 | 9 | CONV_2D | 117/A | — | 118/B | 30×40×8 | 30×40×48 | 1552 | 128 | 131 |
| 9 | 10 | DEPTHWISE_CONV_2D | 118/B | — | 119/C | 30×40×48 | 30×40×48 | 1936 | 176 | 179 |
| 10 | 11 | CONV_2D | 119/C | — | 120/B | 30×40×48 | 30×40×8 | 2368 | 224 | 227 |
| 11 | 12 | ADD | 117/A | 120/B | 121/C | 30×40×8 | 30×40×8 | 0 | 0 | 235 |
| 12 | 13 | CONV_2D | 121/C | — | 122/A | 30×40×8 | 30×40×48 | 2752 | 232 | 238 |
| 13 | 14 | PAD | 122/A | — | 123/B | 30×40×48 | 31×41×48 | 0 | 0 | 0 |
| 14 | 15 | DEPTHWISE_CONV_2D | 123/B | — | 124/A | 31×41×48 | 15×20×48 | 3136 | 280 | 286 |
| 15 | 16 | CONV_2D | 124/A | — | 125/B | 15×20×48 | 15×20×8 | 3568 | 328 | 334 |
| 16 | 17 | CONV_2D | 125/B | — | 126/A | 15×20×8 | 15×20×48 | 3952 | 336 | 342 |
| 17 | 18 | DEPTHWISE_CONV_2D | 126/A | — | 127/C | 15×20×48 | 15×20×48 | 4336 | 384 | 390 |
| 18 | 19 | CONV_2D | 127/C | — | 128/A | 15×20×48 | 15×20×8 | 4768 | 432 | 438 |
| 19 | 20 | ADD | 125/B | 128/A | 129/C | 15×20×8 | 15×20×8 | 0 | 0 | 446 |
| 20 | 21 | CONV_2D | 129/C | — | 130/A | 15×20×8 | 15×20×48 | 5152 | 440 | 449 |
| 21 | 22 | DEPTHWISE_CONV_2D | 130/A | — | 131/B | 15×20×48 | 15×20×48 | 5536 | 488 | 497 |
| 22 | 23 | CONV_2D | 131/B | — | 132/A | 15×20×48 | 15×20×8 | 5968 | 536 | 545 |
| 23 | 24 | ADD | 129/C | 132/A | 133/B | 15×20×8 | 15×20×8 | 0 | 0 | 553 |
| 24 | 25 | CONV_2D | 133/B | — | 134/A | 15×20×8 | 15×20×48 | 6352 | 544 | 556 |
| 25 | 26 | PAD | 134/A | — | 135/B | 15×20×48 | 17×21×48 | 0 | 0 | 0 |
| 26 | 27 | DEPTHWISE_CONV_2D | 135/B | — | 136/A | 17×21×48 | 8×10×48 | 6736 | 592 | 604 |
| 27 | 28 | CONV_2D | 136/A | — | 137/B | 8×10×48 | 8×10×8 | 7168 | 640 | 652 |
| 28 | 29 | CONV_2D | 137/B | — | 138/A | 8×10×8 | 8×10×48 | 7552 | 648 | 660 |
| 29 | 30 | DEPTHWISE_CONV_2D | 138/A | — | 139/C | 8×10×48 | 8×10×48 | 7936 | 696 | 708 |
| 30 | 31 | CONV_2D | 139/C | — | 140/A | 8×10×48 | 8×10×8 | 8368 | 744 | 756 |
| 31 | 32 | ADD | 137/B | 140/A | 141/C | 8×10×8 | 8×10×8 | 0 | 0 | 764 |
| 32 | 33 | CONV_2D | 141/C | — | 142/A | 8×10×8 | 8×10×48 | 8752 | 752 | 767 |
| 33 | 34 | DEPTHWISE_CONV_2D | 142/A | — | 143/B | 8×10×48 | 8×10×48 | 9136 | 800 | 815 |
| 34 | 35 | CONV_2D | 143/B | — | 144/A | 8×10×48 | 8×10×8 | 9568 | 848 | 863 |
| 35 | 36 | ADD | 141/C | 144/A | 145/B | 8×10×8 | 8×10×8 | 0 | 0 | 871 |
| 36 | 37 | CONV_2D | 145/B | — | 146/A | 8×10×8 | 8×10×48 | 9952 | 856 | 874 |
| 37 | 38 | DEPTHWISE_CONV_2D | 146/A | — | 147/C | 8×10×48 | 8×10×48 | 10336 | 904 | 922 |
| 38 | 39 | CONV_2D | 147/C | — | 148/A | 8×10×48 | 8×10×8 | 10768 | 952 | 970 |
| 39 | 40 | ADD | 145/B | 148/A | 149/C | 8×10×8 | 8×10×8 | 0 | 0 | 978 |
| 40 | 41 | CONV_2D | 149/C | — | 150/A | 8×10×8 | 8×10×48 | 11152 | 960 | 981 |
| 41 | 42 | DEPTHWISE_CONV_2D | 150/A | — | 151/B | 8×10×48 | 8×10×48 | 11536 | 1008 | 1029 |
| 42 | 43 | CONV_2D | 151/B | — | 152/A | 8×10×48 | 8×10×16 | 11968 | 1056 | 1077 |
| 43 | 44 | CONV_2D | 152/A | — | 153/B | 8×10×16 | 8×10×96 | 12736 | 1072 | 1093 |
| 44 | 45 | DEPTHWISE_CONV_2D | 153/B | — | 154/C | 8×10×96 | 8×10×96 | 14272 | 1168 | 1189 |
| 45 | 46 | CONV_2D | 154/C | — | 155/B | 8×10×96 | 8×10×16 | 15136 | 1264 | 1285 |
| 46 | 47 | ADD | 152/A | 155/B | 156/C | 8×10×16 | 8×10×16 | 0 | 0 | 1301 |
| 47 | 48 | CONV_2D | 156/C | — | 157/A | 8×10×16 | 8×10×96 | 16672 | 1280 | 1304 |
| 48 | 49 | DEPTHWISE_CONV_2D | 157/A | — | 158/B | 8×10×96 | 8×10×96 | 18208 | 1376 | 1400 |
| 49 | 50 | CONV_2D | 158/B | — | 159/A | 8×10×96 | 8×10×16 | 19072 | 1472 | 1496 |
| 50 | 51 | ADD | 156/C | 159/A | 160/B | 8×10×16 | 8×10×16 | 0 | 0 | 1512 |
| 51 | 52 | CONV_2D | 160/B | — | 161/A | 8×10×16 | 8×10×96 | 20608 | 1488 | 1515 |
| 52 | 53 | PAD | 161/A | — | 162/B | 8×10×96 | 9×11×96 | 0 | 0 | 0 |
| 53 | 54 | DEPTHWISE_CONV_2D | 162/B | — | 163/A | 9×11×96 | 4×5×96 | 22144 | 1584 | 1611 |
| 54 | 55 | CONV_2D | 163/A | — | 164/B | 4×5×96 | 4×5×16 | 23008 | 1680 | 1707 |
| 55 | 56 | CONV_2D | 164/B | — | 165/A | 4×5×16 | 4×5×96 | 24544 | 1696 | 1723 |
| 56 | 57 | DEPTHWISE_CONV_2D | 165/A | — | 166/C | 4×5×96 | 4×5×96 | 26080 | 1792 | 1819 |
| 57 | 58 | CONV_2D | 166/C | — | 167/A | 4×5×96 | 4×5×16 | 26944 | 1888 | 1915 |
| 58 | 59 | ADD | 164/B | 167/A | 168/C | 4×5×16 | 4×5×16 | 0 | 0 | 1931 |
| 59 | 60 | CONV_2D | 168/C | — | 169/A | 4×5×16 | 4×5×96 | 28480 | 1904 | 1934 |
| 60 | 61 | DEPTHWISE_CONV_2D | 169/A | — | 170/B | 4×5×96 | 4×5×96 | 30016 | 2000 | 2030 |
| 61 | 62 | CONV_2D | 170/B | — | 171/A | 4×5×96 | 4×5×16 | 30880 | 2096 | 2126 |
| 62 | 63 | ADD | 168/C | 171/A | 172/B | 4×5×16 | 4×5×16 | 0 | 0 | 2142 |
| 63 | 64 | CONV_2D | 172/B | — | 173/A | 4×5×16 | 4×5×96 | 32416 | 2112 | 2145 |
| 64 | 65 | DEPTHWISE_CONV_2D | 173/A | — | 174/B | 4×5×96 | 4×5×96 | 33952 | 2208 | 2241 |
| 65 | 66 | CONV_2D | 174/B | — | 175/A | 4×5×96 | 4×5×32 | 34816 | 2304 | 2337 |
| 66 | 67 | CONV_2D | 175/A | — | 176/B | 4×5×32 | 4×5×1280 | 37888 | 2336 | 2369 |
| 67 | 68 | MEAN | 176/B | — | 177/A | 4×5×1280 | 1×1×1280 | 0 | 0 | 3649 |
| 68 | 69 | FULLY_CONNECTED | 177/A | — | 178/B | 1×1×1280 | 1×1×1 | 78848 | 3616 | 3650 |

## Bit fields (MSB first)

| Field | Bits | [MSB:LSB] | Width derivation |
|---|---:|---|---|
| `opcode` | 3 | [258:256] | 5 opcode values (0-4); 3 bits encode up to 8 |
| `depthwise_mode` | 1 | [255:255] | Boolean: standard vs. depthwise convolution |
| `kernel_size` | 2 | [254:253] | Kernel dimension is 1 or 3; stored literally |
| `input_buffer` | 2 | [252:251] | 3 activation buffers: A, B, C |
| `output_buffer` | 2 | [250:249] | 3 activation buffers: A, B, C |
| `input_base` | 18 | [248:231] | 18-bit activation address interface; current bases are 0 |
| `output_base` | 18 | [230:213] | 18-bit activation address interface; current bases are 0 |
| `input_height` | 7 | [212:206] | Maximum input height = 120 |
| `input_width` | 8 | [205:198] | Maximum input width = 160 |
| `input_channels` | 11 | [197:187] | Maximum input channels = 1280 |
| `output_height` | 6 | [186:181] | Maximum output height = 61 (PAD output) |
| `output_width` | 7 | [180:174] | Maximum output width = 81 (PAD output) |
| `output_channels` | 11 | [173:163] | Maximum output channels = 1280 |
| `stride_2` | 1 | [162:162] | Boolean: stride 1 or 2 |
| `pad_top` | 2 | [161:160] | 2-bit padding interface; model values fit |
| `pad_bottom` | 2 | [159:158] | 2-bit padding interface; model values fit |
| `pad_left` | 2 | [157:156] | 2-bit padding interface; model values fit |
| `pad_right` | 2 | [155:154] | 2-bit padding interface; model values fit |
| `input_row_stride` | 13 | [153:141] | Maximum input_width * input_channels = 6400 |
| `output_col_step` | 11 | [140:130] | Input-window column step = stride * input_channels; 11-bit model bound |
| `output_row_step` | 13 | [129:117] | Input-window row step = stride * input_width * input_channels; 13-bit model bound |
| `weight_base` | 17 | [116:100] | Maximum mapped weight base = 78848 |
| `bias_base` | 12 | [99:88] | Maximum mapped bias base = 3616 |
| `requant_base` | 12 | [87:76] | Maximum mapped requant base = 3650 |
| `input_zero_point` | 8 | [75:68] | Signed int8 tensor quantization parameter |
| `output_zero_point` | 8 | [67:60] | Signed int8 tensor quantization parameter |
| `activation_min` | 8 | [59:52] | Signed int8 output clamp |
| `activation_max` | 8 | [51:44] | Signed int8 output clamp |
| `input2_buffer` | 2 | [43:42] | 3 activation buffers: A, B, C |
| `input2_base` | 18 | [41:24] | 18-bit activation address interface; current bases are 0 |
| `input2_zero_point` | 8 | [23:16] | Signed int8 tensor quantization parameter |
| `element_count` | 16 | [15:0] | Maximum ADD H * W * C = 38400 |

**Total: 69 × 259 = 17,871 bits.**

## Notes
- Width derivations reflect the current 69-operation model and/or retained RTL interface widths.
- Address arithmetic in the RTL must remain wide enough for full activation addresses.
- `activation_min`/`activation_max` reflect fused activation options (NONE, RELU, RELU_N1_TO_1, RELU6).
- `PAD` requires writing input zero-point into padded cells.
- `MEAN` reduction count and requant multiplier are supplied separately by the MEAN module and requant ROM.
