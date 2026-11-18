# CMPS 301 — Six-Stage Pipelined Processor (VHDL)

A synthesizable 32-bit, six-stage (F / D / X1 / X2 / M / W) pipelined
processor for the CMPS 301 ISA, with one directed self-checking testbench per
RTL module, three integration benches, and a LaTeX specification.

```
rtl/        RTL, VHDL-93 (cpu_pkg.vhd + 21 modules, top.vhd = integrator)
tb/         testbenches, VHDL-2008 (tb_pkg.vhd + tb_<module>.vhd,
            tb_top.vhd, tb_hazards.vhd, tb_system.vhd)
programs/   demo.mem (assembled demo), demo.golden (expected final state),
            demo.mif / program.mif (Quartus RAM initialisation)
scripts/    questa_compile.do, questa_run.do
doc/        spec.tex, spec.pdf
Makefile
```

## 1. Running the tests with GHDL

Requirements: GHDL ≥ 1.0 (mcode, LLVM or GCC back end) and GNU make.

```sh
make all          # analyse everything, run all 24 testbenches, exit 0 only if all PASS
make alu          # one module: runs tb/tb_alu.vhd  (any name from the manifest)
make top          # full-pipeline smoke test
make hazards      # load-use / mispredict / CALL-INT / hardware-IRQ programs
make system       # programs/demo.mem vs programs/demo.golden
make spec         # rebuild doc/spec.pdf
make clean
```

Each target runs exactly

```sh
ghdl -a --std=08 --workdir=build <all rtl and tb files, in dependency order>
ghdl -e --std=08 --workdir=build tb_<module>
ghdl -r --std=08 --workdir=build tb_<module> --assert-level=error --ieee-asserts=disable-at-0
```

A passing testbench prints `PASS tb_<module>` and ends through `std.env.finish`.
Any failed check reports `CHECK FAILED: ...` with `severity error`, which stops
GHDL with a non-zero exit code.

## 2. Running a program from a .mem file

`tb_system` loads a program image, releases reset, runs until the core halts
(HLT reached and older instructions drained), and compares the final state with
a golden file.

```sh
make system                                            # defaults below
make system MEM=programs/foo.mem GOLDEN=programs/foo.golden IN=00000000 IRQ=-1
```

| make var | generic       | meaning                                             | default               |
|----------|---------------|-----------------------------------------------------|-----------------------|
| `MEM`    | `MEM_FILE`    | program image                                       | `programs/demo.mem`   |
| `GOLDEN` | `GOLDEN_FILE` | expected final state                                | `programs/demo.golden`|
| `IN`     | `IN_VALUE`    | constant IN.PORT value (8 hex digits)               | `0000ABCD`            |
| `IRQ`    | `IRQ_CYCLE`   | cycle of a 1-cycle INTR.IN pulse, `-1` = none      | `40`                  |

The bundled golden file assumes the defaults (one interrupt at cycle 40, so
`R4 = 1`, the ISR's counter).

### .mem format

```
# comment lines start with #, / or ;
@000                 # set the load address (hex)
00000010             # one 32-bit hex word per line, address auto-increments
00000100    # text after the word is ignored
@010
88800200    # 010: LDM R1, 0x200
```

Memory map conventions: `M[0]` reset vector, `M[1]` hardware-interrupt vector,
`M[2]`/`M[3]` vectors of `INT 0`/`INT 1`. The stack starts at 4095 and grows
down.

### Adding your own program

1. Hand-assemble the instructions with the encoding below. Lay them out in a
   new `programs/foo.mem`.
2. Write `programs/foo.golden` with any subset of
   `R0..R7`, `SP`, `CCR`, `OUT`, `PC`, one `NAME HEXVALUE` per line.
3. Run `make system MEM=programs/foo.mem GOLDEN=programs/foo.golden IRQ=-1`.

Instruction word: `[31:26] opcode | [25:23] Rdst | [22:20] Rsrc1 | [19:17] Rsrc2 | [16] index | [15:0] imm`.
Operand fields used by each instruction:

| form                          | fields                                              |
|-------------------------------|-----------------------------------------------------|
| `NOT/INC/IN/POP Rd`           | Rdst                                                |
| `OUT/PUSH Rs`                 | Rsrc1                                               |
| `MOV/SWAP Rd, Rs`             | Rdst, Rsrc1                                         |
| `ADD/SUB/AND Rd, Rs1, Rs2`    | Rdst, Rsrc1, Rsrc2                                  |
| `CMP Rs1, Rs2`                | Rsrc1, Rsrc2                                        |
| `SHL/SHR Rd, imm`             | Rdst, imm[4:0]                                      |
| `IADD Rd, Rs, imm`            | Rdst, Rsrc1, imm (sign-extended)                    |
| `LDM Rd, imm`                 | Rdst, imm (sign-extended)                           |
| `LDD Rd, off(Rs)`             | Rdst, Rsrc1 (base), imm (sign-extended offset)      |
| `STD Rs1, off(Rs2)`           | Rsrc1 (data), Rsrc2 (base), imm                     |
| `JMP/JZ/JN/JC/CALL target`    | imm (zero-extended)                                 |
| `INT i`                       | index bit 16                                        |

## 3. Questa / ModelSim

```sh
vsim -c -do "do scripts/questa_compile.do; quit"                 # RTL as -93, TBs as -2008
vsim -do "do scripts/questa_compile.do; do scripts/questa_run.do tb_top"
vsim -c "-gMEM_FILE=programs/demo.mem" "-gGOLDEN_FILE=programs/demo.golden" work.tb_system -do "run -all; quit"
```

`questa_run.do` adds a useful wave set for `tb_top`/`tb_system`: PC, SP, CCR,
OUT.PORT, `R_values`, the fetch side band, the stall/mispredict/redirect/
interrupt signals, and the forwarding selects. Run Questa from the repository
root so that the relative `programs/...` paths resolve.

## 4. Quartus Prime Lite 16.1 (Cyclone V 5CSEMA5F31C6)

Add `rtl/*.vhd` (VHDL-93) and set `top` as the top-level entity. Copy
`programs/program.mif` (or your own `.mif`) to the project directory. The
unified RAM in `data_mem.vhd` carries `ram_init_file = "program.mif"` and
infers M10K blocks. The register file is forced to logic (`ramstyle "logic"`).
The mixed-port write-first behaviour needs bypass logic, which Quartus adds
around the M10K.

## 5. Top-level ports

| port       | dir | width        | description                         |
|------------|-----|--------------|-------------------------------------|
| `clk`      | in  | 1            | clock (rising edge)                 |
| `reset`    | in  | 1            | synchronous, active high            |
| `intr_in`  | in  | 1            | hardware interrupt request (edge)   |
| `in_port`  | in  | 32           | IN.PORT                             |
| `out_port` | out | 32           | OUT.PORT (registered)               |
| `R_values` | out | 8 × 32       | R0..R7 (`reg_array_t`)              |
| `pc_out`   | out | 32           | PC                                  |
| `sp_out`   | out | 32           | SP                                  |
| `ccr_out`  | out | 4            | CCR (bit0 Z, bit1 N, bit2 C)        |
| `halted`   | out | 1            | HLT reached (added for testbenches) |

Generic `PROG : mem_t` gives the initial memory image for simulation.
