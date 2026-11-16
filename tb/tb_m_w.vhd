-------------------------------------------------------------------------------
-- tb_m_w.vhd -- directed self-checking testbench for m_w.vhd
-- Reset, capture of every field, hold (en = 0), flush -> bubble, flush
-- priority over hold, boundary data values.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_m_w is
end entity tb_m_w;

architecture sim of tb_m_w is
  signal clk, reset : std_logic := '1';
  signal en, flush  : std_logic := '0';
  signal ctrl_in, ctrl_out : ctrl_t := CTRL_NOP;
  signal res1_in, res2_in   : word_t := (others => '0');
  signal res1_out, res2_out : word_t;
  signal wa1_in, wa2_in     : raddr_t := "000";
  signal wa1_out, wa2_out   : raddr_t;
  signal c_swap : ctrl_t;
begin
  clk <= not clk after 5 ns;

  dut : entity work.m_w
    port map (clk => clk, reset => reset, en => en, flush => flush,
              ctrl_in => ctrl_in, res1_in => res1_in, res2_in => res2_in,
              wa1_in => wa1_in, wa2_in => wa2_in, ctrl_out => ctrl_out,
              res1_out => res1_out, res2_out => res2_out,
              wa1_out => wa1_out, wa2_out => wa2_out);

  -- a SWAP control word (both write ports)
  process
    variable c : ctrl_t;
  begin
    c := CTRL_NOP;
    c.valid := '1'; c.use_a := '1'; c.use_b := '1'; c.ra1_dst := '1';
    c.ra2_src1 := '1'; c.we1 := '1'; c.we2 := '1'; c.swap := '1';
    c_swap <= c;
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
    ctrl_in <= c_swap; res1_in <= x"80000000"; res2_in <= x"7FFFFFFF";
    wa1_in <= "000"; wa2_in <= "111";
    tick;
    check(ctrl_out = CTRL_NOP, "reset bubble", errs);
    check_eq(res1_out, x"00000000", "reset res1", errs);
    reset <= '0'; tick;
    check(ctrl_out = c_swap, "capture ctrl", errs);
    check_eq(res1_out, x"80000000", "res1 min", errs);
    check_eq(res2_out, x"7FFFFFFF", "res2 max", errs);
    check_eq(wa1_out, "000", "wa1 R0", errs);
    check_eq(wa2_out, "111", "wa2 R7", errs);

    en <= '0'; res1_in <= x"00000000"; ctrl_in <= CTRL_NOP; tick;
    check(ctrl_out = c_swap, "hold ctrl", errs);
    check_eq(res1_out, x"80000000", "hold res1", errs);

    flush <= '1'; tick;
    check(ctrl_out = CTRL_NOP, "flush beats hold", errs);

    flush <= '0'; en <= '1'; ctrl_in <= c_swap; tick;
    check(ctrl_out = c_swap, "resume", errs);
    check_eq(res1_out, x"00000000", "zero res1", errs);

    reset <= '1'; tick;
    check(ctrl_out = CTRL_NOP, "reset again", errs);
    finish_tb("tb_m_w", errs);
    wait;
  end process;
end architecture sim;
