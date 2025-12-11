# SPDX-License-Identifier: MIT
# MyCPU is freely redistributable under the MIT License.
#
# UNOPTIMIZED RISC-V Assembly Implementation of fast_rsqrt
# (Baseline version for performance comparison)
#
# This version intentionally does NOT apply pipeline optimizations:
# - No instruction reordering after loads
# - No delay slot filling
# - Direct translation from C code

#-------------------------------------------------
# _start: Test Entry Point (must be in .text.init)
#-------------------------------------------------
.section .text.init
.globl _start

_start:
    # Initialize stack pointer (4MB)
    li sp, 0x00400000

    # Record start cycle count
    csrr s10, cycle         # s10 = start cycle

    # Test 1: mul32(65536, 6700) == 439091200
    li a0, 65536
    li a1, 6700
    call mul32_base
    # Expected: a0 = 439091200 (0x1A2B1E00)
    li t0, 439091200
    beq a0, t0, mul32_pass
    sw zero, 4(zero)    # mem[4] = 0 (fail)
    j test2
mul32_pass:
    li t0, 1
    sw t0, 4(zero)      # mem[4] = 1 (pass)

test2:
    # Test 2: fast_rsqrt(65535) = 226
    li a0, 65535
    call fast_rsqrt_base
    sw a0, 8(zero)      # mem[8] = result (expected: 226)

test3:
    # Test 3: fast_rsqrt(1) = 65536
    li a0, 1
    call fast_rsqrt_base
    sw a0, 12(zero)     # mem[12] = result (expected: 65536)

test4:
    # Test 4: fast_rsqrt(4) = 32768
    li a0, 4
    call fast_rsqrt_base
    sw a0, 16(zero)     # mem[16] = result (expected: 32768)

    # Record end cycle count and store total cycles
    csrr s11, cycle         # s11 = end cycle
    sub s11, s11, s10       # s11 = total cycles
    sw s11, 20(zero)        # mem[20] = total cycle count

    # Done - enter infinite loop
done:
    wfi
    j done

#-------------------------------------------------
# Function implementations in .text section
#-------------------------------------------------
.section .text

#-------------------------------------------------
# clz_base: Count Leading Zeros (UNOPTIMIZED)
# Input: a0 = 32-bit unsigned integer
# Output: a0 = number of leading zeros (0-32)
#
# Direct translation - no pipeline optimization
#-------------------------------------------------
clz_base:
    beqz a0, clz_return_32

    li t0, 32           # n = 32
    li t1, 16           # c = 16

clz_loop:
    srl t2, a0, t1      # t2 = x >> c
    beqz t2, clz_shift  # UNOPTIMIZED: branch immediately after computation
    sub t0, t0, t1      # n -= c
    mv a0, t2           # x = y

clz_shift:
    srli t1, t1, 1      # c >>= 1
    bnez t1, clz_loop   # UNOPTIMIZED: branch at end of loop

    sub a0, t0, a0      # return n - x
    ret

clz_return_32:
    li a0, 32
    ret

#-------------------------------------------------
# mul32_base: 32-bit Software Multiplication (UNOPTIMIZED)
# Input: a0 = multiplicand (a), a1 = multiplier (b)
# Output: a0 = low 32 bits, a1 = high 32 bits
#
# Direct translation from C - creates Load-Use and RAW hazards
#-------------------------------------------------
mul32_base:
    li t0, 0            # result_low = 0
    li t1, 0            # result_high = 0
    li t2, 32           # loop counter
    mv t3, a0           # t3 = a_low (preserve original)
    li t4, 0            # t4 = a_high (for 64-bit shift)

mul32_loop_base:
    andi t5, a1, 1      # t5 = b & 1
    beqz t5, mul32_skip_base  # UNOPTIMIZED: branch right after andi

    # Add t3:t4 (64-bit a) to t0:t1 (64-bit result)
    # UNOPTIMIZED: sequential dependent operations
    add t0, t0, t3      # result_low += a_low
    sltu t6, t0, t3     # carry - depends on previous add (RAW hazard)
    add t1, t1, t4      # result_high += a_high
    add t1, t1, t6      # result_high += carry - depends on sltu (RAW hazard)

mul32_skip_base:
    # UNOPTIMIZED: these operations are placed sequentially
    # even though they could be interleaved with the above

    # Shift a left by 1 (64-bit): t4:t3 <<= 1
    srli t6, t3, 31     # Extract bit 31
    slli t3, t3, 1      # a_low <<= 1 - depends on t3 (RAW hazard)
    slli t4, t4, 1      # a_high <<= 1
    or t4, t4, t6       # a_high |= carry - depends on both (RAW hazard)

    # Shift b right
    srli a1, a1, 1      # b >>= 1

    # Decrement counter and branch
    addi t2, t2, -1
    bnez t2, mul32_loop_base  # UNOPTIMIZED: branch at very end

    mv a0, t0           # return low
    mv a1, t1           # return high
    ret

