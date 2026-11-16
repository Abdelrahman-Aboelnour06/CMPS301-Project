-------------------------------------------------------------------------------
-- tb_hazard_unit.vhd -- directed self-checking testbench for hazard_unit.vhd
-- Load-use at distance 1 (stall) and distance 2 (no stall), via port A and
-- port B, POP and LDD, RET not a GPR load, stall suppressed by mispredict,
-- D redirect and its suppression, RET/RTI fetch-hold in every stage with
-- the W-stage PC load, HLT and its flush, boot control, reset.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_hazard_unit is
end entity tb_hazard_unit;

architecture sim of tb_hazard_unit is
  signal clk, reset     : std_logic := '1';
  signal d_ctrl, x1_ctrl, x2_ctrl, m_ctrl, w_ctrl : ctrl_t := CTRL_NOP;
  signal d_ra1, d_ra2, x1_wa1 : raddr_t := "000";
  signal d_redirect_req : std_logic := '0';
  signal mispredict     : std_logic := '0';
  signal boot_busy      : std_logic := '0';
  signal boot_load      : std_logic := '0';
  signal stall, d_redirect, fetch_hold, w_load : std_logic;
  signal halt_stop, halted, ifd_flush, dx1_flush, x1x2_flush, pc_en : std_logic;

  function c_use(a, b : std_logic) return ctrl_t is
    variable c : ctrl_t := CTRL_NOP;
  begin
    c.valid := '1'; c.use_a := a; c.use_b := b; c.we1 := '1';
    return c;
  end function;
  function c_ldd return ctrl_t is
    variable c : ctrl_t := CTRL_NOP;
  begin
    c.valid := '1'; c.use_a := '1'; c.mem_rd := '1'; c.we1 := '1';
    return c;
  end function;
  function c_pop return ctrl_t is
    variable c : ctrl_t := CTRL_NOP;
  begin
    c.valid := '1'; c.mem_rd := '1'; c.we1 := '1'; c.addr_sp := '1'; c.sp_inc := '1';
    return c;
  end function;
  function c_ret(rti : boolean) return ctrl_t is
    variable c : ctrl_t := CTRL_NOP;
  begin
    c.valid := '1'; c.mem_rd := '1'; c.addr_sp := '1'; c.sp_inc := '1';
    if rti then c.is_rti := '1'; else c.is_ret := '1'; end if;
    return c;
  end function;
  function c_hlt return ctrl_t is
    variable c : ctrl_t := CTRL_NOP;
  begin
    c.valid := '1'; c.is_hlt := '1';
    return c;
  end function;
