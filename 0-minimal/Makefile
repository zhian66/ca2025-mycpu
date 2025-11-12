# MyCPU is freely redistributable under the MIT License. See the file
# LICENSE" for information on usage and redistribution of this file.

SRC_DIR = src/main/resources
SIM_TIME ?= 1000000
SIM_VCD ?= trace.vcd

all: test

test:
	cd .. && sbt "project minimal" test

verilator:
	@mkdir -p verilog/verilator
	@# Verify sim.cpp exists (it's a source file, should be in repository)
	@test -f verilog/verilator/sim.cpp || { echo "ERROR: verilog/verilator/sim.cpp missing"; exit 1; }
	cd .. && PATH=$$HOME/.local/bin:$$PATH sbt "project minimal" "runMain board.verilator.VerilogGenerator"
	cd verilog/verilator && verilator --trace --exe --cc sim.cpp Top.v && make -C obj_dir -f VTop.mk

sim: verilator
	@echo "Running Verilator simulation for jit.asmbin..."
	cd verilog/verilator/obj_dir && ./VTop -vcd ../../../$(SIM_VCD) -time $(SIM_TIME) -instruction ../../../src/main/resources/jit.asmbin
	@python3 scripts/analyze_trace.py trace.vcd

indent:
	find . -name '*.scala' | xargs scalafmt
	clang-format -i verilog/verilator/*.cpp 2>/dev/null || true
	clang-format -i csrc/*.[ch] 2>/dev/null || true

clean:
	cd .. && sbt "project minimal" clean
	$(RM) -r test_run_dir
	$(RM) -r verilog/verilator/obj_dir
	$(RM) verilog/verilator/*.v
	$(RM) verilog/verilator/*.fir
	$(RM) verilog/verilator/*.anno.json
	$(RM) verilog/*.txt
	$(RM) $(SRC_DIR)/*.o
	$(RM) $(SIM_VCD)

distclean: clean

.PHONY: all test verilator sim indent clean distclean
