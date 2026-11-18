# Three-buffer activation assignment (OP 1–69)

Each tensor occupies one entire buffer at base address 0. Initial tensor 0 is preloaded into A. A, B, C are interchangeable. The allocation preserves each tensor through its final consumer; outputs never share a buffer with current inputs.

| OP | Type | Input tensor / buffer | Input 2 tensor / buffer | Output tensor / buffer |
|---:|---|---|---|---|
| 1 | CONV | 0 / A | — | 110 / B |
| 2 | DW | 110 / B | — | 111 / A |
| 3 | CONV | 111 / A | — | 112 / C |
| 4 | ADD | 110 / B | 112 / C | 113 / A |
| 5 | CONV | 113 / A | — | 114 / B |
| 6 | PAD | 114 / B | — | 115 / A |
| 7 | DW | 115 / A | — | 116 / B |
| 8 | CONV | 116 / B | — | 117 / A |
| 9 | CONV | 117 / A | — | 118 / B |
| 10 | DW | 118 / B | — | 119 / C |
| 11 | CONV | 119 / C | — | 120 / B |
| 12 | ADD | 117 / A | 120 / B | 121 / C |
| 13 | CONV | 121 / C | — | 122 / A |
| 14 | PAD | 122 / A | — | 123 / B |
| 15 | DW | 123 / B | — | 124 / A |
| 16 | CONV | 124 / A | — | 125 / B |
| 17 | CONV | 125 / B | — | 126 / A |
| 18 | DW | 126 / A | — | 127 / C |
| 19 | CONV | 127 / C | — | 128 / A |
| 20 | ADD | 125 / B | 128 / A | 129 / C |
| 21 | CONV | 129 / C | — | 130 / A |
| 22 | DW | 130 / A | — | 131 / B |
| 23 | CONV | 131 / B | — | 132 / A |
| 24 | ADD | 129 / C | 132 / A | 133 / B |
| 25 | CONV | 133 / B | — | 134 / A |
| 26 | PAD | 134 / A | — | 135 / B |
| 27 | DW | 135 / B | — | 136 / A |
| 28 | CONV | 136 / A | — | 137 / B |
| 29 | CONV | 137 / B | — | 138 / A |
| 30 | DW | 138 / A | — | 139 / C |
| 31 | CONV | 139 / C | — | 140 / A |
| 32 | ADD | 137 / B | 140 / A | 141 / C |
| 33 | CONV | 141 / C | — | 142 / A |
| 34 | DW | 142 / A | — | 143 / B |
| 35 | CONV | 143 / B | — | 144 / A |
| 36 | ADD | 141 / C | 144 / A | 145 / B |
| 37 | CONV | 145 / B | — | 146 / A |
| 38 | DW | 146 / A | — | 147 / C |
| 39 | CONV | 147 / C | — | 148 / A |
| 40 | ADD | 145 / B | 148 / A | 149 / C |
| 41 | CONV | 149 / C | — | 150 / A |
| 42 | DW | 150 / A | — | 151 / B |
| 43 | CONV | 151 / B | — | 152 / A |
| 44 | CONV | 152 / A | — | 153 / B |
| 45 | DW | 153 / B | — | 154 / C |
| 46 | CONV | 154 / C | — | 155 / B |
| 47 | ADD | 152 / A | 155 / B | 156 / C |
| 48 | CONV | 156 / C | — | 157 / A |
| 49 | DW | 157 / A | — | 158 / B |
| 50 | CONV | 158 / B | — | 159 / A |
| 51 | ADD | 156 / C | 159 / A | 160 / B |
| 52 | CONV | 160 / B | — | 161 / A |
| 53 | PAD | 161 / A | — | 162 / B |
| 54 | DW | 162 / B | — | 163 / A |
| 55 | CONV | 163 / A | — | 164 / B |
| 56 | CONV | 164 / B | — | 165 / A |
| 57 | DW | 165 / A | — | 166 / C |
| 58 | CONV | 166 / C | — | 167 / A |
| 59 | ADD | 164 / B | 167 / A | 168 / C |
| 60 | CONV | 168 / C | — | 169 / A |
| 61 | DW | 169 / A | — | 170 / B |
| 62 | CONV | 170 / B | — | 171 / A |
| 63 | ADD | 168 / C | 171 / A | 172 / B |
| 64 | CONV | 172 / B | — | 173 / A |
| 65 | DW | 173 / A | — | 174 / B |
| 66 | CONV | 174 / B | — | 175 / A |
| 67 | CONV | 175 / A | — | 176 / B |
| 68 | MEAN | 176 / B | — | 177 / A |
| 69 | FC | 177 / A | — | 178 / B |
