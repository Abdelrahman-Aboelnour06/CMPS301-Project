-------------------------------------------------------------------------------
-- tb_hazards.vhd -- integration test of the hazard machinery (no external
-- files). Independent cores run these programs in parallel:
--   loaduse : load-use at distance 1 (LDD->ADD, POP->INC, LDD->STD data)
--             and distance 2 (LDD, NOP, ADD); store/load forwarding
--   branch  : JZ loop with 2 mispredicts + 1 correct prediction, JC/JN
--             taken, three mispredicted Jcc in a row, SETC + JC
--   callint : CALL/RET, INT 0 / INT 1 with CCR shadow restore, SWAP
--             forwarding, SWAP Rx,Rx, SHL/SHR, IN/OUT, NOT
--   irq     : two INTR.IN pulses during a JZ/JMP loop: injection gating
--             (Jcc in flight), ISR with PUSH/POP/flags, RTI CCR restore
--   drain   : IRQ handler sees every already-fetched INC before RTI
--   irqmiss : IRQ during a mispredicted JZ resumes at the fall-through PC
-- Final registers, SP, CCR, OUT.PORT and PC are compared with values
-- obtained from the ISA semantics.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.cpu_pkg.all;
use work.tb_pkg.all;

entity tb_hazards is
end entity tb_hazards;

