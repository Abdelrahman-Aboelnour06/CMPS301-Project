-------------------------------------------------------------------------------
-- tb_sp_unit.vhd -- directed self-checking testbench for sp_unit.vhd
-- Reset value 4095, pre-decrement push address, post-increment pop address,
-- idle hold, push/pop sequence, 32-bit wrap below 0, dec priority.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_sp_unit is
end entity tb_sp_unit;

architecture sim of tb_sp_unit is
  signal clk   : std_logic := '0';
  signal reset : std_logic := '1';
  signal dec   : std_logic := '0';
  signal inc   : std_logic := '0';
  signal sp    : word_t;
  signal addr  : word_t;
begin
  clk <= not clk after 5 ns;

  dut : entity work.sp_unit
    port map (clk => clk, reset => reset, dec => dec, inc => inc,
              sp => sp, addr => addr);

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
  begin
    dec <= '1'; tick;
    check_eq(sp, x"00000FFF", "reset 4095 (priority over dec)", errs);
    reset <= '0'; dec <= '0';
    wait for 1 ns;
    check_eq(addr, x"00000FFF", "idle addr = SP", errs);

    -- push: address SP-1, SP <- SP-1
    dec <= '1';
    wait for 1 ns;
    check_eq(addr, x"00000FFE", "push addr = SP-1", errs);
    tick;
    check_eq(sp, x"00000FFE", "after push", errs);
    tick;
    check_eq(sp, x"00000FFD", "after 2nd push", errs);

    -- pop: address SP, SP <- SP+1
    dec <= '0'; inc <= '1';
    wait for 1 ns;
    check_eq(addr, x"00000FFD", "pop addr = SP", errs);
    tick;
    check_eq(sp, x"00000FFE", "after pop", errs);

    -- idle
    inc <= '0'; tick;
    check_eq(sp, x"00000FFE", "idle hold", errs);

    -- dec has priority when both asserted
    dec <= '1'; inc <= '1';
    wait for 1 ns;
    check_eq(addr, x"00000FFD", "both: dec addr", errs);
    tick;
    check_eq(sp, x"00000FFD", "both: dec wins", errs);

    -- pop above 4095: 32-bit SP is not narrowed
    dec <= '0'; inc <= '1';
    for i in 1 to 3 loop tick; end loop;
    check_eq(sp, x"00001000", "SP = 4096 (32-bit)", errs);

    -- wrap below zero
    reset <= '1'; inc <= '0'; tick; reset <= '0';
    dec <= '1';
    for i in 1 to 4095 loop tick; end loop;
    check_eq(sp, x"00000000", "SP reaches 0", errs);
    wait for 1 ns;
    check_eq(addr, x"FFFFFFFF", "push at 0 addr = 0xFFFFFFFF", errs);
    tick;
    check_eq(sp, x"FFFFFFFF", "SP wraps to 0xFFFFFFFF", errs);
    dec <= '0';
    finish_tb("tb_sp_unit", errs);
    wait;
  end process;
end architecture sim;
