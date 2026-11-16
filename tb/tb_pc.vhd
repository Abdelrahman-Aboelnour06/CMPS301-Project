-------------------------------------------------------------------------------
-- tb_pc.vhd -- directed self-checking testbench for pc.vhd
-- Reset value, load, hold (en = 0), PC+1 incrementer including the
-- 0xFFFFFFFF -> 0 wrap, reset priority over enable.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_pc is
end entity tb_pc;

architecture sim of tb_pc is
  signal clk      : std_logic := '0';
  signal reset    : std_logic := '1';
  signal en       : std_logic := '0';
  signal pc_next  : word_t := (others => '0');
  signal pc_q     : word_t;
  signal pc_plus1 : word_t;
begin
  clk <= not clk after 5 ns;

  dut : entity work.pc
    port map (clk => clk, reset => reset, en => en, pc_next => pc_next,
              pc_q => pc_q, pc_plus1 => pc_plus1);

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
  begin
    pc_next <= x"DEADBEEF"; en <= '1'; reset <= '1';
    tick;
    check_eq(pc_q, x"00000000", "reset -> 0 (priority over en)", errs);
    check_eq(pc_plus1, x"00000001", "0 + 1", errs);

    reset <= '0'; pc_next <= x"00000010"; en <= '1'; tick;
    check_eq(pc_q, x"00000010", "load 0x10", errs);
    check_eq(pc_plus1, x"00000011", "0x10 + 1", errs);

    en <= '0'; pc_next <= x"00000999"; tick;
    check_eq(pc_q, x"00000010", "hold", errs);
    tick;
    check_eq(pc_q, x"00000010", "hold 2", errs);

    en <= '1'; pc_next <= x"FFFFFFFF"; tick;
    check_eq(pc_q, x"FFFFFFFF", "load max", errs);
    check_eq(pc_plus1, x"00000000", "max + 1 wraps", errs);

    pc_next <= x"00000FFF"; tick;
    check_eq(pc_plus1, x"00001000", "4095 + 1 (no 12-bit narrowing)", errs);

    -- sequential counting using its own incrementer
    pc_next <= x"00000000"; tick;
    for i in 1 to 5 loop
      pc_next <= pc_plus1; tick;
    end loop;
    check_eq(pc_q, x"00000005", "count to 5", errs);

    reset <= '1'; tick;
    check_eq(pc_q, x"00000000", "reset again", errs);
    finish_tb("tb_pc", errs);
    wait;
  end process;
end architecture sim;
