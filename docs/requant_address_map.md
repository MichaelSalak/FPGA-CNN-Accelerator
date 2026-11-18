# Requantization ROM address map

Each ROM address selects one 40-bit `{multiplier[31:0], shift[7:0]}` record.
The shift is a signed int8 in two's-complement; positive values denote left shifts.
Addresses are **record indices**, not byte offsets.

| TFLite OP | Operation type | Requant base address | Number of entries |
|---:|---|---:|---:|
| 1 | CONV_2D | 0 | 8 |
| 2 | DEPTHWISE_CONV_2D | 8 | 8 |
| 3 | CONV_2D | 16 | 8 |
| 4 | ADD | 24 | 3 |
| 5 | CONV_2D | 27 | 48 |
| 6 | PAD | — | 0 |
| 7 | DEPTHWISE_CONV_2D | 75 | 48 |
| 8 | CONV_2D | 123 | 8 |
| 9 | CONV_2D | 131 | 48 |
| 10 | DEPTHWISE_CONV_2D | 179 | 48 |
| 11 | CONV_2D | 227 | 8 |
| 12 | ADD | 235 | 3 |
| 13 | CONV_2D | 238 | 48 |
| 14 | PAD | — | 0 |
| 15 | DEPTHWISE_CONV_2D | 286 | 48 |
| 16 | CONV_2D | 334 | 8 |
| 17 | CONV_2D | 342 | 48 |
| 18 | DEPTHWISE_CONV_2D | 390 | 48 |
| 19 | CONV_2D | 438 | 8 |
| 20 | ADD | 446 | 3 |
| 21 | CONV_2D | 449 | 48 |
| 22 | DEPTHWISE_CONV_2D | 497 | 48 |
| 23 | CONV_2D | 545 | 8 |
| 24 | ADD | 553 | 3 |
| 25 | CONV_2D | 556 | 48 |
| 26 | PAD | — | 0 |
| 27 | DEPTHWISE_CONV_2D | 604 | 48 |
| 28 | CONV_2D | 652 | 8 |
| 29 | CONV_2D | 660 | 48 |
| 30 | DEPTHWISE_CONV_2D | 708 | 48 |
| 31 | CONV_2D | 756 | 8 |
| 32 | ADD | 764 | 3 |
| 33 | CONV_2D | 767 | 48 |
| 34 | DEPTHWISE_CONV_2D | 815 | 48 |
| 35 | CONV_2D | 863 | 8 |
| 36 | ADD | 871 | 3 |
| 37 | CONV_2D | 874 | 48 |
| 38 | DEPTHWISE_CONV_2D | 922 | 48 |
| 39 | CONV_2D | 970 | 8 |
| 40 | ADD | 978 | 3 |
| 41 | CONV_2D | 981 | 48 |
| 42 | DEPTHWISE_CONV_2D | 1029 | 48 |
| 43 | CONV_2D | 1077 | 16 |
| 44 | CONV_2D | 1093 | 96 |
| 45 | DEPTHWISE_CONV_2D | 1189 | 96 |
| 46 | CONV_2D | 1285 | 16 |
| 47 | ADD | 1301 | 3 |
| 48 | CONV_2D | 1304 | 96 |
| 49 | DEPTHWISE_CONV_2D | 1400 | 96 |
| 50 | CONV_2D | 1496 | 16 |
| 51 | ADD | 1512 | 3 |
| 52 | CONV_2D | 1515 | 96 |
| 53 | PAD | — | 0 |
| 54 | DEPTHWISE_CONV_2D | 1611 | 96 |
| 55 | CONV_2D | 1707 | 16 |
| 56 | CONV_2D | 1723 | 96 |
| 57 | DEPTHWISE_CONV_2D | 1819 | 96 |
| 58 | CONV_2D | 1915 | 16 |
| 59 | ADD | 1931 | 3 |
| 60 | CONV_2D | 1934 | 96 |
| 61 | DEPTHWISE_CONV_2D | 2030 | 96 |
| 62 | CONV_2D | 2126 | 16 |
| 63 | ADD | 2142 | 3 |
| 64 | CONV_2D | 2145 | 96 |
| 65 | DEPTHWISE_CONV_2D | 2241 | 96 |
| 66 | CONV_2D | 2337 | 32 |
| 67 | CONV_2D | 2369 | 1280 |
| 68 | MEAN | 3649 | 1 |
| 69 | FULLY_CONNECTED | 3650 | 1 |

**Total: 3651 records × 40 bits = 146040 bits (18255 bytes).**

OP 0 (input QUANTIZE), OP 70 (LOGISTIC), and OP 71 (output QUANTIZE) are excluded.
MEAN incorporates division by 4×5=20 in its single multiplier.
ADD record order: input A, input B, output.