begin
  clk <= not clk after 5 ns;

  dut : entity work.hazard_unit
    port map (clk => clk, reset => reset, d_ctrl => d_ctrl, d_ra1 => d_ra1,
              d_ra2 => d_ra2, d_redirect_req => d_redirect_req,
              x1_ctrl => x1_ctrl, x1_wa1 => x1_wa1, x2_ctrl => x2_ctrl,
              m_ctrl => m_ctrl, w_ctrl => w_ctrl, mispredict => mispredict,
              boot_busy => boot_busy, boot_load => boot_load, stall => stall,
              d_redirect => d_redirect, fetch_hold => fetch_hold,
              w_load => w_load, halt_stop => halt_stop, halted => halted,
              ifd_flush => ifd_flush, dx1_flush => dx1_flush,
              x1x2_flush => x1x2_flush, pc_en => pc_en);

  stim : process
    variable errs : natural := 0;
    procedure tick is
    begin
      wait until rising_edge(clk);
      wait for 1 ns;
    end procedure;
    procedure idle is
    begin
      d_ctrl <= CTRL_NOP; x1_ctrl <= CTRL_NOP; x2_ctrl <= CTRL_NOP;
      m_ctrl <= CTRL_NOP; w_ctrl <= CTRL_NOP; d_redirect_req <= '0';
      mispredict <= '0'; boot_busy <= '0'; boot_load <= '0';
    end procedure;
  begin
    tick;
    reset <= '0';
    idle;
    wait for 1 ns;
    check_sl(halted, '0', "reset halted", errs);
    check_sl(stall, '0', "idle stall", errs);
    check_sl(pc_en, '1', "idle pc_en", errs);
    check_sl(ifd_flush, '0', "idle ifd_flush", errs);
    check_sl(dx1_flush, '0', "idle dx1_flush", errs);

    ---------------------------------------------------------------- load-use
    -- distance 1, LDD in X1 writes R3, D reads R3 on port A
    x1_ctrl <= c_ldd; x1_wa1 <= "011";
    d_ctrl <= c_use('1', '0'); d_ra1 <= "011"; d_ra2 <= "000";
    wait for 1 ns;
    check_sl(stall, '1', "load-use d1 port A", errs);
    check_sl(pc_en, '0', "stall holds PC", errs);
    check_sl(dx1_flush, '1', "stall inserts bubble", errs);
    check_sl(ifd_flush, '0', "stall does not squash IF/D", errs);
    -- port B
    d_ctrl <= c_use('0', '1'); d_ra1 <= "000"; d_ra2 <= "011";
    wait for 1 ns;
    check_sl(stall, '1', "load-use d1 port B", errs);
    -- matching address but operand not used
    d_ctrl <= c_use('0', '0'); d_ra1 <= "011"; d_ra2 <= "011";
    wait for 1 ns;
    check_sl(stall, '0', "no use -> no stall", errs);
    -- different register
    d_ctrl <= c_use('1', '1'); d_ra1 <= "001"; d_ra2 <= "010";
    wait for 1 ns;
    check_sl(stall, '0', "different reg -> no stall", errs);
    -- POP in X1 (R0 boundary)
    x1_ctrl <= c_pop; x1_wa1 <= "000"; d_ra1 <= "000";
    wait for 1 ns;
    check_sl(stall, '1', "POP-use d1 (R0)", errs);
    -- RET in X1 is a load but not a GPR write
    x1_ctrl <= c_ret(false);
    wait for 1 ns;
    check_sl(stall, '0', "RET is not a GPR load", errs);
    -- non-load ALU producer in X1 is forwarded, no stall
    x1_ctrl <= c_use('1', '1');
    wait for 1 ns;
    check_sl(stall, '0', "ALU producer -> forward, no stall", errs);
    -- distance 2: load in X2, consumer in D -> forwarded from M later
    x1_ctrl <= CTRL_NOP; x2_ctrl <= c_ldd; d_ra1 <= "000";
    wait for 1 ns;
    check_sl(stall, '0', "load-use d2 -> no stall", errs);
    -- stall suppressed by mispredict
    x2_ctrl <= CTRL_NOP; x1_ctrl <= c_ldd; x1_wa1 <= "101";
    d_ctrl <= c_use('1', '0'); d_ra1 <= "101"; mispredict <= '1';
    wait for 1 ns;
    check_sl(stall, '0', "mispredict kills stall", errs);
    check_sl(dx1_flush, '1', "mispredict flushes D/X1", errs);
    check_sl(x1x2_flush, '1', "mispredict flushes X1/X2", errs);
    check_sl(ifd_flush, '1', "mispredict flushes IF/D", errs);
    check_sl(pc_en, '1', "mispredict loads PC", errs);
    idle;

    ---------------------------------------------------------------- redirect
    d_redirect_req <= '1';
    wait for 1 ns;
    check_sl(d_redirect, '1', "D redirect", errs);
    check_sl(ifd_flush, '1', "redirect squashes fetch", errs);
    check_sl(pc_en, '1', "redirect loads PC", errs);
    mispredict <= '1';
    wait for 1 ns;
    check_sl(d_redirect, '0', "mispredict beats D redirect", errs);
    idle;

    ---------------------------------------------------------------- RET/RTI hold
    for s in 0 to 4 loop
      for k in 0 to 1 loop
        idle;
        case s is
          when 0      => d_ctrl  <= c_ret(k = 1);
          when 1      => x1_ctrl <= c_ret(k = 1);
          when 2      => x2_ctrl <= c_ret(k = 1);
          when 3      => m_ctrl  <= c_ret(k = 1);
          when others => w_ctrl  <= c_ret(k = 1);
        end case;
        wait for 1 ns;
        check_sl(fetch_hold, '1', "hold stage " & integer'image(s), errs);
        check_sl(ifd_flush, '1', "hold squashes stage " & integer'image(s), errs);
        if s = 4 then
          check_sl(w_load, '1', "W loads PC", errs);
          check_sl(pc_en, '1', "pc_en on W load", errs);
        else
          check_sl(w_load, '0', "no W load stage " & integer'image(s), errs);
          check_sl(pc_en, '0', "PC held stage " & integer'image(s), errs);
        end if;
      end loop;
    end loop;
    idle;

    ---------------------------------------------------------------- HLT
    d_ctrl <= c_hlt; mispredict <= '1';
    wait for 1 ns;
    check_sl(halt_stop, '0', "flushed HLT ignored", errs);
    tick;
    check_sl(halted, '0', "flushed HLT does not halt", errs);
    mispredict <= '0';
    wait for 1 ns;
    check_sl(halt_stop, '1', "HLT stops fetch", errs);
    check_sl(pc_en, '0', "HLT holds PC", errs);
    check_sl(ifd_flush, '1', "HLT squashes fetch", errs);
    tick;
    d_ctrl <= CTRL_NOP;
    wait for 1 ns;
    check_sl(halted, '1', "halted", errs);
    check_sl(halt_stop, '1', "still stopped", errs);
    check_sl(pc_en, '0', "PC frozen", errs);
    tick; tick;
    check_sl(halted, '1', "stays halted", errs);

    ---------------------------------------------------------------- boot / reset
    reset <= '1'; tick; reset <= '0';
    check_sl(halted, '0', "reset clears halted", errs);
    boot_busy <= '1';
    wait for 1 ns;
    check_sl(pc_en, '0', "RST: PC held", errs);
    check_sl(ifd_flush, '1', "boot squashes fetch", errs);
    boot_load <= '1';
    wait for 1 ns;
    check_sl(pc_en, '1', "BOOT: PC loads M[0]", errs);
    idle;

    finish_tb("tb_hazard_unit", errs);
    wait;
  end process;
end architecture sim;
