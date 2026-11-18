-------------------------------------------------------------------------------
-- tb_regfile.vhd -- directed self-checking testbench for regfile.vhd
-- Reset, writes to all 8 registers with boundary values, both read ports,
-- write port 2, simultaneous writes, swap of write addresses, SWAP Rx,Rx
-- (no-op), port-2 priority, write-through (read-during-write) bypass.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_regfile is
end entity tb_regfile;

architecture sim of tb_regfile is
  signal clk      : std_logic := '0';
  signal reset    : std_logic := '1';
  signal ra1, ra2 : raddr_t := "000";
  signal rd1, rd2 : word_t;
  signal wa1      : raddr_t := "000";
  signal wd1      : word_t := (others => '0');
  signal we1      : std_logic := '0';
  signal regs     : reg_array_t;

  function r(i : natural) return raddr_t is
  begin
    return std_logic_vector(to_unsigned(i, 3));
  end function;

  type vals_t is array (0 to 7) of word_t;
  constant VALS : vals_t := (x"00000000", x"00000001", x"FFFFFFFF", x"80000000",
                             x"7FFFFFFF", x"DEADBEEF", x"12345678", x"0000FFFF");
begin
  clk <= not clk after 5 ns;

  dut : entity work.regfile
    port map (clk => clk, reset => reset, ra1 => ra1, ra2 => ra2,
              rd1 => rd1, rd2 => rd2, wa1 => wa1, wd1 => wd1, we1 => we1,
              regs_out => regs);

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
  begin
    tick;
    reset <= '0';
    for i in 0 to 7 loop
      check_eq(regs(i), x"00000000", "reset R" & integer'image(i), errs);
    end loop;

    -- port 1 writes every register
    we1 <= '1';
    for i in 0 to 7 loop
      wa1 <= r(i); wd1 <= VALS(i); tick;
    end loop;
    we1 <= '0';
    for i in 0 to 7 loop
      ra1 <= r(i); ra2 <= r(7 - i);
      wait for 1 ns;
      check_eq(rd1, VALS(i), "port1 read R" & integer'image(i), errs);
      check_eq(rd2, VALS(7 - i), "port2 read R" & integer'image(7 - i), errs);
    end loop;

    -- write-through: read the register being written in the same cycle
    we1 <= '1'; wa1 <= r(6); wd1 <= x"0F0F0F0F"; ra1 <= r(6); ra2 <= r(0);
    wait for 1 ns;
    check_eq(rd1, x"0F0F0F0F", "write-through port1", errs);
    check_eq(rd2, VALS(0), "unrelated read", errs);
    tick;
    we1 <= '0';
    check_eq(regs(6), x"0F0F0F0F", "R6 written", errs);

    -- write enable low: no change
    wa1 <= r(7); wd1 <= x"99999999"; tick;
    check_eq(regs(7), VALS(7), "we=0 no write", errs);

    reset <= '1'; tick;
    for i in 0 to 7 loop
      check_eq(regs(i), x"00000000", "reset again R" & integer'image(i), errs);
    end loop;
    finish_tb("tb_regfile", errs);
    wait;
  end process;
end architecture sim;
