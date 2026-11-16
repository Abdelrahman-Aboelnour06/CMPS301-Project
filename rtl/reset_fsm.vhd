-------------------------------------------------------------------------------
-- reset_fsm.vhd -- boot sequencer.
--   S_RST  : reset asserted. PC = 0 is presented to RAM Port A. All state
--            elements (SP <- 4095, CCR <- 0, intr_pending/in_ISR <- 0,
--            pipeline registers, register file) are cleared by the same
--            synchronous reset.
--   S_BOOT : first cycle after reset release; the registered Port-A output
--            holds M[0]. boot_load = '1' loads PC <- M[0].
--   S_RUN  : normal operation.
-- boot_busy = '1' in S_RST and S_BOOT (fetch squashed, PC only via boot).
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;

entity reset_fsm is
  port (
    clk       : in  std_logic;
    reset     : in  std_logic;
    boot_busy : out std_logic;
    boot_load : out std_logic;
    state_out : out std_logic_vector(1 downto 0)   -- 00 RST, 01 BOOT, 10 RUN
  );
end entity reset_fsm;

architecture rtl of reset_fsm is
  type state_t is (S_RST, S_BOOT, S_RUN);
  signal st : state_t := S_RST;
begin
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        st <= S_RST;
      else
        case st is
          when S_RST  => st <= S_BOOT;
          when S_BOOT => st <= S_RUN;
          when S_RUN  => st <= S_RUN;
        end case;
      end if;
    end if;
  end process;

  boot_busy <= '0' when st = S_RUN  else '1';
  boot_load <= '1' when st = S_BOOT else '0';
  state_out <= "00" when st = S_RST  else
               "01" when st = S_BOOT else
               "10";
end architecture rtl;
