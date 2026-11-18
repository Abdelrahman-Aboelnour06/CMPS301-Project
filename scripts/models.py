"""Two independent models for auditing the cmps301 RTL.

isa_run : architectural reference written from the authoritative ISA table
          (NOT from the author's spec).  Interrupts are injected at given
          dynamic-instruction boundaries.
Rtl     : cycle-level transliteration of rtl/top.vhd and its sub-modules.
          Each line mirrors the VHDL; comments cite the source.
"""
M32 = 0xFFFFFFFF
OPS = {
    'NOP': 0b000000, 'NOT': 0b000001, 'INC': 0b000010, 'OUT': 0b000100,
    'IN': 0b000101, 'SETC': 0b000110, 'HLT': 0b000111, 'MOV': 0b010000,
    'SWAP': 0b010001, 'ADD': 0b010010, 'SUB': 0b010011, 'AND': 0b010100,
    'CMP': 0b010101, 'SHR': 0b010110, 'SHL': 0b010111, 'IADD': 0b011000,
    'PUSH': 0b100000, 'POP': 0b100001, 'LDM': 0b100010, 'LDD': 0b100011,
    'STD': 0b100100, 'JMP': 0b110000, 'JZ': 0b110001, 'JN': 0b110010,
    'JC': 0b110011, 'CALL': 0b110100, 'RET': 0b110101, 'RTI': 0b110110,
    'INT': 0b110111}
NAME = {v: k for k, v in OPS.items()}


def enc(op, rd=0, rs1=0, rs2=0, imm=0, idx=0):
    return (OPS[op] << 26) | (rd << 23) | (rs1 << 20) | (rs2 << 17) | (idx << 16) | (imm & 0xFFFF)


def sext(v):
    v &= 0xFFFF
    return (v | 0xFFFF0000) if v & 0x8000 else v


def flags_zn(r):
    return (1 if r == 0 else 0), (r >> 31) & 1


# ------------------------------------------------------------------ ISA model
def isa_run(mem, in_port=0, irq_before=(), max_instr=100000):
    """irq_before: set of dynamic instruction indices k; a HW IRQ is taken
    before executing the k-th instruction (0-based)."""
    mem = list(mem)
    R = [0] * 8
    pc = mem[0]
    sp = 0xFFF
    Z = N = C = 0
    shadow = (0, 0, 0)
    out = 0
    k = 0
    irq_before = set(irq_before)
    while k < max_instr:
        if k in irq_before:
            sp = (sp - 1) & M32
            mem[sp & 0xFFF] = pc
            shadow = (Z, N, C)
            pc = mem[1]
        w = mem[pc & 0xFFF]
        op = w >> 26
        rd = (w >> 23) & 7
        r1 = (w >> 20) & 7
        r2 = (w >> 17) & 7
        idx = (w >> 16) & 1
        imm = w & 0xFFFF
        npc = (pc + 1) & M32
        n = NAME.get(op, 'NOP')
        k += 1
        if n == 'NOP':
            pass
        elif n == 'NOT':
            R[rd] = (~R[rd]) & M32
            Z, N = flags_zn(R[rd])
        elif n == 'INC':
            s = R[rd] + 1
            C = s >> 32
            R[rd] = s & M32
            Z, N = flags_zn(R[rd])
        elif n == 'OUT':
            out = R[r1]
        elif n == 'IN':
            R[rd] = in_port
        elif n == 'SETC':
            C = 1
        elif n == 'HLT':
            return dict(R=R, pc=pc, sp=sp, ccr=Z | N << 1 | C << 2, out=out, mem=mem, n=k)
        elif n == 'MOV':
            R[rd] = R[r1]
        elif n == 'SWAP':
            R[rd], R[r1] = R[r1], R[rd]
        elif n in ('ADD', 'IADD'):
            b = R[r2] if n == 'ADD' else sext(imm)
            s = R[r1] + b
            C = s >> 32
            R[rd] = s & M32
            Z, N = flags_zn(R[rd])
        elif n in ('SUB', 'CMP'):
            s = (R[r1] - R[r2])
            C = 1 if R[r1] < R[r2] else 0          # borrow convention (A)
            r = s & M32
            Z, N = flags_zn(r)
            if n == 'SUB':
                R[rd] = r
        elif n == 'AND':
            R[rd] = R[r1] & R[r2]
            Z, N = flags_zn(R[rd])
        elif n in ('SHR', 'SHL'):
            a = R[rd]
            k5 = imm & 31
            if n == 'SHR':
                r = a >> k5
                if k5:
                    C = (a >> (k5 - 1)) & 1
            else:
                r = (a << k5) & M32
                if k5:
                    C = (a >> (32 - k5)) & 1
            R[rd] = r
            Z, N = flags_zn(r)
        elif n == 'PUSH':
            sp = (sp - 1) & M32
            mem[sp & 0xFFF] = R[r1]
        elif n == 'POP':
            R[rd] = mem[sp & 0xFFF]
            sp = (sp + 1) & M32
        elif n == 'LDM':
            R[rd] = sext(imm)
        elif n == 'LDD':
            R[rd] = mem[(R[r1] + sext(imm)) & 0xFFF]
        elif n == 'STD':
            mem[(R[r2] + sext(imm)) & 0xFFF] = R[r1]
        elif n == 'JMP':
            npc = imm
        elif n in ('JZ', 'JN', 'JC'):
            if {'JZ': Z, 'JN': N, 'JC': C}[n]:
                npc = imm
        elif n == 'CALL':
            sp = (sp - 1) & M32
            mem[sp & 0xFFF] = npc
            npc = imm
        elif n in ('RET', 'RTI'):
            npc = mem[sp & 0xFFF]
            sp = (sp + 1) & M32
            if n == 'RTI':
                Z, N, C = shadow
        elif n == 'INT':
            sp = (sp - 1) & M32
            mem[sp & 0xFFF] = npc
            shadow = (Z, N, C)
            npc = mem[(2 + idx) & 0xFFF]
        pc = npc
    return None


