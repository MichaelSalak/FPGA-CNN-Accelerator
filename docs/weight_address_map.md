# Weight ROM address map

Each ROM address selects one signed **8-bit** weight (two's-complement).
Addresses are **weight indices**, not byte offsets. The `.mem` file contains one 2-digit hex byte per line.
Weights are copied directly from the TFLite model without transposition.

**Indexing within each operation:**

- `CONV_2D` TFLite `[O, KH, KW, I]`: `base + (((o*KH + kh)*KW + kw)*I + i)`.
- `DEPTHWISE_CONV_2D` TFLite `[1, KH, KW, C]`: `base + ((kh*KW + kw)*C + c)`.
- `FULLY_CONNECTED` TFLite `[O, I]`: `base + o*I + i`.
- `ADD`, `PAD`, `MEAN`: no weight entries.

| TFLite OP | Operation type | Weight base address | Number of entries | Weight shape |
|---:|---|---:|---:|---|
| 1 | CONV_2D | 0 | 216 | `[8, 3, 3, 3]` |
| 2 | DEPTHWISE_CONV_2D | 216 | 72 | `[1, 3, 3, 8]` |
| 3 | CONV_2D | 288 | 64 | `[8, 1, 1, 8]` |
| 4 | ADD | — | 0 | `—` |
| 5 | CONV_2D | 352 | 384 | `[48, 1, 1, 8]` |
| 6 | PAD | — | 0 | `—` |
| 7 | DEPTHWISE_CONV_2D | 736 | 432 | `[1, 3, 3, 48]` |
| 8 | CONV_2D | 1168 | 384 | `[8, 1, 1, 48]` |
| 9 | CONV_2D | 1552 | 384 | `[48, 1, 1, 8]` |
| 10 | DEPTHWISE_CONV_2D | 1936 | 432 | `[1, 3, 3, 48]` |
| 11 | CONV_2D | 2368 | 384 | `[8, 1, 1, 48]` |
| 12 | ADD | — | 0 | `—` |
| 13 | CONV_2D | 2752 | 384 | `[48, 1, 1, 8]` |
| 14 | PAD | — | 0 | `—` |
| 15 | DEPTHWISE_CONV_2D | 3136 | 432 | `[1, 3, 3, 48]` |
| 16 | CONV_2D | 3568 | 384 | `[8, 1, 1, 48]` |
| 17 | CONV_2D | 3952 | 384 | `[48, 1, 1, 8]` |
| 18 | DEPTHWISE_CONV_2D | 4336 | 432 | `[1, 3, 3, 48]` |
| 19 | CONV_2D | 4768 | 384 | `[8, 1, 1, 48]` |
| 20 | ADD | — | 0 | `—` |
| 21 | CONV_2D | 5152 | 384 | `[48, 1, 1, 8]` |
| 22 | DEPTHWISE_CONV_2D | 5536 | 432 | `[1, 3, 3, 48]` |
| 23 | CONV_2D | 5968 | 384 | `[8, 1, 1, 48]` |
| 24 | ADD | — | 0 | `—` |
| 25 | CONV_2D | 6352 | 384 | `[48, 1, 1, 8]` |
| 26 | PAD | — | 0 | `—` |
| 27 | DEPTHWISE_CONV_2D | 6736 | 432 | `[1, 3, 3, 48]` |
| 28 | CONV_2D | 7168 | 384 | `[8, 1, 1, 48]` |
| 29 | CONV_2D | 7552 | 384 | `[48, 1, 1, 8]` |
| 30 | DEPTHWISE_CONV_2D | 7936 | 432 | `[1, 3, 3, 48]` |
| 31 | CONV_2D | 8368 | 384 | `[8, 1, 1, 48]` |
| 32 | ADD | — | 0 | `—` |
| 33 | CONV_2D | 8752 | 384 | `[48, 1, 1, 8]` |
| 34 | DEPTHWISE_CONV_2D | 9136 | 432 | `[1, 3, 3, 48]` |
| 35 | CONV_2D | 9568 | 384 | `[8, 1, 1, 48]` |
| 36 | ADD | — | 0 | `—` |
| 37 | CONV_2D | 9952 | 384 | `[48, 1, 1, 8]` |
| 38 | DEPTHWISE_CONV_2D | 10336 | 432 | `[1, 3, 3, 48]` |
| 39 | CONV_2D | 10768 | 384 | `[8, 1, 1, 48]` |
| 40 | ADD | — | 0 | `—` |
| 41 | CONV_2D | 11152 | 384 | `[48, 1, 1, 8]` |
| 42 | DEPTHWISE_CONV_2D | 11536 | 432 | `[1, 3, 3, 48]` |
| 43 | CONV_2D | 11968 | 768 | `[16, 1, 1, 48]` |
| 44 | CONV_2D | 12736 | 1536 | `[96, 1, 1, 16]` |
| 45 | DEPTHWISE_CONV_2D | 14272 | 864 | `[1, 3, 3, 96]` |
| 46 | CONV_2D | 15136 | 1536 | `[16, 1, 1, 96]` |
| 47 | ADD | — | 0 | `—` |
| 48 | CONV_2D | 16672 | 1536 | `[96, 1, 1, 16]` |
| 49 | DEPTHWISE_CONV_2D | 18208 | 864 | `[1, 3, 3, 96]` |
| 50 | CONV_2D | 19072 | 1536 | `[16, 1, 1, 96]` |
| 51 | ADD | — | 0 | `—` |
| 52 | CONV_2D | 20608 | 1536 | `[96, 1, 1, 16]` |
| 53 | PAD | — | 0 | `—` |
| 54 | DEPTHWISE_CONV_2D | 22144 | 864 | `[1, 3, 3, 96]` |
| 55 | CONV_2D | 23008 | 1536 | `[16, 1, 1, 96]` |
| 56 | CONV_2D | 24544 | 1536 | `[96, 1, 1, 16]` |
| 57 | DEPTHWISE_CONV_2D | 26080 | 864 | `[1, 3, 3, 96]` |
| 58 | CONV_2D | 26944 | 1536 | `[16, 1, 1, 96]` |
| 59 | ADD | — | 0 | `—` |
| 60 | CONV_2D | 28480 | 1536 | `[96, 1, 1, 16]` |
| 61 | DEPTHWISE_CONV_2D | 30016 | 864 | `[1, 3, 3, 96]` |
| 62 | CONV_2D | 30880 | 1536 | `[16, 1, 1, 96]` |
| 63 | ADD | — | 0 | `—` |
| 64 | CONV_2D | 32416 | 1536 | `[96, 1, 1, 16]` |
| 65 | DEPTHWISE_CONV_2D | 33952 | 864 | `[1, 3, 3, 96]` |
| 66 | CONV_2D | 34816 | 3072 | `[32, 1, 1, 96]` |
| 67 | CONV_2D | 37888 | 40960 | `[1280, 1, 1, 32]` |
| 68 | MEAN | — | 0 | `—` |
| 69 | FULLY_CONNECTED | 78848 | 1280 | `[1, 1280]` |

**Total: 80,128 entries × 8 bits = 80,128 bits (80,128 bytes).**

OP 0 (input QUANTIZE), OP 70 (LOGISTIC), and OP 71 (output QUANTIZE) are excluded.
A base of — means the operation has no weights.
The maximum address must fit the RTL weight address width.
