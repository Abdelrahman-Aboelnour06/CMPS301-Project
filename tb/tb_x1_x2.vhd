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
  signal ctrl_in, ctrl_out : ctrl_t := CTRL_NOP;
  signal res1_in, res2_in, a_in, b_in, imm_in, link_in : word_t := (others => '0');
  signal res1_out, res2_out, a_out, b_out, imm_out, link_out : word_t;
  signal wa1_in, wa2_in   : raddr_t := "000";
  signal wa1_out, wa2_out : raddr_t;
  signal c_st : ctrl_t;
begin
  clk <= not clk after 5 ns;

  dut : entity work.x1_x2
    port map (clk => clk, reset => reset, en => en, flush => flush,
              ctrl_in => ctrl_in, res1_in => res1_in, res2_in => res2_in,
              a_in => a_in, b_in => b_in, imm_in => imm_in, wa1_in => wa1_in,
              wa2_in => wa2_in, link_in => link_in, ctrl_out => ctrl_out,
              res1_out => res1_out, res2_out => res2_out, a_out => a_out,
              b_out => b_out, imm_out => imm_out, wa1_out => wa1_out,
              wa2_out => wa2_out, link_out => link_out);

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
    ctrl_in <= c_st; res1_in <= x"00000001"; res2_in <= x"00000002";
    a_in <= x"0000000A"; b_in <= x"0000000B"; imm_in <= x"00000004";
    wa1_in <= "111"; wa2_in <= "110"; link_in <= x"00000100";
    tick;
    check(ctrl_out = CTRL_NOP, "reset bubble", errs);
    reset <= '0'; tick;
    check(ctrl_out = c_st, "capture ctrl", errs);
    check_eq(res1_out, x"00000001", "res1", errs);
    check_eq(res2_out, x"00000002", "res2", errs);
    check_eq(a_out, x"0000000A", "a", errs);
    check_eq(b_out, x"0000000B", "b", errs);
    check_eq(imm_out, x"00000004", "imm", errs);
    check_eq(wa1_out, "111", "wa1", errs);
    check_eq(wa2_out, "110", "wa2", errs);
    check_eq(link_out, x"00000100", "link", errs);

    en <= '0'; res1_in <= x"FFFFFFFF"; tick;
    check_eq(res1_out, x"00000001", "hold", errs);

    flush <= '1'; tick;
    check(ctrl_out = CTRL_NOP, "flush beats hold", errs);
    check_sl(ctrl_out.memory_write, '0', "flushed store does not write", errs);

    flush <= '0'; en <= '1'; tick;
    check(ctrl_out = c_st, "resume", errs);
    check_eq(res1_out, x"FFFFFFFF", "max res1", errs);

    reset <= '1'; tick;
    check(ctrl_out = CTRL_NOP, "reset again", errs);
    finish_tb("tb_x1_x2", errs);
    wait;
  end process;
end architecture sim;
