-------------------------------------------------------------------------------
-- tb_intr_fsm.vhd -- directed self-checking testbench for intr_fsm.vhd
-- Check IRQ edge capture, pipeline draining, ISR deferral and reset.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_intr_fsm is
end entity tb_intr_fsm;

architecture sim of tb_intr_fsm is
  signal clk, reset  : std_logic := '1';
  signal intr_in     : std_logic := '0';
  signal front_busy      : std_logic := '0';
  signal x1_ctrl, x2_ctrl, m_ctrl, w_ctrl : ctrl_t := CTRL_NOP;
  signal halted      : std_logic := '0';
  signal boot_busy   : std_logic := '0';
  signal inject, calm, drain, intr_pending, in_isr : std_logic;

  function c_jcc return ctrl_t is
    variable c : ctrl_t := CTRL_NOP;
  begin
    c.is_real_instruction := '1';
    c.is_conditional_jump := '1';
    c.jump_condition := COND_Z;
    return c;
  end function;
  function c_ret(rti : boolean) return ctrl_t is
    variable c : ctrl_t := CTRL_NOP;
  begin
    c.is_real_instruction := '1';
    c.memory_read := '1';
    c.memory_address_from_sp := '1';
    c.stack_pointer_increment := '1';
    if rti then c.is_return_from_interrupt := '1'; else c.is_return := '1'; end if;
    return c;
  end function;
  function c_hw return ctrl_t is
    variable c : ctrl_t := CTRL_NOP;
  begin
    c.is_real_instruction := '1';
    c.is_hardware_interrupt := '1';
    c.memory_write := '1';
    c.memory_address_from_sp := '1';
    c.stack_pointer_decrement := '1';
    c.store_link_address := '1';
    return c;
  end function;
  function c_int return ctrl_t is
    variable c : ctrl_t := c_hw;
  begin
    c.is_hardware_interrupt := '0';
    c.is_software_interrupt := '1';
    return c;
  end function;
begin
  clk <= not clk after 5 ns;

  dut : entity work.intr_fsm
    port map (clk => clk, reset => reset, intr_in => intr_in, front_busy => front_busy,
              halted => halted, x1_ctrl => x1_ctrl, x2_ctrl => x2_ctrl,
              m_ctrl => m_ctrl, w_ctrl => w_ctrl,
              boot_busy => boot_busy, inject => inject, calm => calm, drain => drain,
              intr_pending => intr_pending, in_isr => in_isr);

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
    procedure quiet is
    begin
      x1_ctrl <= CTRL_NOP; x2_ctrl <= CTRL_NOP;
      m_ctrl <= CTRL_NOP; w_ctrl <= CTRL_NOP; halted <= '0';
      boot_busy <= '0'; front_busy <= '0';
    end procedure;
  begin
    intr_in <= '1';                 -- held high during reset: must not latch
    tick; tick;
    check_sl(intr_pending, '0', "reset pending", errs);
    check_sl(in_isr, '0', "reset in_isr", errs);
    reset <= '0'; quiet; tick;
    check_sl(intr_pending, '0', "level after reset is not an edge", errs);
    wait for 1 ns;
    check_sl(calm, '1', "calm", errs);
    check_sl(inject, '0', "nothing pending", errs);

    -- rising edge latches
    intr_in <= '0'; tick;
    intr_in <= '1'; tick;
    check_sl(intr_pending, '1', "edge latched", errs);
    check_sl(inject, '1', "inject when calm", errs);

    -- Any in-flight instruction must finish before injection.
    for g in 0 to 6 loop
      quiet;
      case g is
        when 0 => front_busy <= '1';
        when 1 => x1_ctrl <= c_ret(false);
        when 2 => x2_ctrl <= c_jcc;
        when 3 => m_ctrl <= c_ret(true);
        when 4 => w_ctrl <= c_ret(false);
        when 5 => boot_busy <= '1';
        when others => halted <= '1';
      end case;
      wait for 1 ns;
      check_sl(calm, '0', "pipeline unavailable", errs);
      check_sl(inject, '0', "wait before injecting", errs);
      check_sl(intr_pending, '1', "pending kept", errs);
      if g < 5 then
        check_sl(drain, '1', "block new fetches during drain", errs);
      else
        check_sl(drain, '0', "no drain during boot or halt", errs);
      end if;
    end loop;
    quiet;

    -- injection cycle: pending is cleared on inject, no second injection
    tick;
    check_sl(intr_pending, '0', "cleared on inject", errs);
    check_sl(inject, '0', "no re-inject once cleared", errs);

    -- micro-op leaves X2: in_isr set, pending stays clear
    x2_ctrl <= c_hw; tick;
    x2_ctrl <= CTRL_NOP;
    check_sl(in_isr, '1', "in ISR", errs);
    check_sl(intr_pending, '0', "pending clear after X2->M", errs);

    -- new edge while in ISR is queued, not dropped (BUG-002)
    intr_in <= '0'; tick; intr_in <= '1'; tick;
    check_sl(intr_pending, '1', "edge queued in ISR", errs);
    check_sl(inject, '0', "no inject while in ISR", errs);
    check_sl(drain, '0', "ISR fetches can continue", errs);

    -- RTI in W clears in_isr; the queued request is injected next
    w_ctrl <= c_ret(true); tick;
    w_ctrl <= CTRL_NOP;
    check_sl(in_isr, '0', "RTI clears in_isr", errs);
    wait for 1 ns;
    check_sl(inject, '1', "queued edge injects after RTI", errs);
    tick;                           -- injection consumes the request
    check_sl(intr_pending, '0', "queued request consumed", errs);
    -- level still high: no new request
    tick;
    check_sl(intr_pending, '0', "held level does not re-trigger", errs);

    -- software INT also enters the ISR state
    x2_ctrl <= c_int; tick;
    x2_ctrl <= CTRL_NOP;
    check_sl(in_isr, '1', "INT sets in_isr", errs);
    check_sl(intr_pending, '0', "INT does not touch pending", errs);
    -- an IRQ edge during a software-INT ISR is queued too
    intr_in <= '0'; tick; intr_in <= '1'; tick;
    check_sl(intr_pending, '1', "edge queued in INT ISR", errs);
    check_sl(inject, '0', "no inject in INT ISR", errs);
    w_ctrl <= c_ret(true); tick;
    w_ctrl <= CTRL_NOP;
    check_sl(in_isr, '0', "RTI after INT", errs);
    wait for 1 ns;
    check_sl(inject, '1', "INT-time edge injects after RTI", errs);
    tick;
    check_sl(intr_pending, '0', "INT-time request consumed", errs);

    -- an edge in the same cycle as an injection wins (set beats clear)
    boot_busy <= '1';               -- hold injection off while latching
    intr_in <= '0'; tick; intr_in <= '1'; tick;
    check_sl(intr_pending, '1', "latched again", errs);
    check_sl(inject, '0', "boot blocks inject", errs);
    intr_in <= '0'; tick;
    boot_busy <= '0'; intr_in <= '1'; tick;   -- inject cycle + new edge
    check_sl(intr_pending, '1', "edge beats coincident clear", errs);

    -- reset clears everything
    intr_in <= '0'; tick; intr_in <= '1'; tick;
    reset <= '1'; tick;
    check_sl(intr_pending, '0', "reset pending", errs);
    check_sl(in_isr, '0', "reset in_isr", errs);
    reset <= '0'; intr_in <= '0';
    finish_tb("tb_intr_fsm", errs);
    wait;
  end process;
end architecture sim;
