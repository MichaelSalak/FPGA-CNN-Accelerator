# Bias ROM address map

Each address selects one signed **32-bit** bias value (two's-complement).
Addresses are **word indices**, not byte offsets.
Biases are stored in their original TFLite int32 accumulator units; do not rescale.
Convolution/depthwise entries are in output-channel order; FC entries are in output-neuron order.

| TFLite OP | Operation type | Bias base address | Number of entries |
|---:|---|---:|---:|
| 1 | CONV_2D | 0 | 8 |
| 2 | DEPTHWISE_CONV_2D | 8 | 8 |
| 3 | CONV_2D | 16 | 8 |
| 4 | ADD | — | 0 |
| 5 | CONV_2D | 24 | 48 |
| 6 | PAD | — | 0 |
| 7 | DEPTHWISE_CONV_2D | 72 | 48 |
| 8 | CONV_2D | 120 | 8 |
| 9 | CONV_2D | 128 | 48 |
| 10 | DEPTHWISE_CONV_2D | 176 | 48 |
| 11 | CONV_2D | 224 | 8 |
| 12 | ADD | — | 0 |
| 13 | CONV_2D | 232 | 48 |
| 14 | PAD | — | 0 |
| 15 | DEPTHWISE_CONV_2D | 280 | 48 |
| 16 | CONV_2D | 328 | 8 |
| 17 | CONV_2D | 336 | 48 |
| 18 | DEPTHWISE_CONV_2D | 384 | 48 |
| 19 | CONV_2D | 432 | 8 |
| 20 | ADD | — | 0 |
| 21 | CONV_2D | 440 | 48 |
| 22 | DEPTHWISE_CONV_2D | 488 | 48 |
| 23 | CONV_2D | 536 | 8 |
| 24 | ADD | — | 0 |
| 25 | CONV_2D | 544 | 48 |
| 26 | PAD | — | 0 |
| 27 | DEPTHWISE_CONV_2D | 592 | 48 |
| 28 | CONV_2D | 640 | 8 |
| 29 | CONV_2D | 648 | 48 |
| 30 | DEPTHWISE_CONV_2D | 696 | 48 |
| 31 | CONV_2D | 744 | 8 |
| 32 | ADD | — | 0 |
| 33 | CONV_2D | 752 | 48 |
| 34 | DEPTHWISE_CONV_2D | 800 | 48 |
| 35 | CONV_2D | 848 | 8 |
| 36 | ADD | — | 0 |
| 37 | CONV_2D | 856 | 48 |
| 38 | DEPTHWISE_CONV_2D | 904 | 48 |
| 39 | CONV_2D | 952 | 8 |
| 40 | ADD | — | 0 |
| 41 | CONV_2D | 960 | 48 |
| 42 | DEPTHWISE_CONV_2D | 1008 | 48 |
| 43 | CONV_2D | 1056 | 16 |
| 44 | CONV_2D | 1072 | 96 |
| 45 | DEPTHWISE_CONV_2D | 1168 | 96 |
| 46 | CONV_2D | 1264 | 16 |
| 47 | ADD | — | 0 |
| 48 | CONV_2D | 1280 | 96 |
| 49 | DEPTHWISE_CONV_2D | 1376 | 96 |
| 50 | CONV_2D | 1472 | 16 |
| 51 | ADD | — | 0 |
| 52 | CONV_2D | 1488 | 96 |
| 53 | PAD | — | 0 |
| 54 | DEPTHWISE_CONV_2D | 1584 | 96 |
| 55 | CONV_2D | 1680 | 16 |
| 56 | CONV_2D | 1696 | 96 |
| 57 | DEPTHWISE_CONV_2D | 1792 | 96 |
| 58 | CONV_2D | 1888 | 16 |
| 59 | ADD | — | 0 |
| 60 | CONV_2D | 1904 | 96 |
| 61 | DEPTHWISE_CONV_2D | 2000 | 96 |
| 62 | CONV_2D | 2096 | 16 |
| 63 | ADD | — | 0 |
| 64 | CONV_2D | 2112 | 96 |
| 65 | DEPTHWISE_CONV_2D | 2208 | 96 |
| 66 | CONV_2D | 2304 | 32 |
| 67 | CONV_2D | 2336 | 1280 |
| 68 | MEAN | — | 0 |
| 69 | FULLY_CONNECTED | 3616 | 1 |

**Total: 3617 entries × 32 bits = 115744 bits (14468 bytes).**

OP 0 (input QUANTIZE), OP 70 (LOGISTIC), and OP 71 (output QUANTIZE) are excluded.
ADD, PAD, and MEAN have no bias entries.
A blank (—) base indicates no bias storage for that operation.
