# SPDX-License-Identifier: MIT
# MyCPU is freely redistributable under the MIT License.
#
# Optimized RISC-V Assembly Implementation of fast_rsqrt
#
# Pipeline Optimizations:
# 1. Instruction reordering to avoid Load-Use hazards
# 2. Register pre-allocation to improve forwarding efficiency
# 3. Minimized branch penalties in multiplication loop

#-------------------------------------------------
# _start: Test Entry Point (must be in .text.init)
# Tests fast_rsqrt with known values and stores results in memory
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
    call mul32_asm
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
    call fast_rsqrt_asm
    sw a0, 8(zero)      # mem[8] = result (expected: 226)

test3:
    # Test 3: fast_rsqrt(1) = 65536
    li a0, 1
    call fast_rsqrt_asm
    sw a0, 12(zero)     # mem[12] = result (expected: 65536)

test4:
    # Test 4: fast_rsqrt(4) = 32768
    li a0, 4
    call fast_rsqrt_asm
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
# clz_asm: Count Leading Zeros
# Input: a0 = 32-bit unsigned integer
# Output: a0 = number of leading zeros (0-32)
# Registers used: t0, t1, t2
#-------------------------------------------------
clz_asm:
    beqz a0, clz_return_32

    li t0, 32           # n = 32
    li t1, 16           # c = 16

clz_loop:
    srl t2, a0, t1      # t2 = x >> c
    beqz t2, clz_shift
    sub t0, t0, t1      # n -= c
    mv a0, t2           # x = y

clz_shift:
    srli t1, t1, 1      # c >>= 1 (16->8->4->2->1)
    bnez t1, clz_loop

    sub a0, t0, a0      # return n - x
    ret

clz_return_32:
    li a0, 32
    ret

#-------------------------------------------------
# mul32_asm: 32-bit Software Multiplication (4x Loop Unrolling)
# Input: a0 = multiplicand (a), a1 = multiplier (b)
# Output: a0 = low 32 bits, a1 = high 32 bits
#
# Pipeline Optimization:
# - 4x Loop Unrolling: reduces branches from 64 to 40 per call
# - Original: 32 iterations × 2 branches = 64 branches
# - Optimized: 8 iterations × 5 branches = 40 branches
# - Saves ~24 branches per mul32 call (37.5% reduction)
#-------------------------------------------------
.align 2
mul32_asm:
    li t0, 0            # result_low = 0
    li t1, 0            # result_high = 0
    li t2, 32           # loop counter (will decrement by 4)
    mv t3, a0           # t3 = a_low (preserve original)
    li t4, 0            # t4 = a_high (for 64-bit shift)

mul32_loop_unrolled:
    # === Bit 0 ===
    andi t5, a1, 1      # t5 = b & 1
    beqz t5, mul32_skip_bit0
    add t0, t0, t3      # result_low += a_low
    sltu t6, t0, t3     # carry
    add t1, t1, t4      # result_high += a_high
    add t1, t1, t6      # result_high += carry
mul32_skip_bit0:
    # Shift a left by 1 (64-bit)
    srli t6, t3, 31
    slli t3, t3, 1
    slli t4, t4, 1
    or t4, t4, t6

    # === Bit 1 ===
    andi t5, a1, 2      # t5 = b & 2
    beqz t5, mul32_skip_bit1
    add t0, t0, t3
    sltu t6, t0, t3
    add t1, t1, t4
    add t1, t1, t6
mul32_skip_bit1:
    srli t6, t3, 31
    slli t3, t3, 1
    slli t4, t4, 1
    or t4, t4, t6

    # === Bit 2 ===
    andi t5, a1, 4      # t5 = b & 4
    beqz t5, mul32_skip_bit2
    add t0, t0, t3
    sltu t6, t0, t3
    add t1, t1, t4
    add t1, t1, t6
mul32_skip_bit2:
    srli t6, t3, 31
    slli t3, t3, 1
    slli t4, t4, 1
    or t4, t4, t6

    # === Bit 3 ===
    andi t5, a1, 8      # t5 = b & 8
    beqz t5, mul32_skip_bit3
    add t0, t0, t3
    sltu t6, t0, t3
    add t1, t1, t4
    add t1, t1, t6
mul32_skip_bit3:
    srli t6, t3, 31
    slli t3, t3, 1
    slli t4, t4, 1
    or t4, t4, t6

    # Shift b right by 4 (process 4 bits at once)
    srli a1, a1, 4

    # Decrement counter by 4
    addi t2, t2, -4
    bnez t2, mul32_loop_unrolled

    mv a0, t0           # return low
    mv a1, t1           # return high
    ret

