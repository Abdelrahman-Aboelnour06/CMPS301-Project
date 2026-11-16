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

  -- ---------------------------------------------------------------- fetch
  signal pc_q, pc_p1, pc_next : word_t;
  signal pc_src               : std_logic_vector(2 downto 0);
  signal pc_en                : std_logic;
  signal ram_addr_a           : maddr_t;
  signal ram_en_a             : std_logic;
  signal q_a                  : word_t;
  signal instr                : word_t;
  signal vec_fetch_r          : std_logic := '0';

  -- ---------------------------------------------------------------- IF/D
  signal ifd_valid, ifd_is_vec : std_logic;
  signal ifd_pc, ifd_pc1       : word_t;

  -- ---------------------------------------------------------------- D
  signal opcode            : opcode_t;
  signal f_rdst, f_rs1, f_rs2 : raddr_t;
  signal d_real            : std_logic;
  signal d_vec_word        : std_logic;
  signal d_inject          : std_logic;
  signal ctrl_raw, ctrl_d  : ctrl_t;
  signal d_ra1, d_ra2      : raddr_t;
  signal rf_rd1, rf_rd2    : word_t;
  signal d_imm             : word_t;
  signal d_imm_z           : word_t;
  signal d_link            : word_t;
  signal d_vec_int         : word_t;
  signal d_target          : word_t;
  signal d_redirect_req    : std_logic;
  signal regs              : reg_array_t;

  -- ---------------------------------------------------------------- X1
  signal x1_ctrl                 : ctrl_t;
  signal x1_a, x1_b, x1_imm      : word_t;
  signal x1_link                 : word_t;
  signal x1_ra1, x1_ra2          : raddr_t;
  signal x1_wa1, x1_wa2          : raddr_t;
  signal fa, fb, alu_b, alu_y    : word_t;
  signal fsel_a, fsel_b          : std_logic_vector(1 downto 0);
  signal alu_z, alu_n, alu_c     : std_logic;
  signal alu_cv                  : std_logic;
  signal x1_res1                 : word_t;
  signal ccr_zn_we, ccr_c_we     : std_logic;

  -- ---------------------------------------------------------------- X2
  signal x2_ctrl                   : ctrl_t;
  signal x2_res1, x2_res2          : word_t;
  signal x2_a, x2_b, x2_imm        : word_t;
  signal x2_link                   : word_t;
  signal x2_wa1, x2_wa2            : raddr_t;
  signal x2_base, x2_ea            : word_t;
  signal sp_val, sp_addr           : word_t;
  signal x2_maddr                  : word_t;
  signal x2_sdata                  : word_t;
  signal taken, mispredict         : std_logic;
  signal ccr_save                  : std_logic;

  -- ---------------------------------------------------------------- M
  signal m_ctrl           : ctrl_t;
  signal m_res1, m_res2   : word_t;
  signal m_wa1, m_wa2     : raddr_t;
  signal q_b              : word_t;
  signal m_final          : word_t;

  -- ---------------------------------------------------------------- W
  signal w_ctrl           : ctrl_t;
  signal w_res1, w_res2   : word_t;
  signal w_wa1, w_wa2     : raddr_t;
  signal out_r            : word_t := (others => '0');
  signal ccr_restore      : std_logic;

  -- ---------------------------------------------------------------- misc
  signal ccr_val, shadow_val : std_logic_vector(3 downto 0);
  signal stall, d_redirect   : std_logic;
  signal fetch_hold, w_load  : std_logic;
  signal halt_stop, halted_i : std_logic;
  signal ifd_flush           : std_logic;
  signal dx1_flush           : std_logic;
  signal x1x2_flush          : std_logic;
  signal boot_busy           : std_logic;
  signal boot_load           : std_logic;
  signal boot_state          : std_logic_vector(1 downto 0);
  signal intr_calm           : std_logic;
  signal intr_pending        : std_logic;
  signal in_isr              : std_logic;
  signal vec_fetch_next      : std_logic;

