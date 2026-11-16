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
    clk        : in  std_logic;
    reset      : in  std_logic;
    en         : in  std_logic;   -- '0' = hold (load-use stall)
    flush      : in  std_logic;   -- '1' = capture a bubble
    valid_in   : in  std_logic;
    is_vec_in  : in  std_logic;
    pc_in      : in  word_t;
    pc1_in     : in  word_t;
    valid_out  : out std_logic;
    is_vec_out : out std_logic;
    pc_out     : out word_t;
    pc1_out    : out word_t
  );
end entity if_d;

architecture rtl of if_d is
  signal valid_r  : std_logic := '0';
  signal is_vec_r : std_logic := '0';
  signal pc_r     : word_t    := (others => '0');
  signal pc1_r    : word_t    := (others => '0');
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        valid_r  <= '0';
        is_vec_r <= '0';
        pc_r     <= (others => '0');
        pc1_r    <= (others => '0');
      elsif flush = '1' then
        valid_r  <= '0';
        is_vec_r <= '0';
        pc_r     <= pc_in;
        pc1_r    <= pc1_in;
      elsif en = '1' then
        valid_r  <= valid_in;
        is_vec_r <= is_vec_in;
        pc_r     <= pc_in;
        pc1_r    <= pc1_in;
      end if;
    end if;
  end process;

  valid_out  <= valid_r;
  is_vec_out <= is_vec_r;
  pc_out     <= pc_r;
  pc1_out    <= pc1_r;
end architecture rtl;
