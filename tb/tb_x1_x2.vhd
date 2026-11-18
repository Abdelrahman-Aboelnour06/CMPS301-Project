-------------------------------------------------------------------------------
-- tb_x1_x2.vhd -- directed self-checking testbench for x1_x2.vhd
-- Reset, capture, hold, mispredict flush -> bubble (kills the X1
-- instruction's later effects), flush priority over hold.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_x1_x2 is
end entity tb_x1_x2;

architecture sim of tb_x1_x2 is
  signal clk, reset : std_logic := '1';
  signal en, flush  : std_logic := '0';
  signal d_in       : x1_x2_t := X1_X2_NOP;
  signal d_out      : x1_x2_t;
  signal c_st       : ctrl_t;
begin
  clk <= not clk after 5 ns;

  dut : entity work.x1_x2
    port map (clk => clk, reset => reset, en => en, flush => flush,
              d_in => d_in, d_out => d_out);

  -- an STD control word
  process
    variable c : ctrl_t;
  begin
    c := CTRL_NOP;
    c.is_real_instruction := '1';
    c.reads_operand_a := '1';
    c.reads_operand_b := '1';
    c.memory_write := '1';
    c.base_address_is_operand_b := '1';
    c_st <= c;
    wait;
  end process;

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
  begin
    en <= '1';
    wait for 1 ns;
    d_in.control <= c_st; d_in.result_1 <= x"00000001"; d_in.result_2 <= x"00000002";
    d_in.operand_a <= x"0000000A"; d_in.operand_b <= x"0000000B"; d_in.immediate <= x"0004";
    d_in.write_addr_1 <= "111"; d_in.write_addr_2 <= "110"; d_in.link_address <= x"00000100";
    tick;
    check(d_out.control = CTRL_NOP, "reset bubble", errs);
    reset <= '0'; tick;
    check(d_out.control = c_st, "capture ctrl", errs);
    check_eq(d_out.result_1, x"00000001", "res1", errs);
    check_eq(d_out.result_2, x"00000002", "res2", errs);
    check_eq(d_out.operand_a, x"0000000A", "a", errs);
    check_eq(d_out.operand_b, x"0000000B", "b", errs);
    check_eq(d_out.immediate, x"0004", "imm", errs);
    check_eq(d_out.write_addr_1, "111", "wa1", errs);
    check_eq(d_out.write_addr_2, "110", "wa2", errs);
    check_eq(d_out.link_address, x"00000100", "link", errs);

    en <= '0'; d_in.result_1 <= x"FFFFFFFF"; tick;
    check_eq(d_out.result_1, x"00000001", "hold", errs);

    flush <= '1'; tick;
    check(d_out.control = CTRL_NOP, "flush beats hold", errs);
    check_sl(d_out.control.memory_write, '0', "flushed store does not write", errs);

    flush <= '0'; en <= '1'; tick;
    check(d_out.control = c_st, "resume", errs);
    check_eq(d_out.result_1, x"FFFFFFFF", "max res1", errs);

    reset <= '1'; tick;
    check(d_out.control = CTRL_NOP, "reset again", errs);
    finish_tb("tb_x1_x2", errs);
    wait;
  end process;
end architecture sim;
