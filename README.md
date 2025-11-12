# RISC-V CPU Labs in Chisel

> [!NOTE]
> Several code fragments are intentionally incomplete. They serve as lab exercises and must be filled in by students during the course.

This repository captures a three-part progression for building a RISC-V processor in Chisel.
Each lab increases architectural complexity while preserving a common verification and simulation environment.
The designs target the 32-bit base integer ISA (RV32I) and run real test programs compiled from C.

> **Toolchain note**
> All Scala projects use SBT 1.10.7 with Chisel 3.6.1.
> The projects use `chisel3.stage.ChiselStage.emitVerilog()` to generate Verilog without requiring external CIRCT/firtool dependencies.
> This approach ensures compatibility with macOS ARM64 systems and simplifies the build process.

## Repository Layout

- `0-minimal/` - Ultra-minimal RISC-V CPU with only 5 instructions (AUIPC, ADDI, LW, SW, JALR) designed to execute JIT self-modifying code demonstration. Educational example of focused processor design.
- `1-single-cycle/` - Baseline RV32I core that executes each instruction in one cycle; includes memory/peripheral models and software tests.
- `2-mmio-trap/` - Extends the single-cycle core with CSR support, a Core Local Interruptor (CLINT), and trap handling for external interrupts.
- `3-pipeline/` - Introduces multi-stage pipelines (3-stage and multiple 5-stage variants) with hazard management, forwarding, and the same CSR/interrupt features.
- `tests/` - Test infrastructure including RISC-V compliance framework and other test suites

## Lab Highlights

### [Minimal CPU](0-minimal/)
- Ultra-minimal RISC-V CPU with only 5 instructions: AUIPC, ADDI, LW, SW, JALR
- Designed specifically to execute JIT (Just-In-Time) self-modifying code demonstration
- Key features:
  - Addition-only ALU (no complex arithmetic operations)
  - Word-aligned memory access only (no byte/halfword operations)
  - No ECALL support (test verification via debug interface)
  - 60-byte test program (`jit.asmbin`) demonstrating: encode → copy → execute cycle
- Educational example showing how to build a focused, minimal processor for specific workloads
- All test verification performed via debug register reads, not system calls

### [Single-Cycle Core](1-single-cycle/)
- Implements the full RV32I instruction set with one-cycle latency per instruction.
- Simple Harvard-style memory interface with Verilator models in `peripheral/`.
- Nine ChiselTest unit and integration tests covering ALU, control flow, and sample programs.
- Key files: `src/main/scala/riscv/core/*.scala`, `verilog/verilator/`, and example programs under `csrc/`.

### [Interrupt-Capable Core](2-mmio-trap/)
- Adds the Zicsr extension (`CSRRW/CSRRS/CSRRC` and immediate forms) and machine-level CSRs such as `mstatus`, `mtvec`, `mepc`, and `mcause`.
- Integrates a CLINT peripheral that raises timer and software interrupts; traps are dispatched through machine-mode handlers.
- Preserves single-cycle execution for non-trapping instructions while sequencing interrupt entry/return (`mret`).
- Eight dedicated tests exercise CSR access patterns and interrupt scenarios.
- Critical design: CLINT writes to CSRs take priority over CPU writes to ensure atomic trap entry.

### [Pipelined Cores](3-pipeline/)
- Provides four pipeline implementations with increasing sophistication:
  1. **ThreeStage**: Simplified 3-stage pipeline (Fetch-Execute-WriteBack) for learning basics
  2. **FiveStageStall**: Classic 5-stage with stall-based hazard handling (no forwarding)
  3. **FiveStageForward**: 5-stage with full EX-to-EX and MEM-to-EX forwarding paths
  4. **FiveStageFinal**: Advanced 5-stage with ID-stage forwarding and early branch resolution (DEFAULT)
- Performance progression: ThreeStage (CPI ~2.5) → FiveStageStall (CPI ~1.8) → FiveStageForward (CPI ~1.3) → FiveStageFinal (CPI ~1.2)
- Includes hazard detection, pipeline flushing, branch handling, and comprehensive forwarding logic.
- Reuses CSR/CLINT infrastructure so both exceptions and asynchronous interrupts work in the presence of pipelining.
- Comprehensive test suite covers pipeline registers, hazard corner cases, and regression programs (`src/test/scala/riscv/`).

## Build and Test Workflow

### Required tools

- SBT 1.9.7+
- Chisel 3.6.1 with legacy FIRRTL compiler 1.6.0
- Verilator 5.042 or newer
- Optional: GNU RISC-V toolchain for assembling the C/asm test payloads
  * Toolchain requirement: RISC-V GNU toolchain at `$HOME/riscv/toolchain/bin/` or set `CROSS_COMPILE` environment variable.

### Build System Architecture

