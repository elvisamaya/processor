# RV32I processor: build and test flow
#
#   make        run all tests
#   make unit   unit tests: ALU, register file, decoder
#   make clean

IVERILOG := iverilog -g2012 -Wall -Wno-timescale -I rtl
VVP      := vvp -n
PY       := python3
BUILD    := build

UNITS    := alu regfile decode

.PHONY: all test unit clean
.SECONDARY:

all: test

test: unit
	@echo ""
	@echo "All tests passed."

# ---------------------------------------------------------------- unit tests
RTL_alu     := rtl/alu.v
RTL_regfile := rtl/regfile.v
RTL_decode  := rtl/imm_gen.v rtl/decoder.v

unit: $(addprefix unit-,$(UNITS))

unit-%: | $(BUILD)
	@echo "=== unit: $* ==="
	@$(IVERILOG) -o $(BUILD)/tb_$*.vvp tb/tb_$*.v $(RTL_$*)
	@$(VVP) $(BUILD)/tb_$*.vvp | tee $(BUILD)/tb_$*.log
	@grep -q "TEST PASSED" $(BUILD)/tb_$*.log

$(BUILD):
	@mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
