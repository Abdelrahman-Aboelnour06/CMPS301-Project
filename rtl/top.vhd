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
  signal current_pc           : word_t := WORD_ZERO;
  signal pc_plus_1          : word_t := WORD_ZERO;
  signal next_pc        : word_t := WORD_ZERO;
  signal pc_select         : std_logic_vector(2 downto 0) := "000";
  signal pc_write_enable          : std_logic := '0';
  signal fetch_ram_addr     : maddr_t := (others => '0');
  signal fetch_ram_enable       : std_logic := '1';
  signal fetch_ram_data            : word_t := WORD_ZERO;
  signal instruction_word          : word_t := WORD_ZERO;
  signal vec_fetch_next : std_logic := '0';
  signal vec_fetch_r    : std_logic := '0';

  -- ------------------------------------------------------------ IF/D Bus
  signal ifd_in         : if_d_t := IF_D_NOP;
  signal if_d_reg            : if_d_t := IF_D_NOP;

  -- ------------------------------------------------------------ Decode (D)
  signal opcode         : opcode_t := (others => '0');
  signal f_rdst         : raddr_t := "000";
  signal f_rs1          : raddr_t := "000";
  signal f_rs2          : raddr_t := "000";
  signal decode_is_real_instr         : std_logic := '0';
  signal decode_is_vector_word     : std_logic := '0';
  signal decode_inject_irq       : std_logic := '0';
  signal ctrl_raw       : ctrl_t := CTRL_NOP;
  signal ctrl_d         : ctrl_t := CTRL_NOP;
  signal decode_read_addr_1          : raddr_t := "000";
  signal decode_read_addr_2          : raddr_t := "000";
  signal decode_write_addr_1         : raddr_t := "000";
  signal rename_map                  : rename_map_t := RENAME_MAP_RESET;
  signal regfile_read_data_1         : word_t := WORD_ZERO;
  signal regfile_read_data_2         : word_t := WORD_ZERO;
  signal decode_immediate          : imm16_t := IMM16_ZERO;
  signal decode_immediate_unsigned        : std_logic := '0';
  signal decode_jump_target_imm        : word_t := WORD_ZERO;
  signal decode_link_address         : word_t := WORD_ZERO;
  signal decode_sw_int_vector_addr      : word_t := WORD_ZERO;
  signal decode_branch_target       : word_t := WORD_ZERO;
  signal decode_redirect_request : std_logic := '0';
  signal regs           : reg_array_t := (others => WORD_ZERO);

  -- ------------------------------------------------------------ D/X1 Bus
  signal dx1_in         : d_x1_t := D_X1_NOP;
  signal d_x1_reg            : d_x1_t := D_X1_NOP;

  -- ------------------------------------------------------------ Execute-1 (X1)
  signal forwarded_operand_a, forwarded_operand_b         : word_t := WORD_ZERO;
  signal forward_select_a, forward_select_b : std_logic_vector(1 downto 0) := "00";
  signal x1_imm_ext     : word_t := WORD_ZERO;
  signal alu_b, alu_y   : word_t := WORD_ZERO;
  signal alu_z          : std_logic := '0';
  signal alu_n          : std_logic := '0';
  signal alu_c          : std_logic := '0';
  signal alu_cv         : std_logic := '0';
  signal execute1_result_1        : word_t := WORD_ZERO;
  signal ccr_zn_we      : std_logic := '0';
  signal ccr_c_we       : std_logic := '0';
  signal ccr_save       : std_logic := '0';
  signal ccr_restore    : std_logic := '0';
  signal ccr_clr        : std_logic_vector(2 downto 0) := "000";
  signal ccr_val        : std_logic_vector(3 downto 0) := "0000";
  signal shadow_val     : std_logic_vector(3 downto 0) := "0000";

  -- ------------------------------------------------------------ X1/X2 Bus
  signal x1x2_in        : x1_x2_t := X1_X2_NOP;
  signal x1_x2_reg           : x1_x2_t := X1_X2_NOP;

  -- ------------------------------------------------------------ Execute-2 (X2)
  signal execute2_base_addr        : word_t := WORD_ZERO;
  signal execute2_effective_addr          : word_t := WORD_ZERO;
  signal stack_pointer_value         : word_t := SP_RESET;
  signal stack_pointer_mem_addr        : word_t := SP_RESET;
  signal execute2_mem_addr       : word_t := WORD_ZERO;
  signal execute2_store_data       : word_t := WORD_ZERO;
  signal execute2_mem_write      : std_logic := '0';
  signal taken          : std_logic := '0';
  signal mispredict     : std_logic := '0';

  -- ------------------------------------------------------------ X2/M Bus
  signal x2m_in         : x2_m_t := X2_M_NOP;
  signal x2_m_reg            : x2_m_t := X2_M_NOP;

  -- ------------------------------------------------------------ Memory (M)
  signal mem_ram_data            : word_t := WORD_ZERO;
  signal memory_stage_result        : word_t := WORD_ZERO;

  -- ------------------------------------------------------------ M/W Bus
  signal mw_in          : m_w_t := M_W_NOP;
  signal m_w_reg             : m_w_t := M_W_NOP;

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
      pc_plus1    => pc_plus_1,
      boot_target => fetch_ram_data,
      w_target    => m_w_reg.result_1,
      x2_target   => x1_x2_reg.link_address,
      d_target    => decode_branch_target,
      sel_boot    => boot_load,
      sel_w       => w_load,
      sel_x2      => mispredict,
      sel_d       => d_redirect,
      pc_next     => next_pc,
      src         => pc_select);

  u_pc : entity work.pc
    port map (
      clk      => clk,
      reset    => reset,
      en       => pc_write_enable,
      pc_next  => next_pc,
      pc_q     => current_pc,
      pc_plus1 => pc_plus_1);

  u_instr_mem : entity work.instr_mem
    port map (
      pc       => current_pc,
      hold     => stall,
      ram_addr => fetch_ram_addr,
      ram_en   => fetch_ram_enable,
      ram_q    => fetch_ram_data,
      instr    => instruction_word);

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
    is_valid              => '1',
    is_interrupt_vector   => vec_fetch_r,
    program_counter       => current_pc,
    next_program_counter  => pc_plus_1);

  u_if_d : entity work.if_d
    port map (
      clk   => clk,
      reset => reset,
      en    => fetch_ram_enable,              -- = not stall
      flush => ifd_flush,
      d_in  => ifd_in,
      d_out => if_d_reg);

  -- =========================================================================
  -- 2. DECODE STAGE (D) & D/X1 PIPELINE REGISTER
  -- =========================================================================
  opcode <= instruction_word(31 downto 26);
  f_rdst <= instruction_word(25 downto 23);
  f_rs1  <= instruction_word(22 downto 20);
  f_rs2  <= instruction_word(19 downto 17);

  decode_is_real_instr     <= if_d_reg.is_valid and not if_d_reg.is_interrupt_vector;
  decode_is_vector_word <= if_d_reg.is_valid and if_d_reg.is_interrupt_vector;

  u_control : entity work.control
    port map (
      opcode   => opcode,
      valid    => decode_is_real_instr,
      inject   => decode_inject_irq,
      ctrl_raw => ctrl_raw,
      ctrl     => ctrl_d);
  PROC_RENAME : process (clk)
    variable idx_dst, idx_src : integer range 0 to 7;
    variable tmp              : raddr_t;
  begin
    if rising_edge(clk) then
      if reset = '1' then
        rename_map <= RENAME_MAP_RESET;
      elsif decode_is_real_instr = '1' and opcode = OP_SWAP
            and decode_inject_irq = '0' and stall = '0' and dx1_flush = '0' then
        idx_dst := to_integer(unsigned(f_rdst));
        idx_src := to_integer(unsigned(f_rs1));
        tmp     := rename_map(idx_dst);
        rename_map(idx_dst) <= rename_map(idx_src);
        rename_map(idx_src) <= tmp;
      end if;
    end if;
  end process;

  decode_read_addr_1  <= rename_map(to_integer(unsigned(f_rdst))) when ctrl_d.read_port_1_uses_rdst  = '1'
                    else rename_map(to_integer(unsigned(f_rs1)));
  decode_read_addr_2  <= rename_map(to_integer(unsigned(f_rs1)))  when ctrl_d.read_port_2_uses_rsrc1 = '1'
                    else rename_map(to_integer(unsigned(f_rs2)));
  decode_write_addr_1 <= rename_map(to_integer(unsigned(f_rdst)));

  decode_immediate     <= instruction_word(15 downto 0);
  decode_immediate_unsigned   <= '1' when opcode = OP_LDM else '0';
  decode_jump_target_imm   <= zext16(instruction_word(15 downto 0));
  decode_sw_int_vector_addr <= x"0000000" & "001" & instruction_word(16);             -- 2 + index
  decode_link_address    <= if_d_reg.program_counter when ctrl_d.is_hardware_interrupt = '1' else if_d_reg.next_program_counter;

  decode_branch_target <= instruction_word       when decode_is_vector_word                   = '1' else
              x"00000001" when ctrl_d.is_hardware_interrupt = '1' else
              decode_sw_int_vector_addr   when ctrl_d.is_software_interrupt = '1' else
              decode_jump_target_imm;

  decode_redirect_request <= decode_is_vector_word or ctrl_d.is_jump or ctrl_d.is_call or
                    ctrl_d.is_conditional_jump or ctrl_d.is_software_interrupt or
                    ctrl_d.is_hardware_interrupt;

  u_regfile : entity work.regfile
    port map (
      clk      => clk,
      reset    => reset,
      ra1      => decode_read_addr_1,
      ra2      => decode_read_addr_2,
      rd1      => regfile_read_data_1,
      rd2      => regfile_read_data_2,
      wa1      => m_w_reg.write_addr_1,
      wd1      => m_w_reg.result_1,
      we1      => m_w_reg.control.write_port_1_enable,
      regs_out => regs);

  u_intr_fsm : entity work.intr_fsm
    port map (
      clk          => clk,
      reset        => reset,
      intr_in      => intr_in,
      d_real       => decode_is_real_instr,
      d_ctrl_raw   => ctrl_raw,
      x1_ctrl      => d_x1_reg.control,
      x2_ctrl      => x1_x2_reg.control,
      m_ctrl       => x2_m_reg.control,
      w_ctrl       => m_w_reg.control,
      mispredict   => mispredict,
      boot_busy    => boot_busy,
      inject       => decode_inject_irq,
      calm         => intr_calm,
      intr_pending => intr_pending,
      in_isr       => in_isr);

  u_hazard : entity work.hazard_unit
    port map (
      clk            => clk,
      reset          => reset,
      d_ctrl         => ctrl_d,
      d_ra1          => decode_read_addr_1,
      d_ra2          => decode_read_addr_2,
      d_redirect_req => decode_redirect_request,
      x1_ctrl        => d_x1_reg.control,
      x1_wa1         => d_x1_reg.write_addr_1,
      x2_ctrl        => x1_x2_reg.control,
      m_ctrl         => x2_m_reg.control,
      w_ctrl         => m_w_reg.control,
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
      pc_en          => pc_write_enable);

  dx1_in <= (
    control               => ctrl_d,
    operand_a             => regfile_read_data_1,
    operand_b             => regfile_read_data_2,
    read_addr_1           => decode_read_addr_1,
    read_addr_2           => decode_read_addr_2,
    write_addr_1          => decode_write_addr_1,
    immediate             => decode_immediate,
    immediate_unsigned    => decode_immediate_unsigned,
    link_address          => decode_link_address);

  u_d_x1 : entity work.d_x1
    port map (
      clk   => clk,
      reset => reset,
      en    => '1',
      flush => dx1_flush,
      d_in  => dx1_in,
      d_out => d_x1_reg);

  -- =========================================================================
  -- 3. EXECUTE-1 STAGE (X1) & X1/X2 PIPELINE REGISTER
  -- =========================================================================
  u_forward : entity work.forward_unit
    port map (
      ra1      => d_x1_reg.read_addr_1,
      ra2      => d_x1_reg.read_addr_2,
      use_a    => d_x1_reg.control.reads_operand_a,
      use_b    => d_x1_reg.control.reads_operand_b,
      rf_a     => d_x1_reg.operand_a,
      rf_b     => d_x1_reg.operand_b,
      x2_we1   => x1_x2_reg.control.write_port_1_enable,
      x2_wa1   => x1_x2_reg.write_addr_1,
      x2_res1  => x1_x2_reg.result_1,
      m_we1    => x2_m_reg.control.write_port_1_enable,
      m_wa1    => x2_m_reg.write_addr_1,
      m_mem_rd => x2_m_reg.control.memory_read,
      m_res1   => x2_m_reg.result_1,
      m_q      => mem_ram_data,
      w_we1    => m_w_reg.control.write_port_1_enable,
      w_wa1    => m_w_reg.write_addr_1,
      w_res1   => m_w_reg.result_1,
      fa       => forwarded_operand_a,
      fb       => forwarded_operand_b,
      sel_a    => forward_select_a,
      sel_b    => forward_select_b);

  x1_imm_ext <= zext16(d_x1_reg.immediate) when d_x1_reg.immediate_unsigned = '1' else sext16(d_x1_reg.immediate);
  alu_b <= x1_imm_ext when d_x1_reg.control.alu_b_uses_immediate = '1' else forwarded_operand_b;

  u_alu : entity work.alu
    port map (
      a     => forwarded_operand_a,
      b     => alu_b,
      shamt => d_x1_reg.immediate(4 downto 0),
      op    => d_x1_reg.control.alu_operation,
      y     => alu_y,
      z     => alu_z,
      n     => alu_n,
      c     => alu_c,
      cv    => alu_cv);

  execute1_result_1 <= in_port when d_x1_reg.control.result_from_in_port = '1' else alu_y;

  ccr_zn_we   <= d_x1_reg.control.update_zero_negative_flags and not mispredict;
  ccr_c_we    <= d_x1_reg.control.update_carry_flag and alu_cv and not mispredict;
  ccr_save    <= x1_x2_reg.control.is_software_interrupt or x1_x2_reg.control.is_hardware_interrupt;
  ccr_restore <= m_w_reg.control.is_return_from_interrupt;

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
    control               => d_x1_reg.control,
    result_1              => execute1_result_1,
    operand_b             => forwarded_operand_b,
    immediate             => d_x1_reg.immediate,
    write_addr_1          => d_x1_reg.write_addr_1,
    link_address          => d_x1_reg.link_address);

  u_x1_x2 : entity work.x1_x2
    port map (
      clk   => clk,
      reset => reset,
      en    => '1',
      flush => x1x2_flush,
      d_in  => x1x2_in,
      d_out => x1_x2_reg);

  -- =========================================================================
  -- 4. EXECUTE-2 STAGE (X2) & X2/M PIPELINE REGISTER
  -- =========================================================================
  execute2_base_addr <= x1_x2_reg.operand_b when x1_x2_reg.control.base_address_is_operand_b = '1' else x1_x2_reg.result_1;

  u_addr_adder : entity work.addr_adder
    port map (
      base   => execute2_base_addr,
      offset => sext16(x1_x2_reg.immediate),
      ea     => execute2_effective_addr);

  u_sp : entity work.sp_unit
    port map (
      clk   => clk,
      reset => reset,
      dec   => x1_x2_reg.control.stack_pointer_decrement,
      inc   => x1_x2_reg.control.stack_pointer_increment,
      sp    => stack_pointer_value,
      addr  => stack_pointer_mem_addr);

  execute2_mem_addr <= stack_pointer_mem_addr   when x1_x2_reg.control.memory_address_from_sp = '1' else execute2_effective_addr;
  execute2_store_data <= x1_x2_reg.link_address when x1_x2_reg.control.store_link_address = '1'     else x1_x2_reg.result_1;
  execute2_mem_write  <= x1_x2_reg.control.memory_write and not reset;

  u_branch : entity work.branch_check
    port map (
      is_jcc     => x1_x2_reg.control.is_conditional_jump,
      cond       => x1_x2_reg.control.jump_condition,
      ccr        => ccr_val,
      taken      => taken,
      mispredict => mispredict,
      clr_mask   => ccr_clr);

  u_mem : entity work.data_mem
    generic map (
      INIT => PROG)
    port map (
      clk    => clk,
      addr_a => fetch_ram_addr,
      en_a   => fetch_ram_enable,
      q_a    => fetch_ram_data,
      addr_b => execute2_mem_addr(MEMINDEX-1 downto 0),
      we_b   => execute2_mem_write,
      din_b  => execute2_store_data,
      q_b    => mem_ram_data);

  x2m_in <= (
    control               => x1_x2_reg.control,
    result_1              => x1_x2_reg.result_1,
    write_addr_1          => x1_x2_reg.write_addr_1);

  u_x2_m : entity work.x2_m
    port map (
      clk   => clk,
      reset => reset,
      en    => '1',
      flush => '0',
      d_in  => x2m_in,
      d_out => x2_m_reg);

  -- =========================================================================
  -- 5. MEMORY STAGE (M) & M/W PIPELINE REGISTER
  -- =========================================================================
  memory_stage_result <= mem_ram_data when x2_m_reg.control.memory_read = '1' else x2_m_reg.result_1;

  mw_in <= (
    control               => x2_m_reg.control,
    result_1              => memory_stage_result,
    write_addr_1          => x2_m_reg.write_addr_1);

  u_m_w : entity work.m_w
    port map (
      clk   => clk,
      reset => reset,
      en    => '1',
      flush => '0',
      d_in  => mw_in,
      d_out => m_w_reg);

  -- =========================================================================
  -- 6. WRITE-BACK STAGE (W) & ARCHITECTURAL OUTPUTS
  -- =========================================================================
  PROC_OUT_PORT : process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        out_r <= WORD_ZERO;
      elsif m_w_reg.control.write_out_port = '1' then
        out_r <= m_w_reg.result_1;
      end if;
    end if;
  end process;

  out_port <= out_r;
  R_values <= regs;
  pc_out   <= current_pc;
  sp_out   <= stack_pointer_value;
  ccr_out  <= ccr_val;
  halted   <= halted_i;

end architecture rtl;