begin

  -- =========================================================== reset / boot
  u_reset_fsm : entity work.reset_fsm
    port map (
      clk       => clk,
      reset     => reset,
      boot_busy => boot_busy,
      boot_load => boot_load,
      state_out => boot_state);

  -- =========================================================== F stage
  u_pc_mux : entity work.pc_mux
    port map (
      pc_plus1    => pc_p1,
      boot_target => q_a,
      w_target    => w_res1,
      x2_target   => x2_link,
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

  -- the word fetched in the next cycle is an INT / IRQ vector
  vec_fetch_next <= d_redirect and (ctrl_d.is_int or ctrl_d.is_hw);

  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        vec_fetch_r <= '0';
      else
        vec_fetch_r <= vec_fetch_next;
      end if;
    end if;
  end process;

  u_if_d : entity work.if_d
    port map (
      clk        => clk,
      reset      => reset,
      en         => ram_en_a,         -- = not stall
      flush      => ifd_flush,
      valid_in   => '1',
      is_vec_in  => vec_fetch_r,
      pc_in      => pc_q,
      pc1_in     => pc_p1,
      valid_out  => ifd_valid,
      is_vec_out => ifd_is_vec,
      pc_out     => ifd_pc,
      pc1_out    => ifd_pc1);

  -- =========================================================== D stage
  opcode <= instr(31 downto 26);
  f_rdst <= instr(25 downto 23);
  f_rs1  <= instr(22 downto 20);
  f_rs2  <= instr(19 downto 17);

  d_real     <= ifd_valid and not ifd_is_vec;
  d_vec_word <= ifd_valid and ifd_is_vec;

  u_control : entity work.control
    port map (
      opcode   => opcode,
      valid    => d_real,
      inject   => d_inject,
      ctrl_raw => ctrl_raw,
      ctrl     => ctrl_d);

  d_ra1 <= f_rdst when ctrl_d.ra1_dst  = '1' else f_rs1;
  d_ra2 <= f_rs1  when ctrl_d.ra2_src1 = '1' else f_rs2;

  d_imm     <= sext16(instr(15 downto 0));
  d_imm_z   <= zext16(instr(15 downto 0));
  d_vec_int <= x"0000000" & "001" & instr(16);           -- 2 + index
  d_link    <= ifd_pc when ctrl_d.is_hw = '1' else ifd_pc1;

  d_target <= instr       when d_vec_word     = '1' else
              x"00000001" when ctrl_d.is_hw   = '1' else
              d_vec_int   when ctrl_d.is_int  = '1' else
              d_imm_z;

  d_redirect_req <= d_vec_word or ctrl_d.is_jmp or ctrl_d.is_call or
                    ctrl_d.is_jcc or ctrl_d.is_int or ctrl_d.is_hw;

  u_regfile : entity work.regfile
    port map (
      clk      => clk,
      reset    => reset,
      ra1      => d_ra1,
      ra2      => d_ra2,
      rd1      => rf_rd1,
      rd2      => rf_rd2,
      wa1      => w_wa1,
      wd1      => w_res1,
      we1      => w_ctrl.we1,
      wa2      => w_wa2,
      wd2      => w_res2,
      we2      => w_ctrl.we2,
      swap     => w_ctrl.swap,
      regs_out => regs);

  u_intr_fsm : entity work.intr_fsm
    port map (
      clk          => clk,
      reset        => reset,
      intr_in      => intr_in,
      d_real       => d_real,
      d_ctrl_raw   => ctrl_raw,
      x1_ctrl      => x1_ctrl,
      x2_ctrl      => x2_ctrl,
      m_ctrl       => m_ctrl,
      w_ctrl       => w_ctrl,
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
      x1_ctrl        => x1_ctrl,
      x1_wa1         => x1_wa1,
      x2_ctrl        => x2_ctrl,
      m_ctrl         => m_ctrl,
      w_ctrl         => w_ctrl,
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

  u_d_x1 : entity work.d_x1
    port map (
      clk      => clk,
      reset    => reset,
      en       => '1',
      flush    => dx1_flush,
      ctrl_in  => ctrl_d,
      a_in     => rf_rd1,
      b_in     => rf_rd2,
      ra1_in   => d_ra1,
      ra2_in   => d_ra2,
      wa1_in   => f_rdst,
      wa2_in   => f_rs1,
      imm_in   => d_imm,
      link_in  => d_link,
      ctrl_out => x1_ctrl,
      a_out    => x1_a,
      b_out    => x1_b,
      ra1_out  => x1_ra1,
      ra2_out  => x1_ra2,
      wa1_out  => x1_wa1,
      wa2_out  => x1_wa2,
      imm_out  => x1_imm,
      link_out => x1_link);

  -- =========================================================== X1 stage
  u_forward : entity work.forward_unit
    port map (
      ra1      => x1_ra1,
      ra2      => x1_ra2,
      use_a    => x1_ctrl.use_a,
      use_b    => x1_ctrl.use_b,
      rf_a     => x1_a,
      rf_b     => x1_b,
      x2_we1   => x2_ctrl.we1,
      x2_we2   => x2_ctrl.we2,
      x2_swap  => x2_ctrl.swap,
      x2_wa1   => x2_wa1,
      x2_wa2   => x2_wa2,
      x2_res1  => x2_res1,
      x2_res2  => x2_res2,
      m_we1    => m_ctrl.we1,
      m_we2    => m_ctrl.we2,
      m_swap   => m_ctrl.swap,
      m_wa1    => m_wa1,
      m_wa2    => m_wa2,
      m_mem_rd => m_ctrl.mem_rd,
      m_res1   => m_res1,
      m_res2   => m_res2,
      m_q      => q_b,
      w_we1    => w_ctrl.we1,
      w_we2    => w_ctrl.we2,
      w_swap   => w_ctrl.swap,
      w_wa1    => w_wa1,
      w_wa2    => w_wa2,
      w_res1   => w_res1,
      w_res2   => w_res2,
      fa       => fa,
      fb       => fb,
      sel_a    => fsel_a,
      sel_b    => fsel_b);

  alu_b <= x1_imm when x1_ctrl.b_imm = '1' else fb;

  u_alu : entity work.alu
    port map (
      a     => fa,
      b     => alu_b,
      shamt => x1_imm(4 downto 0),
      op    => x1_ctrl.alu_op,
      y     => alu_y,
      z     => alu_z,
      n     => alu_n,
      c     => alu_c,
      cv    => alu_cv);

  x1_res1 <= in_port when x1_ctrl.in_sel = '1' else alu_y;

  -- CCR write gated by the X2 flush (the X1 instruction is being killed)
  ccr_zn_we   <= x1_ctrl.zn_we and not mispredict;
  ccr_c_we    <= x1_ctrl.c_we and alu_cv and not mispredict;
  ccr_save    <= x2_ctrl.is_int or x2_ctrl.is_hw;
  ccr_restore <= w_ctrl.is_rti;

  u_ccr : entity work.ccr
    port map (
      clk        => clk,
      reset      => reset,
      z_in       => alu_z,
      n_in       => alu_n,
      c_in       => alu_c,
      zn_we      => ccr_zn_we,
      c_we       => ccr_c_we,
      save       => ccr_save,
      restore    => ccr_restore,
      ccr_out    => ccr_val,
      shadow_out => shadow_val);

  u_x1_x2 : entity work.x1_x2
    port map (
      clk      => clk,
      reset    => reset,
      en       => '1',
      flush    => x1x2_flush,
      ctrl_in  => x1_ctrl,
      res1_in  => x1_res1,
      res2_in  => fb,
      a_in     => fa,
      b_in     => fb,
      imm_in   => x1_imm,
      wa1_in   => x1_wa1,
      wa2_in   => x1_wa2,
      link_in  => x1_link,
      ctrl_out => x2_ctrl,
      res1_out => x2_res1,
      res2_out => x2_res2,
      a_out    => x2_a,
      b_out    => x2_b,
      imm_out  => x2_imm,
      wa1_out  => x2_wa1,
      wa2_out  => x2_wa2,
      link_out => x2_link);

  -- =========================================================== X2 stage
  x2_base <= x2_b when x2_ctrl.base_b = '1' else x2_a;

  u_addr_adder : entity work.addr_adder
    port map (
      base   => x2_base,
      offset => x2_imm,
      ea     => x2_ea);

  u_sp : entity work.sp_unit
    port map (
      clk   => clk,
      reset => reset,
      dec   => x2_ctrl.sp_dec,
      inc   => x2_ctrl.sp_inc,
      sp    => sp_val,
      addr  => sp_addr);

  x2_maddr <= sp_addr when x2_ctrl.addr_sp = '1' else x2_ea;
  x2_sdata <= x2_link when x2_ctrl.st_link = '1' else x2_a;

  u_branch : entity work.branch_check
    port map (
      is_jcc     => x2_ctrl.is_jcc,
      cond       => x2_ctrl.cond,
      ccr        => ccr_val,
      taken      => taken,
      mispredict => mispredict);

  u_mem : entity work.data_mem
    generic map (
      INIT => PROG)
    port map (
      clk    => clk,
      addr_a => ram_addr_a,
      en_a   => ram_en_a,
      q_a    => q_a,
      addr_b => x2_maddr(MEMINDEX-1 downto 0),
      we_b   => x2_ctrl.mem_wr,
      din_b  => x2_sdata,
      q_b    => q_b);

  u_x2_m : entity work.x2_m
    port map (
      clk      => clk,
      reset    => reset,
      en       => '1',
      flush    => '0',
      ctrl_in  => x2_ctrl,
      res1_in  => x2_res1,
      res2_in  => x2_res2,
      wa1_in   => x2_wa1,
      wa2_in   => x2_wa2,
      ctrl_out => m_ctrl,
      res1_out => m_res1,
      res2_out => m_res2,
      wa1_out  => m_wa1,
      wa2_out  => m_wa2);

  -- =========================================================== M stage
  m_final <= q_b when m_ctrl.mem_rd = '1' else m_res1;

  u_m_w : entity work.m_w
    port map (
      clk      => clk,
      reset    => reset,
      en       => '1',
      flush    => '0',
      ctrl_in  => m_ctrl,
      res1_in  => m_final,
      res2_in  => m_res2,
      wa1_in   => m_wa1,
      wa2_in   => m_wa2,
      ctrl_out => w_ctrl,
      res1_out => w_res1,
      res2_out => w_res2,
      wa1_out  => w_wa1,
      wa2_out  => w_wa2);

  -- =========================================================== W stage
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        out_r <= (others => '0');
      elsif w_ctrl.out_we = '1' then
        out_r <= w_res1;
      end if;
    end if;
  end process;

  -- =========================================================== outputs
  out_port <= out_r;
  R_values <= regs;
  pc_out   <= pc_q;
  sp_out   <= sp_val;
  ccr_out  <= ccr_val;
  halted   <= halted_i;

end architecture rtl;