architecture sim of tb_hazards is
  function prog_loaduse return mem_t is
    variable m : mem_t := MEM_ZERO;
  begin
    m(0) := x"00000008";  -- vector
    m(8) := enc(OP_LDM, rd => 1, imm => 100);  -- 0x008: LDM R1, 100
    m(9) := enc(OP_LDM, rd => 2, imm => 85);  -- 0x009: LDM R2, 85
    m(10) := enc(OP_STD, rs1 => 2, rs2 => 1);  -- 0x00a: STD R2, 0(R1)
    m(11) := enc(OP_LDD, rd => 3, rs1 => 1);  -- 0x00b: LDD R3, 0(R1)
    m(12) := enc(OP_ADD, rd => 4, rs1 => 3, rs2 => 3);  -- 0x00c: ADD R4, R3, R3
    m(13) := enc(OP_LDD, rd => 5, rs1 => 1);  -- 0x00d: LDD R5, 0(R1)
    m(15) := enc(OP_ADD, rd => 6, rs1 => 5, rs2 => 2);  -- 0x00f: ADD R6, R5, R2
    m(16) := enc(OP_PUSH, rs1 => 4);  -- 0x010: PUSH R4
    m(17) := enc(OP_POP, rd => 7);  -- 0x011: POP R7
    m(18) := enc(OP_INC, rd => 7);  -- 0x012: INC R7
    m(19) := enc(OP_STD, rd => 7, rs1 => 7, rs2 => 1, imm => -1);  -- 0x013: STD R7, -1(R1)
    m(20) := enc(OP_LDD, rs1 => 1, imm => -1);  -- 0x014: LDD R0, -1(R1)
    m(21) := enc(OP_STD, rs2 => 1, imm => 1);  -- 0x015: STD R0, 1(R1)
    m(22) := enc(OP_LDD, rd => 2, rs1 => 1, imm => 1);  -- 0x016: LDD R2, 1(R1)
    m(23) := enc(OP_LDD, rd => 3, rs1 => 1, imm => 3995);  -- 100 + 3995 = 0xFFF
    m(24) := enc(OP_HLT);
    return m;
  end function;
  function prog_branch return mem_t is
    variable m : mem_t := MEM_ZERO;
  begin
    m(0) := x"00000008";  -- vector
    m(8) := enc(OP_LDM, rd => 1, imm => 3);  -- 0x008: LDM R1, 3
    m(9) := enc(OP_LDM);  -- 0x009: LDM R0, 0
    m(10) := enc(OP_INC);  -- 0x00a: INC R0
    m(11) := enc(OP_IADD, rd => 1, rs1 => 1, imm => -1);  -- 0x00b: IADD R1, R1, -1
    m(12) := enc(OP_JZ, imm => 14);  -- 0x00c: JZ 0xE
    m(13) := enc(OP_JMP, imm => 10);  -- 0x00d: JMP 0xA
    m(14) := enc(OP_LDM, rd => 2, imm => 1);  -- 0x00e: LDM R2, 1
    m(15) := enc(OP_LDM, rd => 3, imm => 2);  -- 0x00f: LDM R3, 2
    m(16) := enc(OP_CMP, rs1 => 2, rs2 => 3);  -- 0x010: CMP R2, R3
    m(17) := enc(OP_JC, imm => 19);  -- 0x011: JC 0x13
    m(18) := enc(OP_LDM, rd => 4, imm => 119);  -- 0x012: LDM R4, 119
    m(19) := enc(OP_JN, imm => 21);  -- 0x013: JN 0x15
    m(20) := enc(OP_LDM, rd => 5, imm => 102);  -- 0x014: LDM R5, 102
    m(21) := enc(OP_CMP, rs1 => 3, rs2 => 2);  -- 0x015: CMP R3, R2
    m(22) := enc(OP_JC, imm => 64);  -- 0x016: JC 0x40
    m(23) := enc(OP_JN, imm => 64);  -- 0x017: JN 0x40
    m(24) := enc(OP_JZ, imm => 64);  -- 0x018: JZ 0x40
    m(25) := enc(OP_LDM, rd => 6, imm => 291);  -- 0x019: LDM R6, 291
    m(26) := enc(OP_SETC);  -- 0x01a: SETC
    m(27) := enc(OP_JC, imm => 29);  -- 0x01b: JC 0x1D
    m(28) := enc(OP_HLT);  -- 0x01c: HLT
    m(29) := enc(OP_HLT);  -- 0x01d: HLT
    m(64) := enc(OP_LDM, rd => 7, imm => 2989);  -- 0x040: LDM R7, 2989
    m(65) := enc(OP_HLT);  -- 0x041: HLT
    return m;
  end function;
  function prog_callint return mem_t is
    variable m : mem_t := MEM_ZERO;
  begin
    m(0) := x"00000008";  -- vector
    m(2) := x"00000030";  -- vector
    m(3) := x"00000038";  -- vector
    m(8) := enc(OP_LDM, rd => 1, imm => -2);  -- 0x008: LDM R1, -2
    m(9) := enc(OP_CALL, imm => 32);  -- 0x009: CALL 0x20
    m(10) := enc(OP_INC, rd => 1);  -- 0x00a: INC R1
    m(11) := enc(OP_SETC);  -- 0x00b: SETC
    m(12) := enc(OP_INT);  -- 0x00c: INT 0
    m(13) := enc(OP_INT, idx => 1);  -- 0x00d: INT 1
    m(14) := enc(OP_SWAP, rd => 3, rs1 => 3);  -- 0x00e: SWAP R3, R3
    m(15) := enc(OP_MOV, rd => 4, rs1 => 3);  -- 0x00f: MOV R4, R3
    m(16) := enc(OP_SWAP, rd => 4, rs1 => 1);  -- 0x010: SWAP R4, R1
    m(17) := enc(OP_ADD, rd => 5, rs1 => 4, rs2 => 1);  -- 0x011: ADD R5, R4, R1
    m(18) := enc(OP_SHL, rd => 6, imm => 4);  -- 0x012: SHL R6, 4
    m(19) := enc(OP_SHR, rd => 6, imm => 1);  -- 0x013: SHR R6, 1
    m(20) := enc(OP_IN, rd => 7);  -- 0x014: IN R7
    m(21) := enc(OP_OUT, rs1 => 7);  -- 0x015: OUT R7
    m(22) := enc(OP_NOT, rd => 7);  -- 0x016: NOT R7
    m(23) := enc(OP_HLT);  -- 0x017: HLT
    m(32) := enc(OP_INC, rd => 1);  -- 0x020: INC R1
    m(33) := enc(OP_INC, rd => 1);  -- 0x021: INC R1
    m(34) := enc(OP_LDM, rd => 6, imm => 3841);  -- 0x022: LDM R6, 3841
    m(35) := enc(OP_RET);  -- 0x023: RET
    m(48) := enc(OP_LDM, rd => 2, imm => 4369);  -- 0x030: LDM R2, 4369
    m(49) := enc(OP_CMP, rs1 => 2, rs2 => 2);  -- 0x031: CMP R2, R2
    m(50) := enc(OP_RTI);  -- 0x032: RTI
    m(56) := enc(OP_LDM, rd => 3, imm => 8738);  -- 0x038: LDM R3, 8738
    m(57) := enc(OP_IADD, rd => 3, rs1 => 3, imm => 1);  -- 0x039: IADD R3, R3, 1
    m(58) := enc(OP_RTI);  -- 0x03a: RTI
    return m;
  end function;
  function prog_irq return mem_t is
    variable m : mem_t := MEM_ZERO;
  begin
    m(0) := x"00000008";  -- vector
    m(1) := x"00000050";  -- vector
    m(8) := enc(OP_LDM);  -- 0x008: LDM R0, 0
    m(9) := enc(OP_LDM, rd => 1, imm => 20);  -- 0x009: LDM R1, 20
    m(10) := enc(OP_IADD, imm => 2);  -- 0x00a: IADD R0, R0, 2
    m(11) := enc(OP_IADD, rd => 1, rs1 => 1, imm => -1);  -- 0x00b: IADD R1, R1, -1
    m(12) := enc(OP_JZ, imm => 14);  -- 0x00c: JZ 0xE
    m(13) := enc(OP_JMP, imm => 10);  -- 0x00d: JMP 0xA
    m(14) := enc(OP_OUT);  -- 0x00e: OUT R0
    m(15) := enc(OP_HLT);  -- 0x00f: HLT
    m(80) := enc(OP_PUSH, rs1 => 2);  -- 0x050: PUSH R2
    m(81) := enc(OP_INC, rd => 7);  -- 0x051: INC R7
    m(82) := enc(OP_SETC);  -- 0x052: SETC
    m(83) := enc(OP_LDM, rd => 2, imm => -1);  -- 0x053: LDM R2, -1
    m(84) := enc(OP_CMP, rs1 => 2, rs2 => 2);  -- 0x054: CMP R2, R2
    m(85) := enc(OP_POP, rd => 2);  -- 0x055: POP R2
    m(86) := enc(OP_RTI);  -- 0x056: RTI
    return m;
  end function;

  function prog_drain(branch_miss : boolean) return mem_t is
    variable m : mem_t := MEM_ZERO;
  begin
    m(0) := x"00000010";
    m(1) := x"00000040";
    for address in 16 to 23 loop
      m(address) := enc(OP_INC);
    end loop;
    if branch_miss then
      m(22) := enc(OP_JZ, imm => 48);  -- Z is clear. Recover to address 23.
      m(48) := enc(OP_INC, rd => 2);   -- Wrong-path marker.
      m(49) := enc(OP_HLT);
    end if;
    m(24) := enc(OP_HLT);
    m(64) := enc(OP_MOV, rd => 1, rs1 => 0);  -- Snapshot R0 at IRQ entry.
    m(65) := enc(OP_LDD, rd => 3, rs1 => 7, imm => 4095);  -- Read saved PC at M[0xFFF].
    m(66) := enc(OP_RTI);
    return m;
  end function;

  constant NCORE : natural := 6;
  type mem_arr_t   is array (0 to NCORE-1) of mem_t;
  type word_arr_t  is array (0 to NCORE-1) of word_t;
  type regs_arr_t  is array (0 to NCORE-1) of reg_array_t;
  type ccr_arr_t   is array (0 to NCORE-1) of std_logic_vector(3 downto 0);
  type name_arr_t  is array (0 to NCORE-1) of string(1 to 7);

  constant PROGS : mem_arr_t := (prog_loaduse, prog_branch, prog_callint, prog_irq, prog_drain(false), prog_drain(true));
  constant NAMES : name_arr_t := ("loaduse", "branch ", "callint", "irq    ", "drain  ", "irqmiss");
  constant INPUT : word_arr_t := (x"00000000", x"00000000", x"1234ABCD", x"00000000", x"00000000", x"00000000");

  constant EXP_R : regs_arr_t := (
    (x"000000AB", x"00000064", x"000000AB", x"000000AA",
     x"000000AA", x"00000055", x"000000AA", x"000000AB"),
    (x"00000003", x"00000000", x"00000001", x"00000002",
     x"00000000", x"00000000", x"00000123", x"00000000"),
    (x"00000000", x"00002223", x"00001111", x"00002223",
     x"00010001", x"00012224", x"00007808", x"EDCB5432"),
    (x"00000028", x"00000000", x"00000000", x"00000000",
     x"00000000", x"00000000", x"00000000", x"00000002"),
    (0 => x"00000008", 1 => x"00000007", 3 => x"00000017", others => x"00000000"),
    (0 => x"00000007", 1 => x"00000006", 3 => x"00000017", others => x"00000000"));
  constant EXP_CCR : ccr_arr_t  := ("0000", "0000", "0010", "0100", "0000", "0000");
  constant EXP_OUT : word_arr_t := (x"00000000", x"00000000", x"1234ABCD", x"00000028", x"00000000", x"00000000");
  constant EXP_PC  : word_arr_t := (x"00000019", x"0000001E", x"00000018", x"00000010", x"00000019", x"00000019");

  signal clk      : std_logic := '0';
  signal reset    : std_logic := '1';
  signal intr     : std_logic_vector(0 to NCORE-1) := (others => '0');
  signal out_port : word_arr_t;
  type rmap_arr_t  is array (0 to NCORE-1) of rename_map_t;
  signal regs     : regs_arr_t;
  signal rmaps    : rmap_arr_t;
  signal pc_out   : word_arr_t;
  signal sp_out   : word_arr_t;
  signal ccr_out  : ccr_arr_t;
  signal halted   : std_logic_vector(0 to NCORE-1);
  signal cycle    : natural := 0;      -- rising edges since reset release