#-------------------------------------------------
# fast_rsqrt_asm: Fast Inverse Square Root (Q16 fixed-point)
# Input: a0 = x (32-bit unsigned integer)
# Output: a0 = 1/sqrt(x) in Q16 format (65536 * 1/sqrt(x))
#
# Pipeline Optimizations:
# - Load-Use hazard avoided by instruction reordering
# - Independent instructions inserted between LW and use
#-------------------------------------------------
.align 2
fast_rsqrt_asm:
    # Prologue: save return address and callee-saved registers
    addi sp, sp, -32
    sw ra, 28(sp)
    sw s0, 24(sp)       # s0 = x (input)
    sw s1, 20(sp)       # s1 = exp (clz result)
    sw s2, 16(sp)       # s2 = y (current estimate)
    sw s3, 12(sp)       # s3 = temporary
    sw s4, 8(sp)        # s4 = temporary

    # Handle edge cases
    beqz a0, rsqrt_return_max    # x == 0 -> return 0xFFFFFFFF
    li t0, 1
    beq a0, t0, rsqrt_return_one # x == 1 -> return 65536

    mv s0, a0           # s0 = x (save input)

    # Step 1: Count leading zeros
    call clz_asm        # a0 = clz(x)
    mv s1, a0           # s1 = exp = clz(x)

    # Step 2: Get initial estimate from lookup table
    # index = 31 - exp
    li t0, 31
    sub t0, t0, s1      # t0 = index = 31 - exp
    slli t0, t0, 1      # t0 = index * 2 (half-word offset)

    la t1, rsqrt_table  # t1 = table base address
    add t1, t1, t0      # t1 = &rsqrt_table[index]
    lhu s2, 0(t1)       # s2 = y = rsqrt_table[index] (LOAD)

    # [OPTIMIZATION] Insert independent instruction after LW
    # Calculate (1 << exp) for later comparison
    li t2, 1
    sll t2, t2, s1      # t2 = 1 << exp (independent of load)

    # Step 3: Linear Interpolation (if x > (1 << exp))
    bleu s0, t2, rsqrt_skip_interp  # if x <= (1 << exp), skip

    # Get next table entry for interpolation
    addi t0, t0, 2      # Move to next entry
    add t1, t1, 2       # t1 = &rsqrt_table[index + 1]

    li t3, 31
    bge s1, t3, rsqrt_use_zero_next  # if exp >= 31, y_next = 0
    lhu t3, 0(t1)       # t3 = y_next = rsqrt_table[index + 1]
    j rsqrt_do_interp

rsqrt_use_zero_next:
    li t3, 0            # y_next = 0

rsqrt_do_interp:
    # delta = y - y_next
    sub s3, s2, t3      # s3 = delta = y - y_next

    # frac = ((x - (1 << exp)) << 16) >> exp
    sub t4, s0, t2      # t4 = x - (1 << exp)
    slli t4, t4, 16     # t4 = (x - (1 << exp)) << 16
    srl t4, t4, s1      # t4 = frac = ((x - (1 << exp)) << 16) >> exp

    # y -= (delta * frac) >> 16
    mv a0, s3           # a0 = delta
    mv a1, t4           # a1 = frac
    call mul32_asm      # a0 = low, a1 = high

    # Shift result right by 16 (take bits [47:16] of 64-bit result)
    srli a0, a0, 16     # a0 >>= 16
    slli t5, a1, 16     # t5 = a1 << 16
    or a0, a0, t5       # a0 = (a1 << 16) | (a0 >> 16)

    sub s2, s2, a0      # y -= adjustment

rsqrt_skip_interp:
    # Step 4: Newton-Raphson Iterations (2 iterations)
    # y = y * (3 - x*y^2) / 2  (in Q16 format)

    li s4, 2            # iteration counter

newton_loop:
    # y2 = y * y
    mv a0, s2
    mv a1, s2
    call mul32_asm      # a0:a1 = y * y (64-bit result)
    mv s3, a0           # s3 = y2 (low 32 bits, sufficient for our range)

    # xy2 = (x * y2) >> 16
    mv a0, s0           # a0 = x
    mv a1, s3           # a1 = y2
    call mul32_asm      # a0:a1 = x * y2

    # Shift right by 16: take bits [47:16]
    srli a0, a0, 16
    slli t5, a1, 16
    or a0, a0, t5       # a0 = xy2 = (x * y2) >> 16

    # Calculate (3 << 16) - xy2
    li t5, 196608       # t5 = 3 << 16 = 196608
    sub t5, t5, a0      # t5 = (3 << 16) - xy2

    # y = (y * ((3 << 16) - xy2)) >> 17
    mv a0, s2           # a0 = y
    mv a1, t5           # a1 = (3 << 16) - xy2
    call mul32_asm      # a0:a1 = y * ((3 << 16) - xy2)

    # Shift right by 17
    srli a0, a0, 17
    slli t5, a1, 15     # (32 - 17 = 15)
    or s2, a0, t5       # s2 = new y

    # Decrement iteration counter
    addi s4, s4, -1
    bnez s4, newton_loop

    mv a0, s2           # Return y
    j rsqrt_epilogue

rsqrt_return_max:
    li a0, -1           # Return 0xFFFFFFFF
    j rsqrt_epilogue

rsqrt_return_one:
    li a0, 65536        # Return 65536 (1.0 in Q16)

rsqrt_epilogue:
    # Epilogue: restore saved registers
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
rsqrt_table:
    .half 65535, 46341, 32768, 23170, 16384   # 2^0 to 2^4
    .half 11585,  8192,  5793,  4096,  2896   # 2^5 to 2^9
    .half  2048,  1448,  1024,   724,   512   # 2^10 to 2^14
    .half   362,   256,   181,   128,    90   # 2^15 to 2^19
    .half    64,    45,    32,    23,    16   # 2^20 to 2^24
    .half    11,     8,     6,     4,     3   # 2^25 to 2^29
    .half     2,     1                        # 2^30 to 2^31
