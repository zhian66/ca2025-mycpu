// SPDX-License-Identifier: MIT
// MyCPU is freely redistributable under the MIT License. See the file
// "LICENSE" for information on usage and redistribution of this file.

/* ============= Fast Rsqrt Implementation ============= */

typedef unsigned int uint32_t;
typedef unsigned long long uint64_t;
typedef unsigned short uint16_t;

static int clz(uint32_t x) {
    if (!x) return 32; /* Special case: no bits set */
    int n = 0;
    if (!(x & 0xFFFF0000)) { n += 16; x <<= 16; }
    if (!(x & 0xFF000000)) { n += 8; x <<= 8; }
    if (!(x & 0xF0000000)) { n += 4; x <<= 4; }
    if (!(x & 0xC0000000)) { n += 2; x <<= 2; }
    if (!(x & 0x80000000)) { n += 1; }
    return n;
}

static const uint16_t rsqrt_table[32] = {
    65535, 46341, 32768, 23170, 16384,  /* 2^0 to 2^4 */
    11585,  8192,  5793,  4096,  2896,  /* 2^5 to 2^9 */
     2048,  1448,  1024,   724,   512,  /* 2^10 to 2^14 */
      362,   256,   181,   128,    90,  /* 2^15 to 2^19 */
       64,    45,    32,    23,    16,  /* 2^20 to 2^24 */
       11,     8,     6,     4,     3,  /* 2^25 to 2^29 */
        2,     1
};

static uint64_t mul32(uint32_t a, uint32_t b) {
    uint64_t r = 0;
    for (int i = 0; i < 32; i++) {
        if (b & (1 << i))
            r += (uint64_t)a << i;
    }
    return r;
}

uint32_t fast_rsqrt(uint32_t x) {
    /* Handle edge cases */
    if (x == 0) return 0xFFFFFFFF; /* Return max value for 1/sqrt(0) */
    if (x == 1) return 65536;      /* Exact: 1/sqrt(1) = 65536 */

    /* Step 1: Determine MSB position */
    int exp = clz(x);

    /* Step 2: Get initial estimate from lookup table */
    int index = 31 - exp; /* Index into rsqrt_table */
    uint32_t y = rsqrt_table[index];

    /* Step 3: Linear Interpolation */
    if (x > (1U << exp)) {
        uint32_t y_next = (exp < 31) ? rsqrt_table[exp + 1] : 0;
        uint32_t delta = y - y_next;
        uint32_t frac = (uint32_t) ((((uint64_t)x - (1UL << exp)) << 16) >> exp);
        y -= (uint32_t) (mul32(delta, frac) >> 16);
    }

    /* Step 4: Newton-Raphson Iterations */
    for (int iter = 0; iter < 2; iter++) {
        uint32_t y2 = (uint32_t)mul32(y, y);
        uint32_t xy2 = (uint32_t)(mul32(x, y2) >> 16);
        y = (uint32_t)(mul32(y, (3u << 16) - xy2) >> 17);
    }

    return y;
}

/* ============= Main Test Entry ============= */

int main(void)
{
    /* Test 1: mul32(65536, 6700) should equal 439091200 */
    uint64_t mul_result = mul32(65536, 6700);
    *(unsigned int *)(4) = (mul_result == 439091200) ? 1 : 0;

    /* Test 2: fast_rsqrt(65535) should be 226 */
    *(unsigned int *)(8) = fast_rsqrt(65535);

    /* Test 3: fast_rsqrt(1) should be 65536 */
    *(unsigned int *)(12) = fast_rsqrt(1);

    /* Test 4: fast_rsqrt(4) should be 32768 */
    *(unsigned int *)(16) = fast_rsqrt(4);

    return 0;
}
