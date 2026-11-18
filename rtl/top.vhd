-------------------------------------------------------------------------------
-- top.vhd -- CMPS 301 six-stage pipelined processor, top-level integrator.
--
--   F  : PC drives RAM Port A; registered RAM output = D-stage instruction.
--   D  : decode, register read, JMP/CALL/INT/vector redirect, Jcc predicted
--        taken, IRQ micro-op injection.
--   X1 : forwarding muxes, ALU + barrel shifter, CCR update, IN.PORT sample.
--   X2 : LDD/STD address adder, SP read/update, Jcc resolution, flush.
--   M  : RAM Port B access (inputs registered at the X2->M edge).
--   W  : register-file write, OUT.PORT write, PC load for RET/RTI.
--
-- Generic PROG gives the initial memory image in simulation.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;

entity top is
  generic (
    PROG : mem_t := MEM_ZERO
  );
  port (
    clk      : in  std_logic;
    reset    : in  std_logic;
    intr_in  : in  std_logic;
    in_port  : in  std_logic_vector(31 downto 0);
    out_port : out std_logic_vector(31 downto 0);
    R_values : out reg_array_t;
    pc_out   : out std_logic_vector(31 downto 0);
    sp_out   : out std_logic_vector(31 downto 0);
    ccr_out  : out std_logic_vector(3 downto 0);
    halted   : out std_logic
  );
end entity top;

