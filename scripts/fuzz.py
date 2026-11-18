import sys, random
sys.path.insert(0, '/home/claude/scripts')
from models import *

ALU3 = ['ADD', 'SUB', 'AND']
def gen(rng, n=60):
    """R7 reserved as data base (=0x800). Code 0x10.., subs at 0x300, ISRs at 0x400/0x480/0x500."""
    m = [0] * 4096
    m[0] = 0x10; m[1] = 0x400; m[2] = 0x480; m[3] = 0x500
    R = lambda: rng.randrange(7)          # R0..R6
    def body(rng, cnt, allow_stack=True, regs=7):
        R = lambda: rng.randrange(regs)
        out = []; depth = 0
        for _ in range(cnt):
            k = rng.random()
            if k < 0.25: out.append(E(rng.choice(ALU3), rd=R(), rs1=R(), rs2=R()))
            elif k < 0.32: out.append(E('CMP', rs1=R(), rs2=R()))
            elif k < 0.40: out.append(E('IADD', rd=R(), rs1=R(), imm=rng.randrange(-70000, 70000) if rng.random()<.2 else rng.randrange(-5, 5)))
            elif k < 0.47: out.append(E(rng.choice(['NOT', 'INC']), rd=R()))
            elif k < 0.53: out.append(E(rng.choice(['SHL', 'SHR']), rd=R(), imm=rng.randrange(0, 40)))
            elif k < 0.58: out.append(E('LDM', rd=R(), imm=rng.randrange(-40000, 40000)))
            elif k < 0.63: out.append(E(rng.choice(['MOV', 'SWAP']), rd=R(), rs1=R()))
            elif k < 0.72: out.append(E('LDD', rd=R(), rs1=7, imm=rng.randrange(-30, 30)))
            elif k < 0.79: out.append(E('STD', rs1=R(), rs2=7, imm=rng.randrange(-30, 30)))
            elif k < 0.82: out.append(E('SETC'))
            elif k < 0.84: out.append(E('IN', rd=R()))
            elif k < 0.86: out.append(E('OUT', rs1=R()))
            elif allow_stack and k < 0.91 and depth < 6: out.append(E('PUSH', rs1=R())); depth += 1
            elif allow_stack and k < 0.96 and depth > 0: out.append(E('POP', rd=R())); depth -= 1
            else: out.append(E('NOP'))
        while depth: out.append(E('POP', rd=R())); depth -= 1
        return out
    E2 = E
    # main
    code = [E('LDM', rd=7, imm=0x800)]
    for _ in range(n):
        k = rng.random()
        if k < 0.75:
            code += body(rng, rng.randrange(1, 5))
        elif k < 0.85:   # forward Jcc / JMP over 0..3 instrs
            skip = body(rng, rng.randrange(0, 4), allow_stack=False)
            code.append(('J', rng.choice(['JZ', 'JN', 'JC', 'JMP']), len(skip)))
            code += skip
        elif k < 0.92:
            code.append(E('CALL', imm=0x300 + 0x20 * rng.randrange(4)))
        elif k < 0.97:
            code.append(E('INT', idx=rng.randrange(2)))
        else:   # small counted backward loop
            r = rng.randrange(7)
            loopbody = body(rng, rng.randrange(1, 4), allow_stack=False)
            # use R6 as counter only if body does not write... just use dedicated: save R6
            code.append(E('PUSH', rs1=6))
            code.append(E('LDM', rd=6, imm=rng.randrange(1, 4)))
            start = len(code)
            # body must not modify R6 -> remap rd=6 to rd=5
            fixed = []
            for w in loopbody:
                if ((w >> 23) & 7) == 6: w = (w & ~(7 << 23)) | (5 << 23)
                if (w >> 26) == OPS['SWAP'] and ((w >> 20) & 7) == 6: w = (w & ~(7 << 20)) | (5 << 20)
                fixed.append(w)
            code += fixed
            code.append(E('IADD', rd=6, rs1=6, imm=-1))
            code.append(('JB', 'JZ', 1))         # JZ out (skip next)
            code.append(('JB', 'JMP', start))
            code.append(E('POP', rd=6))
    code.append(E('HLT'))
    base = 0x10
    words = []
    for i, w in enumerate(code):
        if isinstance(w, tuple):
            kind, op, arg = w
            if kind == 'J': tgt = base + i + 1 + arg
            elif op == 'JZ': tgt = base + i + 2
            else: tgt = base + arg
            w = E(op, imm=tgt)
        words.append(w)
    assert base + len(words) < 0x300
    for i, w in enumerate(words): m[base + i] = w
    for s in range(4):
        b = body(rng, rng.randrange(0, 5)); b.append(E('RET'))
        for i, w in enumerate(b): m[0x300 + 0x20 * s + i] = w
    for a in (0x400, 0x480, 0x500):
        b = body(rng, rng.randrange(0, 6), regs=5); b.append(E('RTI'))
        for i, w in enumerate(b): m[a + i] = w
    return m

E = enc
def one(seed, fix=(), irq_rate=0.0, verbose=False):
    rng = random.Random(seed)
    m = gen(rng)
    inp = rng.getrandbits(32)
    pulses = set(t for t in range(3000) if rng.random() < irq_rate and t > 20)
    rt = Rtl(m, inp, fix=fix).run(lambda t: 1 if t in pulses else 0, max_cycles=5000)
    if not rt['halted']:
        return 'NOHALT', rt
    iz = isa_run(m, inp, irq_before=rt['inject_at'])
    ok = rt['R'] == iz['R'] and rt['sp'] == iz['sp'] and rt['ccr'] == iz['ccr'] and rt['out'] == iz['out'] and rt['pc'] == iz['pc'] + 1
    return ('OK' if ok else 'DIFF'), (rt, iz)

if __name__ == '__main__':
    N = int(sys.argv[1]) if len(sys.argv) > 1 else 2000
    rate = float(sys.argv[2]) if len(sys.argv) > 2 else 0.0
    from collections import Counter
    c = Counter(); bad = []
    irqs = 0
    for s in range(N):
        r, d = one(s, irq_rate=rate)
        c[r] += 1
        if r == 'OK': irqs += len(d[0]['inject_at'])
        if r != 'OK' and len(bad) < 5: bad.append(s)
    print(c, 'irqs_taken', irqs, 'first bad seeds', bad)
