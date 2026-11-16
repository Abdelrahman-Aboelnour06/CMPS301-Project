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
  signal wa1, wa2 : raddr_t := "000";
  signal wd1, wd2 : word_t := (others => '0');
  signal we1, we2 : std_logic := '0';
  signal swap     : std_logic := '0';
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
              wa2 => wa2, wd2 => wd2, we2 => we2, swap => swap,
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

    -- port 2 write alone
    we2 <= '1'; wa2 <= r(3); wd2 <= x"33333333"; tick;
    we2 <= '0';
    check_eq(regs(3), x"33333333", "port2 write", errs);

    -- both ports, different registers, no swap
    we1 <= '1'; wa1 <= r(1); wd1 <= x"AAAAAAAA";
    we2 <= '1'; wa2 <= r(2); wd2 <= x"BBBBBBBB"; tick;
    check_eq(regs(1), x"AAAAAAAA", "dual write R1", errs);
    check_eq(regs(2), x"BBBBBBBB", "dual write R2", errs);

    -- swap: wd1 -> wa2, wd2 -> wa1 (SWAP R1,R2 carries old R1 in wd1)
    swap <= '1';
    wa1 <= r(1); wd1 <= regs(1);
    wa2 <= r(2); wd2 <= regs(2); tick;
    check_eq(regs(1), x"BBBBBBBB", "swap R1", errs);
    check_eq(regs(2), x"AAAAAAAA", "swap R2", errs);

    -- SWAP R4,R4: same address, same data -> unchanged
    wa1 <= r(4); wa2 <= r(4); wd1 <= regs(4); wd2 <= regs(4); tick;
    check_eq(regs(4), VALS(4), "SWAP Rx,Rx no-op", errs);

    -- same address, different data: port 2 wins
    swap <= '0'; wa1 <= r(5); wa2 <= r(5); wd1 <= x"11111111"; wd2 <= x"22222222"; tick;
    check_eq(regs(5), x"22222222", "port2 priority", errs);
    we1 <= '0'; we2 <= '0';

    -- write-through: read the register being written in the same cycle
    we1 <= '1'; wa1 <= r(6); wd1 <= x"0F0F0F0F"; ra1 <= r(6); ra2 <= r(0);
    wait for 1 ns;
    check_eq(rd1, x"0F0F0F0F", "write-through port1", errs);
    check_eq(rd2, VALS(0), "unrelated read", errs);
    we2 <= '1'; wa2 <= r(6); wd2 <= x"F0F0F0F0";
    wait for 1 ns;
    check_eq(rd1, x"F0F0F0F0", "write-through port2 priority", errs);
    swap <= '1'; wa2 <= r(0);     -- effective: wd1 -> R0, wd2 -> R6
    wait for 1 ns;
    check_eq(rd1, x"F0F0F0F0", "write-through with swap (R6 <- wd2)", errs);
    check_eq(rd2, x"0F0F0F0F", "write-through with swap (R0 <- wd1)", errs);
    tick;
    we1 <= '0'; we2 <= '0'; swap <= '0';
    check_eq(regs(6), x"F0F0F0F0", "R6 written", errs);
    check_eq(regs(0), x"0F0F0F0F", "R0 written (R0 is a normal register)", errs);

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
