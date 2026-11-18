-------------------------------------------------------------------------------
-- tb_if_d.vhd -- directed self-checking testbench for if_d.vhd
-- Reset, capture, hold (stall), flush (squash) and flush priority over hold,
-- is_vec propagation and clearing.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_if_d is
end entity tb_if_d;

architecture sim of tb_if_d is
  signal clk   : std_logic := '0';
  signal reset : std_logic := '1';
  signal en    : std_logic := '1';
  signal flush : std_logic := '0';
  signal d_in  : if_d_t := (valid => '1', is_vec => '0', pc => WORD_ZERO, pc1 => WORD_ZERO);
  signal d_out : if_d_t;
begin
  clk <= not clk after 5 ns;

  dut : entity work.if_d
    port map (clk => clk, reset => reset, en => en, flush => flush,
              d_in => d_in, d_out => d_out);

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
  begin
    d_in.pc <= x"00000123"; d_in.pc1 <= x"00000124"; d_in.is_vec <= '1';
    tick;
    check_sl(d_out.valid, '0', "reset valid", errs);
    check_sl(d_out.is_vec, '0', "reset is_vec", errs);
    check_eq(d_out.pc, x"00000000", "reset pc", errs);

    reset <= '0'; d_in.is_vec <= '0'; tick;
    check_sl(d_out.valid, '1', "capture valid", errs);
    check_eq(d_out.pc, x"00000123", "capture pc", errs);
    check_eq(d_out.pc1, x"00000124", "capture pc1", errs);

    -- stall: hold
    en <= '0'; d_in.pc <= x"00000200"; d_in.pc1 <= x"00000201"; tick;
    check_eq(d_out.pc, x"00000123", "hold pc", errs);
    check_sl(d_out.valid, '1', "hold valid", errs);

    -- flush while stalled: flush wins
    flush <= '1'; tick;
    check_sl(d_out.valid, '0', "flush beats hold", errs);
    check_eq(d_out.pc, x"00000200", "flush captures pc", errs);

    -- vector word
    flush <= '0'; en <= '1'; d_in.is_vec <= '1'; d_in.pc <= x"00000002"; tick;
    check_sl(d_out.is_vec, '1', "is_vec captured", errs);
    check_sl(d_out.valid, '1', "vector word valid", errs);
    flush <= '1'; tick;
    check_sl(d_out.is_vec, '0', "flush clears is_vec", errs);

    -- boundary pc
    flush <= '0'; d_in.is_vec <= '0'; d_in.pc <= x"FFFFFFFF"; d_in.pc1 <= x"00000000"; tick;
    check_eq(d_out.pc, x"FFFFFFFF", "max pc", errs);
    check_eq(d_out.pc1, x"00000000", "wrapped pc1", errs);

    reset <= '1'; tick;
    check_sl(d_out.valid, '0', "reset again", errs);
    finish_tb("tb_if_d", errs);
    wait;
  end process;
end architecture sim;
