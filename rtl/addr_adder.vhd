-------------------------------------------------------------------------------
-- addr_adder.vhd -- X2 effective-address adder for LDD / STD.
--   ea = base + offset  (offset is the sign-extended 16-bit immediate)
-- The full 32-bit sum is produced; the RAM uses ea[11:0].
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity addr_adder is
  port (
    base   : in  word_t;
    offset : in  word_t;
    ea     : out word_t
  );
end entity addr_adder;

architecture rtl of addr_adder is
begin
  ea <= std_logic_vector(unsigned(base) + unsigned(offset));
end architecture rtl;
