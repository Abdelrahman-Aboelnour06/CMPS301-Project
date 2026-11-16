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
  signal clk        : std_logic := '0';
  signal reset      : std_logic := '1';
  signal en         : std_logic := '1';
  signal flush      : std_logic := '0';
  signal valid_in   : std_logic := '1';
  signal is_vec_in  : std_logic := '0';
  signal pc_in      : word_t := (others => '0');
  signal pc1_in     : word_t := (others => '0');
  signal valid_out  : std_logic;
  signal is_vec_out : std_logic;
  signal pc_out     : word_t;
  signal pc1_out    : word_t;
begin
  clk <= not clk after 5 ns;

  dut : entity work.if_d
    port map (clk => clk, reset => reset, en => en, flush => flush,
              valid_in => valid_in, is_vec_in => is_vec_in, pc_in => pc_in,
              pc1_in => pc1_in, valid_out => valid_out, is_vec_out => is_vec_out,
              pc_out => pc_out, pc1_out => pc1_out);

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
  begin
    pc_in <= x"00000123"; pc1_in <= x"00000124"; is_vec_in <= '1';
    tick;
    check_sl(valid_out, '0', "reset valid", errs);
    check_sl(is_vec_out, '0', "reset is_vec", errs);
    check_eq(pc_out, x"00000000", "reset pc", errs);

    reset <= '0'; is_vec_in <= '0'; tick;
    check_sl(valid_out, '1', "capture valid", errs);
    check_eq(pc_out, x"00000123", "capture pc", errs);
    check_eq(pc1_out, x"00000124", "capture pc1", errs);

    -- stall: hold
    en <= '0'; pc_in <= x"00000200"; pc1_in <= x"00000201"; tick;
    check_eq(pc_out, x"00000123", "hold pc", errs);
    check_sl(valid_out, '1', "hold valid", errs);

    -- flush while stalled: flush wins
    flush <= '1'; tick;
    check_sl(valid_out, '0', "flush beats hold", errs);
    check_eq(pc_out, x"00000200", "flush captures pc", errs);

    -- vector word
    flush <= '0'; en <= '1'; is_vec_in <= '1'; pc_in <= x"00000002"; tick;
    check_sl(is_vec_out, '1', "is_vec captured", errs);
    check_sl(valid_out, '1', "vector word valid", errs);
    flush <= '1'; tick;
    check_sl(is_vec_out, '0', "flush clears is_vec", errs);

    -- boundary pc
    flush <= '0'; is_vec_in <= '0'; pc_in <= x"FFFFFFFF"; pc1_in <= x"00000000"; tick;
    check_eq(pc_out, x"FFFFFFFF", "max pc", errs);
    check_eq(pc1_out, x"00000000", "wrapped pc1", errs);

    reset <= '1'; tick;
    check_sl(valid_out, '0', "reset again", errs);
    finish_tb("tb_if_d", errs);
    wait;
  end process;
end architecture sim;