#-------------------------------------------------
# fast_rsqrt_base: Fast Inverse Square Root (UNOPTIMIZED)
# Input: a0 = x (32-bit unsigned integer)
# Output: a0 = 1/sqrt(x) in Q16 format
#
# UNOPTIMIZED version - has Load-Use hazards after every LW/LHU
#-------------------------------------------------
fast_rsqrt_base:
    # Prologue
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)
    sw s1, 20(sp)
    sw s2, 16(sp)
    sw s3, 12(sp)
    sw s4, 8(sp)

    # Handle edge cases
    beqz a0, rsqrt_return_max_base
    li t0, 1
    beq a0, t0, rsqrt_return_one_base

    mv s0, a0           # s0 = x

    # Step 1: Count leading zeros
    call clz_base
    mv s1, a0           # s1 = exp = clz(x)

    # Step 2: Get initial estimate from lookup table
    li t0, 31
    sub t0, t0, s1      # t0 = index = 31 - exp
    slli t0, t0, 1      # t0 = index * 2 (half-word offset)

    la t1, rsqrt_table_base
    add t1, t1, t0
    lhu s2, 0(t1)       # s2 = y = rsqrt_table[index]
    # UNOPTIMIZED: Calculate (1 << exp) BEFORE load finishes - causes stall
    mv s3, s2           # LOAD-USE HAZARD: use s2 immediately after load
    mv s2, s3           # restore s2 (s3 = s2 temporarily)

    li t2, 1
    sll t2, t2, s1      # t2 = 1 << exp

    # Step 3: Linear Interpolation (if x > (1 << exp))
    bleu s0, t2, rsqrt_skip_interp_base

    # Get next table entry
    add t1, t1, 2
    li t3, 31
    bge s1, t3, rsqrt_use_zero_next_base
    lhu t3, 0(t1)       # t3 = y_next
    sub s3, s2, t3      # LOAD-USE HAZARD: use t3 immediately after load
    j rsqrt_do_interp_done_base

rsqrt_use_zero_next_base:
    li t3, 0
    sub s3, s2, t3      # delta = y - y_next (no hazard here)
    j rsqrt_do_interp_done_base

rsqrt_do_interp_base:
    # delta = y - y_next (this path no longer used)
    sub s3, s2, t3

rsqrt_do_interp_done_base:

    # frac = ((x - (1 << exp)) << 16) >> exp
    sub t4, s0, t2
    slli t4, t4, 16
    srl t4, t4, s1

    # y -= (delta * frac) >> 16
    mv a0, s3
    mv a1, t4
    call mul32_base

    # Shift right by 16
    srli a0, a0, 16
    slli t5, a1, 16
    or a0, a0, t5       # UNOPTIMIZED: RAW hazard on a0

    sub s2, s2, a0      # y -= adjustment

rsqrt_skip_interp_base:
    # Step 4: Newton-Raphson Iterations (2 iterations)
    li s4, 2

newton_loop_base:
    # y2 = y * y
    mv a0, s2
    mv a1, s2
    call mul32_base
    mv s3, a0           # s3 = y2 - UNOPTIMIZED: RAW hazard

    # xy2 = (x * y2) >> 16
    mv a0, s0
    mv a1, s3           # UNOPTIMIZED: uses s3 right after assignment
    call mul32_base

    # Shift right by 16
    srli a0, a0, 16
    slli t5, a1, 16
    or a0, a0, t5       # UNOPTIMIZED: RAW hazard

    # (3 << 16) - xy2
    li t5, 196608
    sub t5, t5, a0      # UNOPTIMIZED: RAW hazard on a0

    # y = (y * ((3 << 16) - xy2)) >> 17
    mv a0, s2
    mv a1, t5           # UNOPTIMIZED: uses t5 right after computation
    call mul32_base

    # Shift right by 17
    srli a0, a0, 17
    slli t5, a1, 15
    or s2, a0, t5       # UNOPTIMIZED: RAW hazard

    addi s4, s4, -1
    bnez s4, newton_loop_base

    mv a0, s2
    j rsqrt_epilogue_base

rsqrt_return_max_base:
    li a0, -1
    j rsqrt_epilogue_base

rsqrt_return_one_base:
    li a0, 65536

rsqrt_epilogue_base:
    lw ra, 28(sp)
    lw s0, 24(sp)
    lw s1, 20(sp)
    lw s2, 16(sp)
    lw s3, 12(sp)
    lw s4, 8(sp)
    addi sp, sp, 32
    ret

#-------------------------------------------------
# Read-only data section
#-------------------------------------------------
.section .rodata
.align 2
rsqrt_table_base:
    .half 65535, 46341, 32768, 23170, 16384   # 2^0 to 2^4
    .half 11585,  8192,  5793,  4096,  2896   # 2^5 to 2^9
    .half  2048,  1448,  1024,   724,   512   # 2^10 to 2^14
    .half   362,   256,   181,   128,    90   # 2^15 to 2^19
    .half    64,    45,    32,    23,    16   # 2^20 to 2^24
    .half    11,     8,     6,     4,     3   # 2^25 to 2^29
    .half     2,     1                        # 2^30 to 2^31
