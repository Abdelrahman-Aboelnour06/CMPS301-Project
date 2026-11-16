-------------------------------------------------------------------------------
-- instr_mem.vhd -- instruction-fetch (Port A) view of the unified memory.
--
-- The CMPS 301 machine is Von Neumann: one 4096 x 32 true dual-port M10K
-- array (data_mem.vhd) holds code and data. Port A of that array is the
-- read-only fetch port. This wrapper:
--   * converts the 32-bit PC into the 12-bit word index (PC[11:0]),
--   * drives the Port-A clock enable (deasserted on a load-use stall so the
--     registered RAM output -- the instruction word seen by D -- is held),
--   * returns the registered Port-A data as the D-stage instruction word.
-- The memory is initialised from a .mif in Quartus (ram_init_file attribute
-- in data_mem.vhd) and from the INIT generic in simulation.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity instr_mem is
  port (
    pc       : in  word_t;      -- current PC (address being fetched)
    hold     : in  std_logic;   -- '1' = keep the previously fetched word
    ram_addr : out maddr_t;     -- to data_mem Port A
    ram_en   : out std_logic;   -- to data_mem Port A clock enable
    ram_q    : in  word_t;      -- registered Port-A data from data_mem
    instr    : out word_t       -- instruction word for the D stage
  );
end entity instr_mem;

architecture rtl of instr_mem is
begin
  ram_addr <= pc(MEMINDEX-1 downto 0);
  ram_en   <= not hold;
  instr    <= ram_q;
end architecture rtl;
