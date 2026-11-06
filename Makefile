# RV32I processor: build and test flow
#
#   make         run all tests
#   make unit    unit tests: ALU, register file, decoder
#   make golden  assemble every program and run it on the golden model
#   make clean

IVERILOG := iverilog -g2012 -Wall -Wno-timescale -I rtl
VVP      := vvp -n
PY       := python3
BUILD    := build

UNITS    := alu regfile decode
PROGRAMS := arith branches memory fib sort hazards
ALLPROGS := $(PROGRAMS)

.PHONY: all test unit golden clean
.SECONDARY:

all: test

test: unit golden
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

# ---------------------------------------------------------------- programs
# assemble, then run the golden model to produce the expected results
$(BUILD)/%.hex: programs/%.s scripts/rvasm.py | $(BUILD)
	@$(PY) scripts/rvasm.py $< -o $@

$(BUILD)/%.regs: $(BUILD)/%.hex scripts/rviss.py
	@$(PY) scripts/rviss.py $< --out $(BUILD)/$* > /dev/null

EXPECTED := $(addprefix $(BUILD)/,$(addsuffix .regs,$(ALLPROGS)))

golden: $(addprefix $(BUILD)/,$(addsuffix .hex,$(ALLPROGS)))
	@echo "=== golden model ==="
	@for p in $(ALLPROGS); do $(PY) scripts/rviss.py $(BUILD)/$$p.hex --out $(BUILD)/$$p; done

$(BUILD):
	@mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