begin
  clk <= not clk after 5 ns;

  cores : for k in 0 to NCORE-1 generate
    dut : entity work.top
      generic map (PROG => PROGS(k))
      port map (clk => clk, reset => reset, intr_in => intr(k),
                in_port => INPUT(k), out_port => out_port(k),
                R_values => regs(k), pc_out => pc_out(k), sp_out => sp_out(k),
                ccr_out => ccr_out(k), halted => halted(k));
    rmaps(k) <= << signal dut.rename_map : rename_map_t >>;
  end generate;

  -- cycle counter (edge index t = 0 is the first edge with reset low)
  process (clk)
  begin
    if rising_edge(clk) then
      if reset = '1' then
        cycle <= 0;
      else
        cycle <= cycle + 1;
      end if;
    end if;
  end process;

  -- INTR.IN for the "irq" core: high for edges t = 30..31 and t = 120..124
  intr(3) <= '1' when (cycle >= 30 and cycle < 32) or (cycle >= 120 and cycle < 125)
             else '0';

  -- The IRQ sampling edge fetches address 22 in both directed programs.
  intr(4 to 5) <= "11" when cycle = 8 else "00";

  stim : process
    variable errs : natural := 0;
    variable n    : natural := 0;
  begin
    for i in 1 to 3 loop
      wait until rising_edge(clk);
    end loop;
    reset <= '0';
    while halted /= (halted'range => '1') and n < 2000 loop
      wait until rising_edge(clk);
      n := n + 1;
    end loop;
    check(halted = (halted'range => '1'), "all cores halted", errs);
    for i in 1 to 8 loop
      wait until rising_edge(clk);
    end loop;
    wait for 1 ns;
    for k in 0 to NCORE-1 loop
      for r in 0 to 7 loop
        check_eq(regs(k)(to_integer(unsigned(rmaps(k)(r)))), EXP_R(k)(r), NAMES(k) & " R" & integer'image(r), errs);
      end loop;
      check_eq(sp_out(k), x"00000FFF", NAMES(k) & " SP", errs);
      check_eq(ccr_out(k), EXP_CCR(k), NAMES(k) & " CCR", errs);
      check_eq(out_port(k), EXP_OUT(k), NAMES(k) & " OUT", errs);
      check_eq(pc_out(k), EXP_PC(k), NAMES(k) & " PC", errs);
    end loop;
    finish_tb("tb_hazards", errs);
    wait;
  end process;
end architecture sim;
