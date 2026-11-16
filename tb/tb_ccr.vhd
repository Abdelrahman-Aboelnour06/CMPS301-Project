-------------------------------------------------------------------------------
-- tb_ccr.vhd -- directed self-checking testbench for ccr.vhd
-- Reset, Z/N write without C, C write without Z/N, flush gating (both write
-- enables low), shadow save (INT), restore (RTI) with priority over a
-- simultaneous flag write, reserved bit 3 always 0.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_ccr is
end entity tb_ccr;

architecture sim of tb_ccr is
  signal clk     : std_logic := '0';
  signal reset   : std_logic := '1';
  signal z_in, n_in, c_in : std_logic := '0';
  signal zn_we, c_we      : std_logic := '0';
  signal save, restore    : std_logic := '0';
  signal ccr_out, shadow_out : std_logic_vector(3 downto 0);
begin
  clk <= not clk after 5 ns;

  dut : entity work.ccr
    port map (clk => clk, reset => reset, z_in => z_in, n_in => n_in,
              c_in => c_in, zn_we => zn_we, c_we => c_we, save => save,
              restore => restore, ccr_out => ccr_out, shadow_out => shadow_out);

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
  begin
    z_in <= '1'; n_in <= '1'; c_in <= '1'; zn_we <= '1'; c_we <= '1';
    tick;
    check_eq(ccr_out, "0000", "reset ccr (priority over writes)", errs);
    check_eq(shadow_out, "0000", "reset shadow", errs);
    reset <= '0';

    -- Z,N only
    zn_we <= '1'; c_we <= '0'; z_in <= '1'; n_in <= '0'; c_in <= '1'; tick;
    check_eq(ccr_out, "0001", "Z=1 N=0 C unchanged", errs);
    -- C only
    zn_we <= '0'; c_we <= '1'; z_in <= '0'; n_in <= '1'; c_in <= '1'; tick;
    check_eq(ccr_out, "0101", "C=1, Z/N unchanged", errs);
    -- all three
    zn_we <= '1'; c_we <= '1'; z_in <= '0'; n_in <= '1'; c_in <= '0'; tick;
    check_eq(ccr_out, "0010", "N only", errs);
    -- flush gating: enables low -> no change
    zn_we <= '0'; c_we <= '0'; z_in <= '1'; n_in <= '0'; c_in <= '1'; tick;
    check_eq(ccr_out, "0010", "gated (flush)", errs);

    -- save to shadow (INT) while also writing flags: shadow gets the OLD value
    save <= '1'; zn_we <= '1'; c_we <= '1'; z_in <= '1'; n_in <= '0'; c_in <= '1'; tick;
    save <= '0'; zn_we <= '0'; c_we <= '0';
    check_eq(shadow_out, "0010", "shadow saved", errs);
    check_eq(ccr_out, "0101", "ccr written same cycle", errs);

    -- ISR changes flags
    zn_we <= '1'; c_we <= '1'; z_in <= '0'; n_in <= '0'; c_in <= '0'; tick;
    check_eq(ccr_out, "0000", "ISR flags", errs);

    -- restore (RTI) with a concurrent write: restore wins
    restore <= '1'; zn_we <= '1'; c_we <= '1'; z_in <= '1'; n_in <= '1'; c_in <= '1'; tick;
    restore <= '0'; zn_we <= '0'; c_we <= '0';
    check_eq(ccr_out, "0010", "restored", errs);
    check_eq(shadow_out, "0010", "shadow unchanged by restore", errs);

    -- reserved bit 3 never set
    zn_we <= '1'; c_we <= '1'; z_in <= '1'; n_in <= '1'; c_in <= '1'; tick;
    check_eq(ccr_out, "0111", "all flags, bit3 = 0", errs);

    reset <= '1'; tick;
    check_eq(ccr_out, "0000", "reset again", errs);
    finish_tb("tb_ccr", errs);
    wait;
  end process;
end architecture sim;
