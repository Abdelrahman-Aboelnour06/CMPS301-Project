-------------------------------------------------------------------------------
-- tb_top.vhd -- full-pipeline smoke test (no external files).
-- A fixed 10-instruction program (forwarding at distance 1 and 2, SWAP,
-- PUSH/POP, AND, INC, HLT) is placed in memory through the PROG generic,
-- the core is reset, run until HLT drains, and R0..R7, SP, CCR, PC and
-- OUT.PORT are compared with the expected values. Also checks that no
-- observable output carries 'U'/'X'.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_top is
end entity tb_top;

architecture sim of tb_top is
  function prog_smoke return mem_t is
    variable m : mem_t := MEM_ZERO;
  begin
    m(0) := x"00000010";  -- vector
    m(16) := enc(OP_LDM, rd => 1, imm => 5);  -- 0x010: LDM R1, 5
    m(17) := enc(OP_LDM, rd => 2, imm => 7);  -- 0x011: LDM R2, 7
    m(18) := enc(OP_ADD, rd => 3, rs1 => 1, rs2 => 2);  -- 0x012: ADD R3, R1, R2
    m(19) := enc(OP_SUB, rd => 4, rs1 => 3, rs2 => 1);  -- 0x013: SUB R4, R3, R1
    m(20) := enc(OP_SWAP, rd => 1, rs1 => 2);  -- 0x014: SWAP R1, R2
    m(21) := enc(OP_PUSH, rs1 => 3);  -- 0x015: PUSH R3
    m(22) := enc(OP_POP, rd => 5);  -- 0x016: POP R5
    m(23) := enc(OP_AND, rd => 6, rs1 => 4, rs2 => 3);  -- 0x017: AND R6, R4, R3
    m(24) := enc(OP_INC, rd => 7);  -- 0x018: INC R7
    m(25) := enc(OP_HLT);  -- 0x019: HLT
    return m;
  end function;
  signal clk      : std_logic := '0';
  signal reset    : std_logic := '1';
  signal intr_in  : std_logic := '0';
  signal in_port  : word_t := (others => '0');
  signal out_port : word_t;
  signal regs     : reg_array_t;
  signal rmap     : rename_map_t;
  signal pc_out   : word_t;
  signal sp_out   : word_t;
  signal ccr_out  : std_logic_vector(3 downto 0);
  signal halted   : std_logic;

  type exp_t is array (0 to 7) of word_t;
  constant EXP_R : exp_t := (x"00000000", x"00000007", x"00000005", x"0000000C",
                             x"00000007", x"0000000C", x"00000004", x"00000001");
begin
  clk <= not clk after 5 ns;

  rmap <= << signal dut.rename_map : rename_map_t >>;

  dut : entity work.top
    generic map (PROG => prog_smoke)
    port map (clk => clk, reset => reset, intr_in => intr_in, in_port => in_port,
              out_port => out_port, R_values => regs, pc_out => pc_out,
              sp_out => sp_out, ccr_out => ccr_out, halted => halted);

  stim : process
    variable errs   : natural := 0;
    variable cycles : natural := 0;
  begin
    for i in 1 to 3 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;
    check_eq(pc_out, x"00000000", "PC = 0 during reset", errs);
    check_eq(sp_out, x"00000FFF", "SP = 4095 during reset", errs);
    check_eq(ccr_out, "0000", "CCR = 0 during reset", errs);
    reset <= '0';
    wait until rising_edge(clk);
    wait until rising_edge(clk);
    wait for 1 ns;
    check_eq(pc_out, x"00000010", "boot: PC <- M[0]", errs);

    while halted /= '1' and cycles < 500 loop
      wait until rising_edge(clk);
      cycles := cycles + 1;
    end loop;
    check(halted = '1', "core halted", errs);
    for i in 1 to 8 loop                     -- let older instructions drain
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;

    for i in 0 to 7 loop
      check_eq(regs(to_integer(unsigned(rmap(i)))), EXP_R(i), "R" & integer'image(i), errs);
      check(not is_x(regs(to_integer(unsigned(rmap(i))))), "R" & integer'image(i) & " not X", errs);
    end loop;
    check_eq(sp_out, x"00000FFF", "SP balanced", errs);
    check_eq(ccr_out, "0000", "CCR", errs);
    check_eq(pc_out, x"0000001A", "PC frozen after HLT", errs);
    check_eq(out_port, x"00000000", "OUT.PORT untouched", errs);
    check(not (is_x(pc_out) or is_x(sp_out) or is_x(ccr_out) or is_x(out_port)),
          "no X on outputs", errs);
    -- HLT: PC stays frozen, no clock gating (clock still running)
    for i in 1 to 5 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;
    check_eq(pc_out, x"0000001A", "PC still frozen", errs);
    report "tb_top: halted after " & integer'image(cycles) & " cycles after boot";
    finish_tb("tb_top", errs);
    wait;
  end process;
end architecture sim;