architecture rtl of top is

  -- ------------------------------------------------------------ Reset / Boot
  signal boot_busy      : std_logic := '1';
  signal boot_load      : std_logic := '0';
  signal boot_state     : std_logic_vector(1 downto 0) := "00";

  -- ------------------------------------------------------------ Fetch (F)
  signal pc_q           : word_t := WORD_ZERO;
  signal pc_p1          : word_t := WORD_ZERO;
  signal pc_next        : word_t := WORD_ZERO;
  signal pc_src         : std_logic_vector(2 downto 0) := "000";
  signal pc_en          : std_logic := '0';
  signal ram_addr_a     : maddr_t := (others => '0');
  signal ram_en_a       : std_logic := '1';
  signal q_a            : word_t := WORD_ZERO;
  signal instr          : word_t := WORD_ZERO;
  signal vec_fetch_next : std_logic := '0';
  signal vec_fetch_r    : std_logic := '0';

  -- ------------------------------------------------------------ IF/D Bus
  signal ifd_in         : if_d_t := IF_D_NOP;
  signal ifd            : if_d_t := IF_D_NOP;

  -- ------------------------------------------------------------ Decode (D)
  signal opcode         : opcode_t := (others => '0');
  signal f_rdst         : raddr_t := "000";
  signal f_rs1          : raddr_t := "000";
  signal f_rs2          : raddr_t := "000";
  signal d_real         : std_logic := '0';
  signal d_vec_word     : std_logic := '0';
  signal d_inject       : std_logic := '0';
  signal ctrl_raw       : ctrl_t := CTRL_NOP;
  signal ctrl_d         : ctrl_t := CTRL_NOP;
  signal d_ra1          : raddr_t := "000";
  signal d_ra2          : raddr_t := "000";
  signal rf_rd1         : word_t := WORD_ZERO;
  signal rf_rd2         : word_t := WORD_ZERO;
  signal d_imm          : word_t := WORD_ZERO;
  signal d_imm_z        : word_t := WORD_ZERO;
  signal d_link         : word_t := WORD_ZERO;
  signal d_vec_int      : word_t := WORD_ZERO;
  signal d_target       : word_t := WORD_ZERO;
  signal d_redirect_req : std_logic := '0';
  signal regs           : reg_array_t := (others => WORD_ZERO);

  -- ------------------------------------------------------------ D/X1 Bus
  signal dx1_in         : d_x1_t := D_X1_NOP;
  signal dx1            : d_x1_t := D_X1_NOP;

  -- ------------------------------------------------------------ Execute-1 (X1)
  signal fa, fb         : word_t := WORD_ZERO;
  signal fsel_a, fsel_b : std_logic_vector(1 downto 0) := "00";
  signal alu_b, alu_y   : word_t := WORD_ZERO;
  signal alu_z          : std_logic := '0';
  signal alu_n          : std_logic := '0';
  signal alu_c          : std_logic := '0';
  signal alu_cv         : std_logic := '0';
  signal x1_res1        : word_t := WORD_ZERO;
  signal ccr_zn_we      : std_logic := '0';
  signal ccr_c_we       : std_logic := '0';
  signal ccr_save       : std_logic := '0';
  signal ccr_restore    : std_logic := '0';
  signal ccr_clr        : std_logic_vector(2 downto 0) := "000";
  signal ccr_val        : std_logic_vector(3 downto 0) := "0000";
  signal shadow_val     : std_logic_vector(3 downto 0) := "0000";

  -- ------------------------------------------------------------ X1/X2 Bus
  signal x1x2_in        : x1_x2_t := X1_X2_NOP;
  signal x1x2           : x1_x2_t := X1_X2_NOP;

  -- ------------------------------------------------------------ Execute-2 (X2)
  signal x2_base        : word_t := WORD_ZERO;
  signal x2_ea          : word_t := WORD_ZERO;
  signal sp_val         : word_t := SP_RESET;
  signal sp_addr        : word_t := SP_RESET;
  signal x2_maddr       : word_t := WORD_ZERO;
  signal x2_sdata       : word_t := WORD_ZERO;
  signal taken          : std_logic := '0';
  signal mispredict     : std_logic := '0';

  -- ------------------------------------------------------------ X2/M Bus
  signal x2m_in         : x2_m_t := X2_M_NOP;
  signal x2m            : x2_m_t := X2_M_NOP;

  -- ------------------------------------------------------------ Memory (M)
  signal q_b            : word_t := WORD_ZERO;
  signal m_final        : word_t := WORD_ZERO;

  -- ------------------------------------------------------------ M/W Bus
  signal mw_in          : m_w_t := M_W_NOP;
  signal mw             : m_w_t := M_W_NOP;

  -- ------------------------------------------------------------ Write-Back (W)
  signal out_r          : word_t := WORD_ZERO;

  -- ------------------------------------------------------------ Hazard & Interrupts
  signal stall          : std_logic := '0';
  signal d_redirect     : std_logic := '0';
  signal fetch_hold     : std_logic := '0';
  signal w_load         : std_logic := '0';
  signal halt_stop      : std_logic := '0';
  signal halted_i       : std_logic := '0';
  signal ifd_flush      : std_logic := '0';
  signal dx1_flush      : std_logic := '0';
  signal x1x2_flush     : std_logic := '0';
  signal intr_calm      : std_logic := '0';
  signal intr_pending   : std_logic := '0';
  signal in_isr         : std_logic := '0';

