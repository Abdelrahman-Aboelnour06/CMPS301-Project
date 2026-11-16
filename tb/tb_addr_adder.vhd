-------------------------------------------------------------------------------
-- tb_addr_adder.vhd -- directed self-checking testbench for addr_adder.vhd
-- Positive / negative / zero offsets, 32-bit wrap-around, 12-bit boundary.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_addr_adder is
end entity tb_addr_adder;

architecture sim of tb_addr_adder is
  signal base, offset, ea : word_t := (others => '0');
begin
  dut : entity work.addr_adder
    port map (base => base, offset => offset, ea => ea);

  stim : process
    variable errs : natural := 0;
    procedure t(bv, ov, ev : word_t; name : string) is
    begin
      base <= bv; offset <= ov;
      wait for 1 ns;
      check_eq(ea, ev, name, errs);
    end procedure;
  begin
    t(x"00000000", x"00000000", x"00000000", "0+0");
    t(x"00000100", x"00000005", x"00000105", "base+5");
    t(x"00000100", sext16(x"FFFF"), x"000000FF", "base-1");
    t(x"00000100", sext16(x"8000"), x"FFFF8100", "base-32768");
    t(x"00000000", sext16(x"7FFF"), x"00007FFF", "0+32767");
    t(x"00000FFF", x"00000001", x"00001000", "4095+1 (RAM index wraps to 0)");
    t(x"FFFFFFFF", x"00000001", x"00000000", "32-bit wrap");
    t(x"00000000", sext16(x"FFFF"), x"FFFFFFFF", "0-1");
    t(x"80000000", x"80000000", x"00000000", "min+min");
    finish_tb("tb_addr_adder", errs);
    wait;
  end process;
end architecture sim;
