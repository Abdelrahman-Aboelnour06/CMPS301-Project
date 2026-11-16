-------------------------------------------------------------------------------
-- tb_reset_fsm.vhd -- directed self-checking testbench for reset_fsm.vhd
-- RST while reset is high (any duration), exactly one BOOT cycle with
-- boot_load, then RUN forever; reset re-asserted from RUN and from BOOT.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.tb_pkg.all;

entity tb_reset_fsm is
end entity tb_reset_fsm;

architecture sim of tb_reset_fsm is
  signal clk       : std_logic := '0';
  signal reset     : std_logic := '1';
  signal boot_busy : std_logic;
  signal boot_load : std_logic;
  signal st        : std_logic_vector(1 downto 0);
begin
  clk <= not clk after 5 ns;

  dut : entity work.reset_fsm
    port map (clk => clk, reset => reset, boot_busy => boot_busy,
              boot_load => boot_load, state_out => st);

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
  begin
    tick; tick; tick;
    check_eq(st, "00", "RST while reset", errs);
    check_sl(boot_busy, '1', "busy in RST", errs);
    check_sl(boot_load, '0', "no load in RST", errs);

    reset <= '0'; tick;
    check_eq(st, "01", "BOOT", errs);
    check_sl(boot_load, '1', "load PC <- M[0]", errs);
    check_sl(boot_busy, '1', "busy in BOOT", errs);
    tick;
    check_eq(st, "10", "RUN", errs);
    check_sl(boot_busy, '0', "not busy in RUN", errs);
    check_sl(boot_load, '0', "no load in RUN", errs);
    for i in 1 to 10 loop tick; end loop;
    check_eq(st, "10", "stays in RUN", errs);

    -- reset from RUN
    reset <= '1'; tick;
    check_eq(st, "00", "reset from RUN", errs);
    -- single-cycle reset, then reset during BOOT
    reset <= '0'; tick;
    check_eq(st, "01", "BOOT again", errs);
    reset <= '1'; tick;
    check_eq(st, "00", "reset during BOOT", errs);
    reset <= '0'; tick; tick;
    check_eq(st, "10", "RUN again", errs);
    finish_tb("tb_reset_fsm", errs);
    wait;
  end process;
end architecture sim;