begin

  -- =========================================================================
  -- 0. RESET / BOOT SEQUENCER
  -- =========================================================================
  u_reset_fsm : entity work.reset_fsm
    port map (
      clk       => clk,
      reset     => reset,
      boot_busy => boot_busy,
      boot_load => boot_load,
      state_out => boot_state);

  -- =========================================================================
  -- 1. FETCH STAGE (F) & IF/D PIPELINE REGISTER
  -- =========================================================================
  u_pc_mux : entity work.pc_mux
    port map (
      pc_plus1    => pc_p1,
      boot_target => q_a,
      w_target    => mw.res1,
      x2_target   => x1x2.link,
      d_target    => d_target,
      sel_boot    => boot_load,
      sel_w       => w_load,
      sel_x2      => mispredict,
      sel_d       => d_redirect,
      pc_next     => pc_next,
      src         => pc_src);

  u_pc : entity work.pc
    port map (
      clk      => clk,
      reset    => reset,
      en       => pc_en,
      pc_next  => pc_next,
      pc_q     => pc_q,
      pc_plus1 => pc_p1);

  u_instr_mem : entity work.instr_mem
    port map (
      pc       => pc_q,
      hold     => stall,
      ram_addr => ram_addr_a,
      ram_en   => ram_en_a,
      ram_q    => q_a,
      instr    => instr);

  -- Track whether the word being fetched next cycle is an INT/IRQ vector
  vec_fetch_next <= d_redirect and (ctrl_d.is_software_interrupt or ctrl_d.is_hardware_interrupt);

  PROC_VEC_FETCH : process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        vec_fetch_r <= '0';
      else
        vec_fetch_r <= vec_fetch_next;
      end if;
    end if;
  end process;

  ifd_in <= (
    valid  => '1',
    is_vec => vec_fetch_r,
    pc     => pc_q,
    pc1    => pc_p1);

  u_if_d : entity work.if_d
    port map (
      clk   => clk,
      reset => reset,
      en    => ram_en_a,              -- = not stall
      flush => ifd_flush,
      d_in  => ifd_in,
      d_out => ifd);

  -- =========================================================================
  -- 2. DECODE STAGE (D) & D/X1 PIPELINE REGISTER
  -- =========================================================================
  opcode <= instr(31 downto 26);
  f_rdst <= instr(25 downto 23);
  f_rs1  <= instr(22 downto 20);
  f_rs2  <= instr(19 downto 17);

  d_real     <= ifd.valid and not ifd.is_vec;
  d_vec_word <= ifd.valid and ifd.is_vec;

  u_control : entity work.control
    port map (
      opcode   => opcode,
      valid    => d_real,
      inject   => d_inject,
      ctrl_raw => ctrl_raw,
      ctrl     => ctrl_d);

  d_ra1 <= f_rdst when ctrl_d.read_port_1_uses_rdst  = '1' else f_rs1;
  d_ra2 <= f_rs1  when ctrl_d.read_port_2_uses_rsrc1 = '1' else f_rs2;

  d_imm     <= zext16(instr(15 downto 0)) when opcode = OP_LDM else sext16(instr(15 downto 0));
  d_imm_z   <= zext16(instr(15 downto 0));
  d_vec_int <= x"0000000" & "001" & instr(16);             -- 2 + index
  d_link    <= ifd.pc when ctrl_d.is_hardware_interrupt = '1' else ifd.pc1;

  d_target <= instr       when d_vec_word                   = '1' else
              x"00000001" when ctrl_d.is_hardware_interrupt = '1' else
              d_vec_int   when ctrl_d.is_software_interrupt = '1' else
              d_imm_z;

  d_redirect_req <= d_vec_word or ctrl_d.is_jump or ctrl_d.is_call or
                    ctrl_d.is_conditional_jump or ctrl_d.is_software_interrupt or
                    ctrl_d.is_hardware_interrupt;

  u_regfile : entity work.regfile
    port map (
      clk      => clk,
      reset    => reset,
      ra1      => d_ra1,
      ra2      => d_ra2,
      rd1      => rf_rd1,
      rd2      => rf_rd2,
      wa1      => mw.wa1,
      wd1      => mw.res1,
      we1      => mw.ctrl.write_port_1_enable,
      wa2      => mw.wa2,
      wd2      => mw.res2,
      we2      => mw.ctrl.write_port_2_enable,
      swap     => mw.ctrl.swap_write_addresses,
      regs_out => regs);

  u_intr_fsm : entity work.intr_fsm
    port map (
      clk          => clk,
      reset        => reset,
      intr_in      => intr_in,
      d_real       => d_real,
      d_ctrl_raw   => ctrl_raw,
      x1_ctrl      => dx1.ctrl,
      x2_ctrl      => x1x2.ctrl,
      m_ctrl       => x2m.ctrl,
      w_ctrl       => mw.ctrl,
      mispredict   => mispredict,
      boot_busy    => boot_busy,
      inject       => d_inject,
      calm         => intr_calm,
      intr_pending => intr_pending,
      in_isr       => in_isr);

  u_hazard : entity work.hazard_unit
    port map (
      clk            => clk,
      reset          => reset,
      d_ctrl         => ctrl_d,
      d_ra1          => d_ra1,
      d_ra2          => d_ra2,
      d_redirect_req => d_redirect_req,
      x1_ctrl        => dx1.ctrl,
      x1_wa1         => dx1.wa1,
      x2_ctrl        => x1x2.ctrl,
      m_ctrl         => x2m.ctrl,
      w_ctrl         => mw.ctrl,
      mispredict     => mispredict,
      boot_busy      => boot_busy,
      boot_load      => boot_load,
      stall          => stall,
      d_redirect     => d_redirect,
      fetch_hold     => fetch_hold,
      w_load         => w_load,
      halt_stop      => halt_stop,
      halted         => halted_i,
      ifd_flush      => ifd_flush,
      dx1_flush      => dx1_flush,
      x1x2_flush     => x1x2_flush,
      pc_en          => pc_en);

  dx1_in <= (
    ctrl => ctrl_d,
    a    => rf_rd1,
    b    => rf_rd2,
    ra1  => d_ra1,
    ra2  => d_ra2,
    wa1  => f_rdst,
    wa2  => f_rs1,
    imm  => d_imm,
    link => d_link);

  u_d_x1 : entity work.d_x1
    port map (
      clk   => clk,
      reset => reset,
      en    => '1',
      flush => dx1_flush,
      d_in  => dx1_in,
      d_out => dx1);

  -- =========================================================================
  -- 3. EXECUTE-1 STAGE (X1) & X1/X2 PIPELINE REGISTER
  -- =========================================================================
  u_forward : entity work.forward_unit
    port map (
      ra1      => dx1.ra1,
      ra2      => dx1.ra2,
      use_a    => dx1.ctrl.reads_operand_a,
      use_b    => dx1.ctrl.reads_operand_b,
      rf_a     => dx1.a,
      rf_b     => dx1.b,
      x2_we1   => x1x2.ctrl.write_port_1_enable,
      x2_we2   => x1x2.ctrl.write_port_2_enable,
      x2_swap  => x1x2.ctrl.swap_write_addresses,
      x2_wa1   => x1x2.wa1,
      x2_wa2   => x1x2.wa2,
      x2_res1  => x1x2.res1,
      x2_res2  => x1x2.res2,
      m_we1    => x2m.ctrl.write_port_1_enable,
      m_we2    => x2m.ctrl.write_port_2_enable,
      m_swap   => x2m.ctrl.swap_write_addresses,
      m_wa1    => x2m.wa1,
      m_wa2    => x2m.wa2,
      m_mem_rd => x2m.ctrl.memory_read,
      m_res1   => x2m.res1,
      m_res2   => x2m.res2,
      m_q      => q_b,
      w_we1    => mw.ctrl.write_port_1_enable,
      w_we2    => mw.ctrl.write_port_2_enable,
      w_swap   => mw.ctrl.swap_write_addresses,
      w_wa1    => mw.wa1,
      w_wa2    => mw.wa2,
      w_res1   => mw.res1,
      w_res2   => mw.res2,
      fa       => fa,
      fb       => fb,
      sel_a    => fsel_a,
      sel_b    => fsel_b);

  alu_b <= dx1.imm when dx1.ctrl.alu_b_uses_immediate = '1' else fb;

  u_alu : entity work.alu
    port map (
      a     => fa,
      b     => alu_b,
      shamt => dx1.imm(4 downto 0),
      op    => dx1.ctrl.alu_operation,
      y     => alu_y,
      z     => alu_z,
      n     => alu_n,
      c     => alu_c,
      cv    => alu_cv);

  x1_res1 <= in_port when dx1.ctrl.result_from_in_port = '1' else alu_y;

  ccr_zn_we   <= dx1.ctrl.update_zero_negative_flags and not mispredict;
  ccr_c_we    <= dx1.ctrl.update_carry_flag and alu_cv and not mispredict;
  ccr_save    <= x1x2.ctrl.is_software_interrupt or x1x2.ctrl.is_hardware_interrupt;
  ccr_restore <= mw.ctrl.is_return_from_interrupt;

  u_ccr : entity work.ccr
    port map (
      clk        => clk,
      reset      => reset,
      z_in       => alu_z,
      n_in       => alu_n,
      c_in       => alu_c,
      zn_we      => ccr_zn_we,
      c_we       => ccr_c_we,
      clr_mask   => ccr_clr,
      save       => ccr_save,
      restore    => ccr_restore,
      ccr_out    => ccr_val,
      shadow_out => shadow_val);

  x1x2_in <= (
    ctrl => dx1.ctrl,
    res1 => x1_res1,
    res2 => fb,
    a    => fa,
    b    => fb,
    imm  => dx1.imm,
    wa1  => dx1.wa1,
    wa2  => dx1.wa2,
    link => dx1.link);

  u_x1_x2 : entity work.x1_x2
    port map (
      clk   => clk,
      reset => reset,
      en    => '1',
      flush => x1x2_flush,
      d_in  => x1x2_in,
      d_out => x1x2);

  -- =========================================================================
  -- 4. EXECUTE-2 STAGE (X2) & X2/M PIPELINE REGISTER
  -- =========================================================================
  x2_base <= x1x2.b when x1x2.ctrl.base_address_is_operand_b = '1' else x1x2.a;

  u_addr_adder : entity work.addr_adder
    port map (
      base   => x2_base,
      offset => x1x2.imm,
      ea     => x2_ea);

  u_sp : entity work.sp_unit
    port map (
      clk   => clk,
      reset => reset,
      dec   => x1x2.ctrl.stack_pointer_decrement,
      inc   => x1x2.ctrl.stack_pointer_increment,
      sp    => sp_val,
      addr  => sp_addr);

  x2_maddr <= sp_addr   when x1x2.ctrl.memory_address_from_sp = '1' else x2_ea;
  x2_sdata <= x1x2.link when x1x2.ctrl.store_link_address = '1'     else x1x2.a;

  u_branch : entity work.branch_check
    port map (
      is_jcc     => x1x2.ctrl.is_conditional_jump,
      cond       => x1x2.ctrl.jump_condition,
      ccr        => ccr_val,
      taken      => taken,
      mispredict => mispredict,
      clr_mask   => ccr_clr);

  u_mem : entity work.data_mem
    generic map (
      INIT => PROG)
    port map (
      clk    => clk,
      addr_a => ram_addr_a,
      en_a   => ram_en_a,
      q_a    => q_a,
      addr_b => x2_maddr(MEMINDEX-1 downto 0),
      we_b   => x1x2.ctrl.memory_write,
      din_b  => x2_sdata,
      q_b    => q_b);

  x2m_in <= (
    ctrl => x1x2.ctrl,
    res1 => x1x2.res1,
    res2 => x1x2.res2,
    wa1  => x1x2.wa1,
    wa2  => x1x2.wa2);

  u_x2_m : entity work.x2_m
    port map (
      clk   => clk,
      reset => reset,
      en    => '1',
      flush => '0',
      d_in  => x2m_in,
      d_out => x2m);

  -- =========================================================================
  -- 5. MEMORY STAGE (M) & M/W PIPELINE REGISTER
  -- =========================================================================
  m_final <= q_b when x2m.ctrl.memory_read = '1' else x2m.res1;

  mw_in <= (
    ctrl => x2m.ctrl,
    res1 => m_final,
    res2 => x2m.res2,
    wa1  => x2m.wa1,
    wa2  => x2m.wa2);

  u_m_w : entity work.m_w
    port map (
      clk   => clk,
      reset => reset,
      en    => '1',
      flush => '0',
      d_in  => mw_in,
      d_out => mw);

  -- =========================================================================
  -- 6. WRITE-BACK STAGE (W) & ARCHITECTURAL OUTPUTS
  -- =========================================================================
  PROC_OUT_PORT : process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        out_r <= WORD_ZERO;
      elsif mw.ctrl.write_out_port = '1' then
        out_r <= mw.res1;
      end if;
    end if;
  end process;

  out_port <= out_r;
  R_values <= regs;
  pc_out   <= pc_q;
  sp_out   <= sp_val;
  ccr_out  <= ccr_val;
  halted   <= halted_i;

end architecture rtl;