# ------------------------------------------------------------------ RTL model
FIELDS = ['valid', 'alu_op', 'b_imm', 'use_a', 'use_b', 'ra1_dst', 'ra2_src1', 'we1', 'we2',
          'swap', 'zn_we', 'c_we', 'in_sel', 'out_we', 'mem_rd', 'mem_wr', 'addr_sp',
          'sp_dec', 'sp_inc', 'st_link', 'base_b', 'is_jmp', 'is_call', 'is_jcc', 'is_int',
          'is_hw', 'is_ret', 'is_rti', 'is_hlt', 'cond']
NOPC = {f: 0 for f in FIELDS}
NOPC['alu_op'] = 'PASSA'


def control(opcode, valid):                       # control.vhd process
    c = dict(NOPC)
    if not valid:
        return c
    c['valid'] = 1
    n = NAME.get(opcode)
    c['nm'] = n
    S = lambda **kw: c.update(kw)
    if n == 'NOT': S(alu_op='NOT', use_a=1, ra1_dst=1, we1=1, zn_we=1)
    elif n == 'INC': S(alu_op='INC', use_a=1, ra1_dst=1, we1=1, zn_we=1, c_we=1)
    elif n == 'OUT': S(alu_op='PASSA', use_a=1, out_we=1)
    elif n == 'IN': S(in_sel=1, we1=1)
    elif n == 'SETC': S(alu_op='SETC', c_we=1)
    elif n == 'HLT': S(is_hlt=1)
    elif n == 'MOV': S(alu_op='PASSA', use_a=1, we1=1)
    elif n == 'SWAP': S(alu_op='PASSA', use_a=1, use_b=1, ra1_dst=1, ra2_src1=1, we1=1, we2=1, swap=1)
    elif n == 'ADD': S(alu_op='ADD', use_a=1, use_b=1, we1=1, zn_we=1, c_we=1)
    elif n == 'SUB': S(alu_op='SUB', use_a=1, use_b=1, we1=1, zn_we=1, c_we=1)
    elif n == 'AND': S(alu_op='AND', use_a=1, use_b=1, we1=1, zn_we=1)
    elif n == 'CMP': S(alu_op='SUB', use_a=1, use_b=1, zn_we=1, c_we=1)
    elif n == 'SHR': S(alu_op='SHR', use_a=1, ra1_dst=1, we1=1, zn_we=1, c_we=1)
    elif n == 'SHL': S(alu_op='SHL', use_a=1, ra1_dst=1, we1=1, zn_we=1, c_we=1)
    elif n == 'IADD': S(alu_op='ADD', b_imm=1, use_a=1, we1=1, zn_we=1, c_we=1)
    elif n == 'PUSH': S(use_a=1, mem_wr=1, addr_sp=1, sp_dec=1)
    elif n == 'POP': S(mem_rd=1, addr_sp=1, sp_inc=1, we1=1)
    elif n == 'LDM': S(alu_op='PASSB', b_imm=1, we1=1)
    elif n == 'LDD': S(use_a=1, mem_rd=1, we1=1)
    elif n == 'STD': S(use_a=1, use_b=1, mem_wr=1, base_b=1)
    elif n == 'JMP': S(is_jmp=1)
    elif n in ('JZ', 'JN', 'JC'): S(is_jcc=1, cond=opcode & 3)
    elif n == 'CALL': S(is_call=1, mem_wr=1, addr_sp=1, sp_dec=1, st_link=1)
    elif n == 'RET': S(is_ret=1, mem_rd=1, addr_sp=1, sp_inc=1)
    elif n == 'RTI': S(is_rti=1, mem_rd=1, addr_sp=1, sp_inc=1)
    elif n == 'INT': S(is_int=1, mem_wr=1, addr_sp=1, sp_dec=1, st_link=1)
    return c