The projects use the legacy Scala FIRRTL compiler instead of CIRCT/firtool:
- Verilog Generation: `chisel3.stage.ChiselStage.emitVerilog()` generates Verilog directly
- No External Dependencies: No firtool or CIRCT tools required
- Platform Compatibility: Works on Linux, macOS (Intel and Apple Silicon), and other Unix-like systems
- Compilation Time: Legacy compiler is slower than CIRCT but fully functional

Each project's `build.sbt` includes:
```scala
libraryDependencies ++= Seq(
  "edu.berkeley.cs" %% "chisel3" % "3.6.1",
  "edu.berkeley.cs" %% "chiseltest" % "0.6.0" % "test",
  "edu.berkeley.cs" %% "firrtl" % "1.6.0",  // Legacy FIRRTL compiler
)
```

The `VerilogGenerator` in each `src/main/scala/board/verilator/Top.scala` uses:
```scala
import chisel3.stage.ChiselStage

object VerilogGenerator extends App {
  (new ChiselStage).emitVerilog(
    new Top(),
    Array("--target-dir", "verilog/verilator")
  )
}
```

### Repository-wide targets (from top-level directory)

```shell
make clean         # Clean build artifacts from all projects
make distclean     # Deep clean: remove RISCOF results and all generated files
```

The `distclean` target removes all generated artifacts while preserving source files:
- RISCOF work directory and test results
- sbt build artifacts (target/, .bloop/, .metals/)
- Auto-generated compliance test files
- Verilator generated files and waveforms

### Project-specific targets (from individual project directories)

```shell
make test       # Execute ChiselTest suite via sbt
make verilator  # Generate Verilog (via legacy FIRRTL compiler) and build Verilator C++ simulator
make sim        # Run Verilator simulation; generates waveforms in trace.vcd
make indent     # Format Scala and C++ sources (scalafmt + clang-format)
make clean      # Remove build artifacts
make compliance # Run RISCOF compliance tests for this project
```

The `make verilator` target performs two steps:
1. Generate Verilog from Chisel using `sbt "runMain board.verilator.VerilogGenerator"`
2. Compile the Verilator C++ simulator with VCD tracing support

The `make sim` target runs the compiled simulator with configurable parameters:
```shell
make sim SIM_ARGS="-instruction src/main/resources/fibonacci.asmbin" SIM_TIME=100000
```

VCD waveform generation can be controlled via the `WRITE_VCD` variable:
```shell
make sim                # Default: VCD enabled (generates trace.vcd)
WRITE_VCD=0 make sim    # Disable VCD for faster simulation
WRITE_VCD=1 make sim    # Explicit enable VCD
```
Note: VCD generation is enabled by default (`WRITE_VCD=1`). Set `WRITE_VCD=0` to skip waveform generation when running large simulations or compliance tests where waveform analysis is not needed. This significantly improves simulation performance.

## Learning Path and Architecture Overview

### Recommended Study Sequence

1. Start with `0-minimal/` to understand focused processor design with minimal instruction set
2. Study `1-single-cycle/` to understand basic RISC-V instruction execution with full RV32I support
3. Explore `2-mmio-trap/` to learn privileged architecture and interrupt handling
4. Progress to `3-pipeline/` variants in order: ThreeStage → FiveStageStall → FiveStageForward → FiveStageFinal

### Architecture Documentation

Comprehensive documentation is available in:
- **Module Scaladoc**: All core CPU modules have detailed Scaladoc comments
  - `src/main/scala/riscv/core/CPU.scala` - Top-level architecture overview
  - `src/main/scala/riscv/core/Execute.scala` - ALU operations and branch resolution
  - `src/main/scala/riscv/core/InstructionDecode.scala` - Instruction decoding and control signals
  - `src/main/scala/riscv/core/CSR.scala` (2-mmio-trap) - Privileged architecture and interrupt priority
- **Compliance Test Documentation**: `src/test/scala/riscv/compliance/ComplianceTestBase.scala` - RISCOF test framework

### Key Architectural Decisions

**Single-Cycle vs Pipeline:**
- Single-cycle: CPI = 1, simple design, longer clock period
- Pipeline: CPI < 2, complex hazard handling, shorter clock period
- Trade-off: Hardware complexity vs performance

**Hazard Handling Strategies:**
- Stalling: Simple hardware, lower performance
- Forwarding: Complex hardware, eliminates most hazard stalls
- Early resolution: Reduces control hazard penalties

**CSR Write Priority (2-mmio-trap):**
- CLINT writes override CPU writes during trap entry
- Ensures atomic state updates for interrupt handling
- Critical for correct exception/interrupt behavior

## Notes for Students

- The labs are designed to be read in order; later directories assume experience with modules introduced earlier.
- Comments marked with `CA25: Exercise` in the source indicate TODOs that must be completed as part of the exercises.
- When extending functionality, favor the existing Chisel module boundaries so the provided testbenches continue to apply.
- All source files include comprehensive Scaladoc - read the module documentation before modifying code.
- Use `make test` frequently to verify your changes pass all tests.
