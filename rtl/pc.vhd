-------------------------------------------------------------------------------
-- pc.vhd -- 32-bit program counter register with PC+1 incrementer.
-- Synchronous active-high reset to 0 (the reset FSM then loads M[0]).
-- en = '0' holds the current value (stall / fetch-hold / HLT).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity pc is
  port (
    clk      : in  std_logic;
    reset    : in  std_logic;
    en       : in  std_logic;
    pc_next  : in  word_t;
    pc_q     : out word_t;
    pc_plus1 : out word_t
  );
end entity pc;

architecture rtl of pc is
  signal pc_r : word_t := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        pc_r <= (others => '0');
      elsif en = '1' then
        pc_r <= pc_next;
      end if;
    end if;
  end process;

  pc_q     <= pc_r;
  pc_plus1 <= std_logic_vector(unsigned(pc_r) + 1);
end architecture rtl;