HWC = dict(NOPC, nm='HWop', valid=1, mem_wr=1, addr_sp=1, sp_dec=1, st_link=1, is_hw=1)


def alu(a, b, shamt, op):                          # alu.vhd
    r, cc, cv = a, 0, 0
    if op == 'NOT': r = (~a) & M32
    elif op == 'INC': s = a + 1; r = s & M32; cc = s >> 32; cv = 1
    elif op == 'ADD': s = a + b; r = s & M32; cc = s >> 32; cv = 1
    elif op == 'SUB':
        s = ((a - b) & 0x1FFFFFFFF); r = s & M32; cc = s >> 32; cv = 1
    elif op == 'AND': r = a & b
    elif op in ('SHL', 'SHR'):
        k = shamt
        if op == 'SHR':
            r = a >> k
            if k: cc = (a >> (k - 1)) & 1; cv = 1
        else:
            r = (a << k) & M32
            if k: cc = (a >> (32 - k)) & 1; cv = 1
    elif op == 'PASSB': r = b
    elif op == 'SETC': r = a; cc = 1; cv = 1
    return r, (1 if r == 0 else 0), (r >> 31) & 1, cc, cv


class Rtl:
    def __init__(self, mem, in_port=0, fix=()):
        self.fix = set(fix)
        self.ram = list(mem) + [0] * (4096 - len(mem))
        self.in_port = in_port
        self.t = 0
        # state, values after reset
        self.pc = 0; self.qa = 0; self.qb = 0; self.vec_r = 0
        self.ifd = dict(valid=0, is_vec=0, pc=0, pc1=0)
        Z = dict(ctrl=dict(NOPC), a=0, b=0, ra1=0, ra2=0, wa1=0, wa2=0, imm=0, link=0, res1=0, res2=0)
        self.dx1 = dict(Z); self.x1x2 = dict(Z); self.x2m = dict(Z); self.mw = dict(Z)
        self.regs = [0] * 8; self.ccr = 0; self.shadow = 0; self.sp = 0xFFF
        self.halted = 0; self.st = 'RST'; self.prev = 1; self.pending = 0; self.in_isr = 0
        self.out = 0
        self.log = []
        self.retired = 0          # real instructions reaching W (valid & not hw)
        self.inject_at = []       # retired count when hw micro-op retires
        self.ram_reads_x2 = 0

    def step(self, intr_in=0):
        f = self.fix
        ram = self.ram
        ifd, dx1, x1x2, x2m, mw = self.ifd, self.dx1, self.x1x2, self.x2m, self.mw
        x1c, x2c, mc, wc = dx1['ctrl'], x1x2['ctrl'], x2m['ctrl'], mw['ctrl']
        boot_busy = 0 if self.st == 'RUN' else 1
        boot_load = 1 if self.st == 'BOOT' else 0
        # ---- X2 branch check (uses CCR state)
        if x2c['is_jcc']:
            bit = {1: 0, 2: 1, 3: 2}.get(x2c['cond'])
            t = (self.ccr >> bit) & 1 if bit is not None else 0
        else:
            t = 1
        mispredict = 1 if (x2c['is_jcc'] and not t) else 0
        # ---- D
        instr = self.qa
        opcode = instr >> 26
        f_rdst, f_rs1, f_rs2 = (instr >> 23) & 7, (instr >> 20) & 7, (instr >> 17) & 7
        d_real = ifd['valid'] and not ifd['is_vec']
        d_vec = ifd['valid'] and ifd['is_vec']
        raw = control(opcode, d_real)
        # intr_fsm
        jcc_busy = raw['is_jcc'] or x1c['is_jcc'] or x2c['is_jcc']
        if 'starve' in f:
            jcc_busy = 0
        ret_busy = any(c['is_ret'] or c['is_rti'] for c in (raw, x1c, x2c, mc, wc))
        calm = d_real and not jcc_busy and not ret_busy and not mispredict and not boot_busy
        inject = 1 if (self.pending and not self.in_isr and calm) else 0
        cd = dict(HWC) if inject else raw
        d_ra1 = f_rdst if cd['ra1_dst'] else f_rs1
        d_ra2 = f_rs1 if cd['ra2_src1'] else f_rs2
        d_imm = sext(instr & 0xFFFF)
        d_imm_z = instr & 0xFFFF
        d_vec_int = 2 + ((instr >> 16) & 1)
        d_link = ifd['pc'] if cd['is_hw'] else ifd['pc1']
        if d_vec: d_target = instr
        elif cd['is_hw']: d_target = 1
        elif cd['is_int']: d_target = d_vec_int
        else: d_target = d_imm_z
        d_redirect_req = d_vec or cd['is_jmp'] or cd['is_call'] or cd['is_jcc'] or cd['is_int'] or cd['is_hw']
        # regfile read with W bypass
        wea1 = mw['wa2'] if wc['swap'] else mw['wa1']
        wea2 = mw['wa1'] if wc['swap'] else mw['wa2']

        def rfread(ra):
            if wc['we2'] and wea2 == ra: return mw['res2']
            if wc['we1'] and wea1 == ra: return mw['res1']
            return self.regs[ra]
        rf1, rf2 = rfread(d_ra1), rfread(d_ra2)
        # hazard unit
        x1_load = x1c['mem_rd'] and x1c['we1']
        use_hit = (cd['use_a'] and d_ra1 == dx1['wa1']) or (cd['use_b'] and d_ra2 == dx1['wa1'])
        stall = 1 if (x1_load and use_hit and not mispredict) else 0
        redir = 1 if (d_redirect_req and not mispredict) else 0
        hold = any(c['is_ret'] or c['is_rti'] for c in (cd, x1c, x2c, mc, wc))
        wload = wc['is_ret'] or wc['is_rti']
        halt_now = cd['is_hlt'] and not mispredict
        hstop = self.halted or halt_now
        ifd_flush = boot_busy or mispredict or redir or hold or hstop
        dx1_flush = stall or mispredict
        x1x2_flush = mispredict
        pc_en = boot_load or wload or mispredict or redir or not (stall or hold or hstop or boot_busy)
        # pc mux
        if boot_load: pc_next = self.qa
        elif wload: pc_next = mw['res1']
        elif mispredict: pc_next = x1x2['link']
        elif redir: pc_next = d_target
        else: pc_next = (self.pc + 1) & M32
        vec_next = redir and (cd['is_int'] or cd['is_hw'])
        # ---- X1 forwarding
        m_res1_eff = self.qb if mc['mem_rd'] else x2m['res1']

        def lookup(r, c, st, d1, d2):
            e1, e2 = (st['wa2'], st['wa1']) if c['swap'] else (st['wa1'], st['wa2'])
            if c['we2'] and e2 == r: return 1, d2
            if c['we1'] and e1 == r: return 1, d1
            return 0, d1

        def fwd(r, use, rf):
            h, d = lookup(r, x2c, x1x2, x1x2['res1'], x1x2['res2'])
            if use and h: return d
            h, d = lookup(r, mc, x2m, m_res1_eff, x2m['res2'])
            if use and h: return d
            h, d = lookup(r, wc, mw, mw['res1'], mw['res2'])
            if use and h: return d
            return rf
        fa = fwd(dx1['ra1'], x1c['use_a'], dx1['a'])
        fb = fwd(dx1['ra2'], x1c['use_b'], dx1['b'])
        alu_b = dx1['imm'] if x1c['b_imm'] else fb
        y, az, an, ac, acv = alu(fa, alu_b, dx1['imm'] & 31, x1c['alu_op'])
        x1_res1 = self.in_port if x1c['in_sel'] else y
        zn_we = x1c['zn_we'] and not mispredict
        c_we = x1c['c_we'] and acv and not mispredict
        save = x2c['is_int'] or x2c['is_hw']
        restore = wc['is_rti']
        # ---- X2
        base = x1x2['b'] if x2c['base_b'] else x1x2['a']
        ea = (base + x1x2['imm']) & M32
        sp_m1 = (self.sp - 1) & M32
        sp_addr = sp_m1 if x2c['sp_dec'] else self.sp
        maddr = (sp_addr if x2c['addr_sp'] else ea) & 0xFFF
        sdata = x1x2['link'] if x2c['st_link'] else x1x2['a']
        addr_a = self.pc & 0xFFF
        en_a = not stall
        # =============== clock edge ===============
        we_b = x2c['mem_wr']
        if en_a:
            self.qa = sdata if (we_b and addr_a == maddr) else ram[addr_a]
        self.qb = sdata if we_b else ram[maddr]
        if we_b:
            ram[maddr] = sdata
        # trace W retire
        if wc['valid']:
            if wc['is_hw']:
                self.inject_at.append(self.retired)
            else:
                self.retired += 1
        # regfile write
        if wc['we1']: self.regs[wea1] = mw['res1']
        if wc['we2']: self.regs[wea2] = mw['res2']
        if wc['out_we']: self.out = mw['res1']
        # ccr
        if save: self.shadow = self.ccr
        if restore:
            self.ccr = self.shadow
        else:
            if zn_we: self.ccr = (self.ccr & ~3) | az | (an << 1)
            if c_we: self.ccr = (self.ccr & ~4) | (ac << 2)
        # sp
        if x2c['sp_dec']: self.sp = sp_m1
        elif x2c['sp_inc']: self.sp = (self.sp + 1) & M32
        # intr fsm
        edge = intr_in and not self.prev
        if 'irqlatch2' in f:
            if edge: self.pending = 1
            elif inject: self.pending = 0
        elif 'irqlatch' in f:
            if edge: self.pending = 1
            elif x2c['is_hw']: self.pending = 0
        else:
            if x2c['is_hw']: self.pending = 0
            elif edge and not self.in_isr: self.pending = 1
        self.prev = intr_in
        if x2c['is_hw'] or x2c['is_int']: self.in_isr = 1
        elif wc['is_rti']: self.in_isr = 0
        if halt_now: self.halted = 1
        # pipeline regs
        self.mw = dict(ctrl=mc, res1=m_res1_eff,    # m_final (q_b sampled before this edge)
                       res2=x2m['res2'], wa1=x2m['wa1'], wa2=x2m['wa2'])
        self.x2m = dict(ctrl=x2c, res1=x1x2['res1'], res2=x1x2['res2'], wa1=x1x2['wa1'], wa2=x1x2['wa2'])
        self.x1x2 = dict(ctrl=dict(NOPC) if x1x2_flush else x1c, res1=x1_res1, res2=fb, a=fa, b=fb,
                         imm=dx1['imm'], wa1=dx1['wa1'], wa2=dx1['wa2'], link=dx1['link'])
        self.dx1 = dict(ctrl=dict(NOPC) if dx1_flush else cd, a=rf1, b=rf2, ra1=d_ra1, ra2=d_ra2,
                        wa1=f_rdst, wa2=f_rs1, imm=d_imm, link=d_link)
        if ifd_flush:
            self.ifd = dict(valid=0, is_vec=0, pc=self.pc, pc1=(self.pc + 1) & M32)
        elif en_a:
            self.ifd = dict(valid=1, is_vec=self.vec_r, pc=self.pc, pc1=(self.pc + 1) & M32)
        self.vec_r = vec_next
        if pc_en: self.pc = pc_next
        self.st = {'RST': 'BOOT', 'BOOT': 'RUN', 'RUN': 'RUN'}[self.st]
        self.log.append(dict(t=self.t, stall=stall, mispredict=mispredict, inject=inject,
                             D=(NAME.get(opcode, '?') if d_real else ('VEC' if d_vec else '-')) if not inject else 'HWop'))
        self.t += 1

    def run(self, intr_fn=lambda t: 0, max_cycles=20000, drain=8):
        n = 0
        while not self.halted and n < max_cycles:
            self.step(intr_fn(self.t))
            n += 1
        for _ in range(drain):
            self.step(intr_fn(self.t))
        return dict(R=list(self.regs), pc=self.pc, sp=self.sp, ccr=self.ccr, out=self.out,
                    cycles=n, halted=self.halted, inject_at=self.inject_at)
