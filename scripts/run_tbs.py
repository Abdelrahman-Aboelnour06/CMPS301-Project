import sys
sys.path.insert(0, '/home/claude/scripts')
from models import *

def mem_from(d):
    m = [0] * 4096
    for a, w in d.items():
        m[a] = w
    return m

def load_mem_file(path):
    m = [0] * 4096; a = 0
    for line in open(path):
        s = line.strip()
        if not s or s[0] in '#/;':
            continue
        tok = s.split()[0]
        if tok.startswith('@'):
            a = int(tok[1:], 16); continue
        m[a] = int(tok, 16); a = (a + 1) % 4096
    return m

E = enc
progs = {}
progs['tb_top'] = mem_from({0: 0x10, 16: E('LDM', rd=1, imm=5), 17: E('LDM', rd=2, imm=7),
    18: E('ADD', rd=3, rs1=1, rs2=2), 19: E('SUB', rd=4, rs1=3, rs2=1), 20: E('SWAP', rd=1, rs1=2),
    21: E('PUSH', rs1=3), 22: E('POP', rd=5), 23: E('AND', rd=6, rs1=4, rs2=3), 24: E('INC', rd=7), 25: E('HLT')})
progs['loaduse'] = mem_from({0: 8, 8: E('LDM', rd=1, imm=100), 9: E('LDM', rd=2, imm=85), 10: E('STD', rs1=2, rs2=1),
    11: E('LDD', rd=3, rs1=1), 12: E('ADD', rd=4, rs1=3, rs2=3), 13: E('LDD', rd=5, rs1=1), 15: E('ADD', rd=6, rs1=5, rs2=2),
    16: E('PUSH', rs1=4), 17: E('POP', rd=7), 18: E('INC', rd=7), 19: E('STD', rd=7, rs1=7, rs2=1, imm=-1),
    20: E('LDD', rs1=1, imm=-1), 21: E('STD', rs2=1, imm=1), 22: E('LDD', rd=2, rs1=1, imm=1), 23: E('HLT')})
progs['branch'] = mem_from({0: 8, 8: E('LDM', rd=1, imm=3), 9: E('LDM'), 10: E('INC'), 11: E('IADD', rd=1, rs1=1, imm=-1),
    12: E('JZ', imm=14), 13: E('JMP', imm=10), 14: E('LDM', rd=2, imm=1), 15: E('LDM', rd=3, imm=2), 16: E('CMP', rs1=2, rs2=3),
    17: E('JC', imm=19), 18: E('LDM', rd=4, imm=119), 19: E('JN', imm=21), 20: E('LDM', rd=5, imm=102), 21: E('CMP', rs1=3, rs2=2),
    22: E('JC', imm=64), 23: E('JN', imm=64), 24: E('JZ', imm=64), 25: E('LDM', rd=6, imm=291), 26: E('SETC'), 27: E('JC', imm=29),
    28: E('HLT'), 29: E('HLT'), 64: E('LDM', rd=7, imm=2989), 65: E('HLT')})
progs['callint'] = mem_from({0: 8, 2: 0x30, 3: 0x38, 8: E('LDM', rd=1, imm=-2), 9: E('CALL', imm=32), 10: E('INC', rd=1),
    11: E('SETC'), 12: E('INT'), 13: E('INT', idx=1), 14: E('SWAP', rd=3, rs1=3), 15: E('MOV', rd=4, rs1=3), 16: E('SWAP', rd=4, rs1=1),
    17: E('ADD', rd=5, rs1=4, rs2=1), 18: E('SHL', rd=6, imm=4), 19: E('SHR', rd=6, imm=1), 20: E('IN', rd=7), 21: E('OUT', rs1=7),
    22: E('NOT', rd=7), 23: E('HLT'), 32: E('INC', rd=1), 33: E('INC', rd=1), 34: E('LDM', rd=6, imm=3841), 35: E('RET'),
    48: E('LDM', rd=2, imm=4369), 49: E('CMP', rs1=2, rs2=2), 50: E('RTI'), 56: E('LDM', rd=3, imm=8738),
    57: E('IADD', rd=3, rs1=3, imm=1), 58: E('RTI')})
progs['irq'] = mem_from({0: 8, 1: 0x50, 8: E('LDM'), 9: E('LDM', rd=1, imm=20), 10: E('IADD', imm=2), 11: E('IADD', rd=1, rs1=1, imm=-1),
    12: E('JZ', imm=14), 13: E('JMP', imm=10), 14: E('OUT'), 15: E('HLT'), 80: E('PUSH', rs1=2), 81: E('INC', rd=7),
    82: E('SETC'), 83: E('LDM', rd=2, imm=-1), 84: E('CMP', rs1=2, rs2=2), 85: E('POP', rd=2), 86: E('RTI')})
progs['demo'] = load_mem_file('/home/claude/src/cmps301/programs/demo.mem')

inputs = dict(callint=0x1234ABCD, demo=0x0000ABCD)
irqs = dict(irq=lambda t: 1 if (30 <= t < 32 or 120 <= t < 125) else 0,
            demo=lambda t: 1 if t == 40 else 0)

exp = {
 'tb_top': dict(R=[0, 7, 5, 0xC, 7, 0xC, 4, 1], sp=0xFFF, ccr=0, out=0, pc=0x1A),
 'loaduse': dict(R=[0xAB, 0x64, 0xAB, 0x55, 0xAA, 0x55, 0xAA, 0xAB], sp=0xFFF, ccr=0b0000, out=0, pc=0x18),
 'branch': dict(R=[3, 0, 1, 2, 0, 0, 0x123, 0], sp=0xFFF, ccr=0b0100, out=0, pc=0x1E),
 'callint': dict(R=[0, 0x2223, 0x1111, 0x2223, 1, 0x2224, 0x7808, 0xEDCB5432], sp=0xFFF, ccr=0b0010, out=0x1234ABCD, pc=0x18),
 'irq': dict(R=[0x28, 0, 0, 0, 0, 0, 0, 2], sp=0xFFF, ccr=0b0101, out=0x28, pc=0x10),
 'demo': dict(R=[0, 0x208, 0xFFFF8FFF, 0x7000, 1, 0x702C, 0x64, 0xABC00], sp=0xFFF, ccr=2, out=0x702C, pc=0x2B),
}

def show(name, fix=()):
    m = progs[name]
    rt = Rtl(m, inputs.get(name, 0), fix=fix).run(irqs.get(name, lambda t: 0))
    iz = isa_run(m, inputs.get(name, 0), irq_before=rt['inject_at'])
    e = exp[name]
    print(f"== {name}  fix={sorted(fix)}  cycles={rt['cycles']} irq_taken_before_instr#{rt['inject_at']}")
    for key in ('R', 'sp', 'ccr', 'out', 'pc'):
        a, b, c = rt[key], (iz[key] if iz else None), e[key]
        if key == 'pc' and iz: b = iz['pc'] + 1   # RTL PC frozen at HLT+1
        fmt = (lambda v: [hex(x) for x in v]) if key == 'R' else hex
        flag = '' if (a == c and a == b) else '   <-- MISMATCH'
        print(f"  {key:3s} rtl={fmt(a)} isa={fmt(b) if b is not None else None} tb={fmt(c)}{flag}")

if __name__ == '__main__':
    for n in progs:
        show(n)
