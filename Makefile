# RV32I processor: build and test flow
#
#   make        run all tests
#   make clean

IVERILOG := iverilog -g2012 -Wall -Wno-timescale -I rtl
VVP      := vvp -n
PY       := python3
BUILD    := build

UNITS    := 

.PHONY: all test unit clean
.SECONDARY:

all: test

test: unit
	@echo ""
	@echo "All tests passed."

# ---------------------------------------------------------------- unit tests


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
