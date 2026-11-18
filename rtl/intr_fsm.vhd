-------------------------------------------------------------------------------
-- intr_fsm.vhd -- hardware interrupt (INTR.IN) request latch and injection.
--
--   intr_pending : set on a rising edge of intr_in while in_ISR = '0'
--                  (a line already high when reset is released is not an
--                  edge);
--                  cleared when the injected micro-op leaves X2 (enters M).
--                  (Clear has priority over a simultaneous new edge.)
--   in_isr       : set when an INT or IRQ micro-op leaves X2; cleared when
--                  RTI is in W. Gates new requests and injection
--                  (non-nested interrupts, single shadow CCR).
--   inject       : replace the D-stage instruction by the IRQ micro-op.
--                  Allowed only in a "calm" cycle:
--                    * a real instruction is in D (not a bubble / vector),
--                    * no Jcc in D, X1, X2,
--                    * no RET / RTI in D, X1, X2, M, W,
--                    * no X2 mispredict, not booting.
--                  If the micro-op were ever flushed before M, pending stays
--                  set and injection repeats at the next calm cycle.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity intr_fsm is
  port (
    clk          : in  std_logic;
    reset        : in  std_logic;
    intr_in      : in  std_logic;
    d_real       : in  std_logic;   -- IF/D holds a real instruction
    d_ctrl_raw   : in  ctrl_t;      -- decode of D before injection
    x1_ctrl      : in  ctrl_t;
    x2_ctrl      : in  ctrl_t;
    m_ctrl       : in  ctrl_t;
    w_ctrl       : in  ctrl_t;
    mispredict   : in  std_logic;
    boot_busy    : in  std_logic;
    inject       : out std_logic;
    calm         : out std_logic;
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
  signal ret_busy  : std_logic;
begin

  ret_busy <= d_ctrl_raw.is_return or d_ctrl_raw.is_return_from_interrupt or
              x1_ctrl.is_return    or x1_ctrl.is_return_from_interrupt    or
              x2_ctrl.is_return    or x2_ctrl.is_return_from_interrupt    or
              m_ctrl.is_return     or m_ctrl.is_return_from_interrupt     or
              w_ctrl.is_return     or w_ctrl.is_return_from_interrupt;

  -- BUG-001 fix: a Jcc in D/X1/X2 no longer blocks injection.
  --   Jcc in X1 -> D always holds a bubble (the Jcc's D redirect flushed IF/D).
  --   Jcc in X2 -> 'not mispredict' already proves D is on the correct path.
  --   Jcc in D  -> replaced by the micro-op; it re-executes after RTI with
  --                the restored CCR.
  -- With the old Jcc gate, INTR.IN starved forever in any loop of <= 2
  -- instructions closed by a Jcc (e.g. L: AND R2,R1,R1 ; JZ L).
  calm_i <= d_real and not ret_busy and
            not mispredict and not boot_busy;

  inject_i <= pending_r and not in_isr_r and calm_i;
  inject   <= inject_i;
  calm   <= calm_i;

  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        prev_r    <= '1';          -- a level already high at reset is not an edge
        pending_r <= '0';
        in_isr_r  <= '0';
      else
        prev_r <= intr_in;

        -- BUG-002 fix: every rising edge is latched, including edges that
        -- arrive while in_ISR = 1. The request waits (no nesting) and is
        -- injected after RTI clears in_ISR. The latch is cleared when the
        -- micro-op is injected: once injected it cannot be flushed (inject
        -- needs no mispredict, the micro-op reads no register so it cannot
        -- stall, and a Jcc in X1 implies a bubble in D), so a new edge in
        -- the following cycles is a new request, not merged with this one.
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
