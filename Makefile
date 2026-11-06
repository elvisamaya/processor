# RV32I processor: build and test flow
#
#   make              run everything (unit tests + every program on the core)
#   make unit         unit tests: ALU, register file, decoder
#   make single       all programs on the single-cycle core
#   make wave P=fib   dump + open a waveform for one program
#   make clean

IVERILOG := iverilog -g2012 -Wall -Wno-timescale -I rtl
VVP      := vvp -n
PY       := python3
BUILD    := build

UNITS    := alu regfile decode
PROGRAMS := arith branches memory fib sort hazards
ALLPROGS := $(PROGRAMS)

COMMON_RTL := rtl/alu.v rtl/regfile.v rtl/imm_gen.v rtl/decoder.v rtl/branch_cmp.v \
              rtl/lsu.v rtl/imem.v rtl/dmem.v

.PHONY: all test unit single wave clean
.SECONDARY:

all: test

test: unit single
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

# ---------------------------------------------------------------- core simulations
# run every program on one core; fail if any program fails
define run_core
	@echo "=== $(1) ==="
	@rm -f $(BUILD)/$(1).log
	@for p in $(ALLPROGS); do \
		$(VVP) $(BUILD)/$(1).vvp +prog=$(BUILD)/$$p > $(BUILD)/$(1)_$$p.log; \
		grep -h "ERROR" $(BUILD)/$(1)_$$p.log; \
		grep -h "RESULT" $(BUILD)/$(1)_$$p.log | tee -a $(BUILD)/$(1).log; \
		grep -q "TEST PASSED" $(BUILD)/$(1)_$$p.log || { echo "FAILED: $$p on $(1)"; exit 1; }; \
	done
endef

$(BUILD)/core_single.vvp: tb/tb_core.v rtl/core_single.v $(COMMON_RTL) | $(BUILD)
	@$(IVERILOG) -o $@ $^

single: $(BUILD)/core_single.vvp $(EXPECTED)
	$(call run_core,core_single)

# ---------------------------------------------------------------- waveforms
P    ?= fib
wave: $(BUILD)/core_single.vvp $(BUILD)/$(P).regs
	$(VVP) $(BUILD)/core_single.vvp +prog=$(BUILD)/$(P) +vcd
	gtkwave $(BUILD)/$(P).vcd &

$(BUILD):
	@mkdir -p $(BUILD)

clean:
	rm -rf $(BUILD)
