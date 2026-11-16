-------------------------------------------------------------------------------
-- hazard_unit.vhd -- pipeline control: load-use stall, flush generation,
-- fetch-hold for RET/RTI, HLT, and the next-PC enable.
--
--   stall      : D instruction reads a register that the load (LDD/POP)
--                in X1 will write. One bubble; afterwards the value is
--                forwarded from M (RAM q_b). Suppressed by a mispredict.
--   d_redirect : JMP / CALL / Jcc (predict taken) / INT / IRQ micro-op /
--                vector word in D redirects the PC (unless X2 flushes).
--   fetch_hold : RET or RTI anywhere in D, X1, X2, M, W -> no new fetch
--                until W loads the PC.
--   halt_stop  : HLT reached D (not flushed) or the core is halted.
--                Fetch stops forever; older instructions drain. No clock
--                gating.
--   ifd_flush  : squash the word being fetched this cycle.
--   dx1_flush  : bubble into D/X1 (stall or mispredict).
--   x1x2_flush : bubble into X1/X2 (mispredict kills the X1 instruction).
--   pc_en      : PC register enable.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use work.cpu_pkg.all;

entity hazard_unit is
  port (
    clk            : in  std_logic;
    reset          : in  std_logic;
    -- D stage (post-injection decode)
    d_ctrl         : in  ctrl_t;
    d_ra1          : in  raddr_t;
    d_ra2          : in  raddr_t;
    d_redirect_req : in  std_logic;
    -- X1 stage
    x1_ctrl        : in  ctrl_t;
    x1_wa1         : in  raddr_t;
    -- later stages
    x2_ctrl        : in  ctrl_t;
    m_ctrl         : in  ctrl_t;
    w_ctrl         : in  ctrl_t;
    -- X2 branch resolution
    mispredict     : in  std_logic;
    -- reset FSM
    boot_busy      : in  std_logic;
    boot_load      : in  std_logic;
    -- outputs
    stall          : out std_logic;
    d_redirect     : out std_logic;
    fetch_hold     : out std_logic;
    w_load         : out std_logic;
    halt_stop      : out std_logic;
    halted         : out std_logic;
    ifd_flush      : out std_logic;
    dx1_flush      : out std_logic;
    x1x2_flush     : out std_logic;
    pc_en          : out std_logic
  );
end entity hazard_unit;

architecture rtl of hazard_unit is
  signal halted_r   : std_logic := '0';
  signal stall_i    : std_logic;
  signal redir_i    : std_logic;
  signal hold_i     : std_logic;
  signal wload_i    : std_logic;
  signal halt_now   : std_logic;
  signal hstop_i    : std_logic;
  signal x1_load    : std_logic;
  signal use_hit    : std_logic;
begin

  -- load-use: X1 holds a load that writes a GPR (POP / LDD; swap = '0')
  x1_load <= x1_ctrl.mem_rd and x1_ctrl.we1;
  use_hit <= '1' when ((d_ctrl.use_a = '1' and d_ra1 = x1_wa1) or
                       (d_ctrl.use_b = '1' and d_ra2 = x1_wa1)) else '0';
  stall_i <= x1_load and use_hit and not mispredict;

  redir_i <= d_redirect_req and not mispredict;

  hold_i <= d_ctrl.is_ret  or d_ctrl.is_rti  or
            x1_ctrl.is_ret or x1_ctrl.is_rti or
            x2_ctrl.is_ret or x2_ctrl.is_rti or
            m_ctrl.is_ret  or m_ctrl.is_rti  or
            w_ctrl.is_ret  or w_ctrl.is_rti;

  wload_i  <= w_ctrl.is_ret or w_ctrl.is_rti;
  halt_now <= d_ctrl.is_hlt and not mispredict;
  hstop_i  <= halted_r or halt_now;

  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        halted_r <= '0';
      elsif halt_now = '1' then
        halted_r <= '1';
      end if;
    end if;
  end process;

  stall      <= stall_i;
  d_redirect <= redir_i;
  fetch_hold <= hold_i;
  w_load     <= wload_i;
  halt_stop  <= hstop_i;
  halted     <= halted_r;

  ifd_flush  <= boot_busy or mispredict or redir_i or hold_i or hstop_i;
  dx1_flush  <= stall_i or mispredict;
  x1x2_flush <= mispredict;

  pc_en <= boot_load or wload_i or mispredict or redir_i or
           not (stall_i or hold_i or hstop_i or boot_busy);
end architecture rtl;
