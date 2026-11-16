-------------------------------------------------------------------------------
-- tb_intr_fsm.vhd -- directed self-checking testbench for intr_fsm.vhd
-- Edge latching, level does not re-trigger, every injection-gating
-- condition (bubble/vector in D, Jcc in D/X1/X2, RET/RTI in D/X1/X2/M/W,
-- mispredict, boot), clearing when the micro-op leaves X2, re-injection if
-- the micro-op is lost, in_ISR set by INT and IRQ and cleared by RTI,
-- requests ignored while in_ISR, reset.
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
  signal d_real      : std_logic := '0';
  signal d_ctrl_raw, x1_ctrl, x2_ctrl, m_ctrl, w_ctrl : ctrl_t := CTRL_NOP;
  signal mispredict  : std_logic := '0';
  signal boot_busy   : std_logic := '0';
  signal inject, calm, intr_pending, in_isr : std_logic;

  function c_jcc return ctrl_t is
    variable c : ctrl_t := CTRL_NOP;
  begin
    c.valid := '1'; c.is_jcc := '1'; c.cond := COND_Z;
    return c;
  end function;
  function c_ret(rti : boolean) return ctrl_t is
    variable c : ctrl_t := CTRL_NOP;
  begin
    c.valid := '1'; c.mem_rd := '1'; c.addr_sp := '1'; c.sp_inc := '1';
    if rti then c.is_rti := '1'; else c.is_ret := '1'; end if;
    return c;
  end function;
  function c_hw return ctrl_t is
    variable c : ctrl_t := CTRL_NOP;
  begin
    c.valid := '1'; c.is_hw := '1'; c.mem_wr := '1'; c.addr_sp := '1';
    c.sp_dec := '1'; c.st_link := '1';
    return c;
  end function;
  function c_int return ctrl_t is
    variable c : ctrl_t := c_hw;
  begin
    c.is_hw := '0'; c.is_int := '1';
    return c;
  end function;
begin
  clk <= not clk after 5 ns;

  dut : entity work.intr_fsm
    port map (clk => clk, reset => reset, intr_in => intr_in, d_real => d_real,
              d_ctrl_raw => d_ctrl_raw, x1_ctrl => x1_ctrl, x2_ctrl => x2_ctrl,
              m_ctrl => m_ctrl, w_ctrl => w_ctrl, mispredict => mispredict,
              boot_busy => boot_busy, inject => inject, calm => calm,
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
      d_ctrl_raw <= CTRL_NOP; x1_ctrl <= CTRL_NOP; x2_ctrl <= CTRL_NOP;
      m_ctrl <= CTRL_NOP; w_ctrl <= CTRL_NOP; mispredict <= '0';
      boot_busy <= '0'; d_real <= '1';
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

    -- every gating condition blocks injection
    for g in 0 to 11 loop
      quiet;
      case g is
        when 0  => d_real     <= '0';
        when 1  => d_ctrl_raw <= c_jcc;
        when 2  => x1_ctrl    <= c_jcc;
        when 3  => x2_ctrl    <= c_jcc;
        when 4  => d_ctrl_raw <= c_ret(false);
        when 5  => x1_ctrl    <= c_ret(true);
        when 6  => x2_ctrl    <= c_ret(false);
        when 7  => m_ctrl     <= c_ret(true);
        when 8  => w_ctrl     <= c_ret(false);
        when 9  => mispredict <= '1';
        when 10 => boot_busy  <= '1';
        when others => d_ctrl_raw <= c_ret(true);
      end case;
      wait for 1 ns;
      check_sl(calm, '0', "gate " & integer'image(g) & " calm", errs);
      check_sl(inject, '0', "gate " & integer'image(g) & " inject", errs);
      check_sl(intr_pending, '1', "gate " & integer'image(g) & " pending kept", errs);
    end loop;
    quiet;

    -- micro-op lost before M (pending stays) -> injects again next calm cycle
    tick; tick;
    check_sl(intr_pending, '1', "still pending (not serviced)", errs);
    check_sl(inject, '1', "re-inject", errs);

    -- micro-op leaves X2: pending cleared, in_isr set
    x2_ctrl <= c_hw; tick;
    x2_ctrl <= CTRL_NOP;
    check_sl(intr_pending, '0', "cleared at X2->M", errs);
    check_sl(in_isr, '1', "in ISR", errs);
    wait for 1 ns;
    check_sl(inject, '0', "no inject in ISR", errs);

    -- new edge while in ISR is ignored (non-nested)
    intr_in <= '0'; tick; intr_in <= '1'; tick;
    check_sl(intr_pending, '0', "edge ignored in ISR", errs);

    -- RTI in W clears in_isr
    w_ctrl <= c_ret(true); tick;
    w_ctrl <= CTRL_NOP;
    check_sl(in_isr, '0', "RTI clears in_isr", errs);
    -- level still high: no new request
    tick;
    check_sl(intr_pending, '0', "held level does not re-trigger", errs);

    -- software INT also enters the ISR state
    x2_ctrl <= c_int; tick;
    x2_ctrl <= CTRL_NOP;
    check_sl(in_isr, '1', "INT sets in_isr", errs);
    check_sl(intr_pending, '0', "INT does not touch pending", errs);
    w_ctrl <= c_ret(true); tick;
    w_ctrl <= CTRL_NOP;
    check_sl(in_isr, '0', "RTI after INT", errs);

    -- clear has priority over a simultaneous new edge
    intr_in <= '0'; tick; intr_in <= '1'; tick;
    check_sl(intr_pending, '1', "latched again", errs);
    intr_in <= '0'; tick;
    intr_in <= '1'; x2_ctrl <= c_hw; tick;
    x2_ctrl <= CTRL_NOP;
    check_sl(intr_pending, '0', "clear beats coincident edge", errs);

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
