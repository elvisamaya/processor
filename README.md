# RISC-V Processor

![ci](https://github.com/elvisamaya/processor/actions/workflows/ci.yml/badge.svg)

A RISC-V (RV32I) processor in Verilog, built two ways: a **single-cycle** core and a **5-stage pipelined** core with hazard detection, forwarding and branch flushing. Both run the same programs and are checked instruction-for-instruction against a golden reference model, including thousands of randomly generated instructions.

## Results

Every program runs on three cores, and each final register file, data memory and instruction count must match the golden model exactly.

| program      | instructions | single-cycle CPI | pipeline, stall only | pipeline + forwarding |
|--------------|-------------:|-----------------:|---------------------:|----------------------:|
| arith        |           71 |            1.000 |                2.028 |                 1.056 |
| branches     |          147 |            1.000 |                1.830 |                 1.571 |
| memory       |           62 |            1.000 |                1.758 |                 1.226 |
| fib          |          206 |            1.000 |                1.830 |                 1.282 |
| sort         |        9,810 |            1.000 |                2.102 |                 1.503 |
| hazards      |           89 |            1.000 |                2.326 |                 1.483 |
| random ×8    |        8,171 |            1.000 |                1.711 |                 1.233 |
| **all**      |   **18,556** |        **1.000** |            **1.924** |             **1.380** |

**Forwarding cuts the pipeline's CPI by 28%** (1.92 → 1.38). The single-cycle core always has CPI = 1, but its clock period must cover an entire instruction. The pipeline's clock only has to cover one stage, roughly 1/5 of that, so even at CPI 1.38 it finishes programs about **3.6× faster** (5 / 1.38) at the higher clock it allows. That estimate assumes perfectly balanced stages; real designs get less.

## Supported instructions

All of RV32I except CSRs: `LUI AUIPC JAL JALR`, `BEQ BNE BLT BGE BLTU BGEU`, `LB LH LW LBU LHU SB SH SW`, `ADDI SLTI SLTIU XORI ORI ANDI SLLI SRLI SRAI`, `ADD SUB SLL SLT SLTU XOR SRL SRA OR AND`, `FENCE` (no-op), `ECALL`/`EBREAK` (halt).

## Architecture

### Single-cycle (`rtl/core_single.v`)

```
        +------+   +---------+   +----------+   +-----+   +------+   +-------+
 PC --> | imem | ->| decoder | ->| regfile  | ->| ALU | ->| dmem | ->| WB mux| --+
  ^     +------+   | imm_gen |   | (2R/1W)  |   +-----+   | lsu  |   +-------+   |
  |                +---------+   +----------+      |      +------+               |
  +---- next PC: pc+4 / branch target / jump target <----------- regfile write <-+
```

Every instruction completes in one cycle. Simple, but the clock period is set by the slowest path: a load goes through *all* the blocks above.

### 5-stage pipeline (`rtl/core_pipe.v`)

```
   IF          ID              EX                 MEM          WB
 +------+   +---------+   +-------------+   +------------+   +--------+
 | PC   |   | decode  |   | ALU         |   | data mem   |   | write  |
 | imem |==>| regfile |==>| branch cmp  |==>| load/store |==>| back   |
 +------+   | imm     |   | target addr |   +------------+   +--------+
    ^       +---------+   +-------------+        |               |
    |  hazard unit:  ^  forwarding muxes <--------+---------------+
    |  stall IF/ID --+        |
    +-- redirect + flush <----+  (taken branch / jump)
```

`==>` are pipeline registers (IF/ID, ID/EX, EX/MEM, MEM/WB). Five instructions are in flight at once.

| Hazard | Example | How it's handled | Cost |
|---|---|---|---|
| Read-after-write, ALU result | `add t1,t0,t0` → `sub t2,t1,t0` | **Forwarding** from EX/MEM or MEM/WB into the ALU inputs (newest value wins) | 0 cycles |
| Read-after-write, through write-back | producer 3 instructions earlier | Register file **write-through** (read returns the value being written) | 0 cycles |
| Load-use | `lw a0,0(s0)` → `addi a1,a0,1` | **Stall** decode one cycle, then forward from MEM/WB | 1 bubble |
| Taken branch / jump | `bnez t0, loop` | Predict not-taken; resolve in EX; **flush** IF/ID and ID/EX | 2 bubbles |

With `FORWARDING=0` the core instead stalls until the producer reaches write-back. It's slower, but kept so the two can be compared.

### Watching it run

`make trace` prints which instruction (by PC) sits in each stage every cycle. From `programs/hazards.s`:

```
cycle |    IF |    ID |    EX |   MEM |    WB |
   13 |  0034 |  0030 |  002c |  0028 |  0024 |
   14 |  0038 |  0034 |  0030 |  002c |  0028 | stall      <- 0x30 lw a0 / 0x34 addi a1,a0,1
   15 |  0038 |  0034 |    -- |  0030 |  002c |            <- bubble inserted into EX
   16 |  003c |  0038 |  0034 |    -- |  0030 |            <- addi gets a0 forwarded from WB
   ...
   31 |  0068 |  0064 |  0060 |    -- |  005c | taken -> flush IF,ID   <- 0x60 bnez t6, taken1
   32 |  0068 |    -- |    -- |  0060 |    -- |            <- 0x64 (wrong path) squashed
   33 |  006c |  0068 |    -- |    -- |  0060 |            <- fetch resumes at the target
```

## Verification

```
programs/*.s ──► rvasm.py ──► .hex ──┬──► Verilog core (iverilog) ──► final state ─┐
                                     │                                             ├─► must match exactly
gen_random.py ──► random_N.s ────────┴──► rviss.py (golden ISA model) ─► expected ──┘
```

- **Golden model.** `scripts/rviss.py` is an instruction-set simulator written directly from the RISC-V spec, with no clocks or pipeline. After every program, the testbench compares all 32 registers, all 1,024 words of data memory, and the instruction count against it.
- **Directed tests.** Hand-written programs cover every ALU edge case (`arith`), every branch condition taken and not taken, plus calls and returns (`branches`), every load/store size, alignment and sign extension (`memory`), real workloads (`fib`, `sort`), and every pipeline hazard pattern (`hazards`).
- **Random tests.** `scripts/gen_random.py` generates programs of ~1,000 executed instructions with dense register dependencies, loads, stores, forward branches, jumps and small loops. Eight seeds run in every regression.
- **Unit tests.** ALU (20,000+ vectors against a reference model), register file, and immediate/decoder on hand-encoded instructions.
- **Do the tests actually catch bugs?** I planted 8 typical pipeline bugs, one at a time. Every one made the regression fail:

  | Planted bug | Caught by |
  |---|---|
  | No EX/MEM forwarding | `arith` |
  | No load-use stall | `memory` |
  | ID/EX not flushed on a taken branch | `branches` |
  | Forwarding priority reversed (older value wins) | `branches` |
  | Forwarding a "result" for `x0` | `arith` |
  | Stall-only core ignores a MEM-stage dependency | `arith` |
  | `BLT` compares unsigned | `branches` |
  | `LB` doesn't sign-extend | `memory` |

- **Lint.** Both cores are clean under Verilator `-Wall`, and CI runs lint plus the full regression on every push.

## Running it

Requires [Icarus Verilog](https://steveicarus.github.io/iverilog/) and Python 3. Verilator and GTKWave are optional.

```bash
make                      # unit tests + every program on all three cores
make cpi                  # the CPI table above
make trace P=hazards      # cycle-by-cycle pipeline trace
make wave P=fib CORE=pipe # waveform in GTKWave
make lint                 # Verilator -Wall

# assemble and run your own program
python3 scripts/rvasm.py my.s -o build/my.hex -l      # -l prints a listing
python3 scripts/rviss.py build/my.hex --out build/my  # golden result
vvp -n build/core_pipe.vvp +prog=build/my             # run it on the pipeline
```

## Layout

```
rtl/        alu, regfile, imm_gen, decoder, branch_cmp, lsu, imem, dmem,
            core_single (single-cycle), core_pipe (5-stage pipeline)
tb/         unit testbenches + tb_core (runs a program, compares to golden model)
programs/   hand-written RV32I assembly tests
scripts/    rvasm.py (assembler), rviss.py (golden model), gen_random.py, cpi_table.py
```

## Next steps

- [ ] Branch prediction (a small branch history table) to recover the 2-cycle taken-branch penalty
- [ ] Run on an FPGA with a UART for output (reusing my [digital-design-rtl](https://github.com/elvisamaya/digital-design-rtl) UART)
- [ ] Synthesize with Yosys/OpenLane and measure the real clock-frequency gain from pipelining
- [ ] M extension (multiply/divide)
