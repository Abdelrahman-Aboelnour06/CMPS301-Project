-------------------------------------------------------------------------------
-- Latch IRQ edges, drain the pipeline, then issue the interrupt micro-op.
-- One request can wait while an ISR runs. RTI releases it for service.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity intr_fsm is
  port (
    clk          : in  std_logic;
    reset        : in  std_logic;
    intr_in      : in  std_logic;
    front_busy   : in  std_logic;   -- valid D word or a vector being fetched
    halted       : in  std_logic;
    x1_ctrl      : in  ctrl_t;
    x2_ctrl      : in  ctrl_t;
    m_ctrl       : in  ctrl_t;
    w_ctrl       : in  ctrl_t;
    boot_busy    : in  std_logic;
    inject       : out std_logic;
    calm         : out std_logic;
    drain        : out std_logic;
    intr_pending : out std_logic;
    in_isr       : out std_logic
  );
end entity intr_fsm;

architecture rtl of intr_fsm is
  signal prev_r    : std_logic := '1';
  signal pending_r : std_logic := '0';
  signal in_isr_r  : std_logic := '0';
  signal calm_i    : std_logic;
  signal inject_i  : std_logic;
  signal drain_i   : std_logic;
begin

  calm_i <= not (front_busy or x1_ctrl.is_real_instruction or
                 x2_ctrl.is_real_instruction or m_ctrl.is_real_instruction or
                 w_ctrl.is_real_instruction or boot_busy or halted);

  drain_i  <= pending_r and not (in_isr_r or boot_busy or halted);
  inject_i <= drain_i and calm_i;
  inject   <= inject_i;
  calm     <= calm_i;
  drain    <= drain_i;

  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        prev_r    <= '1';          -- a level already high at reset is not an edge
        pending_r <= '0';
        in_isr_r  <= '0';
      else
        prev_r <= intr_in;

        if intr_in = '1' and prev_r = '0' then
          pending_r <= '1';
        elsif inject_i = '1' then
          pending_r <= '0';
        end if;

        if x2_ctrl.is_hardware_interrupt = '1' or x2_ctrl.is_software_interrupt = '1' then
          in_isr_r <= '1';
        elsif w_ctrl.is_return_from_interrupt = '1' then
          in_isr_r <= '0';
        end if;
      end if;
    end if;
  end process;

  intr_pending <= pending_r;
  in_isr       <= in_isr_r;
end architecture rtl;
