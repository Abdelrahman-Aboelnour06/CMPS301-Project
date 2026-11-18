-------------------------------------------------------------------------------
-- if_d.vhd -- IF/D pipeline register.
-- The instruction word itself is the registered Port-A output of the RAM
-- (held by the Port-A clock enable); this register carries its side-band:
--   valid  : the word is a real fetched word (0 = squashed / bubble)
--   is_vec : the word is an interrupt/INT vector, not an instruction
--   pc     : address of the word
--   pc1    : address + 1 (link / fall-through)
-- flush has priority over en (hold).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity if_d is
  port (
    clk   : in  std_logic;
    reset : in  std_logic;
    en    : in  std_logic;              -- '0' = hold (load-use stall)
    flush : in  std_logic;              -- '1' = capture a bubble
    d_in  : in  if_d_t;
    d_out : out if_d_t
  );
end entity if_d;

architecture rtl of if_d is
  signal reg : if_d_t := IF_D_NOP;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        reg <= IF_D_NOP;
      elsif flush = '1' then
        reg.is_valid  <= '0';
        reg.is_interrupt_vector <= '0';
        reg.program_counter     <= d_in.program_counter;
        reg.next_program_counter    <= d_in.next_program_counter;
      elsif en = '1' then
        reg <= d_in;
      end if;
    end if;
  end process;

  d_out <= reg;
end architecture rtl;
