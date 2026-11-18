import sys; sys.path.insert(0,'/home/claude/scripts')
from models import *
E=enc
def trace(prog, ncyc, start=3, intr=lambda t:0, title=''):
    m=[0]*4096
    for a,w in prog.items(): m[a]=w
    m[0x30]=0x1234
    r=Rtl(m); rows=[]
    for t in range(ncyc):
        nm=lambda c: c.get('nm','-') if c['valid'] else '-'
        D = r.log and None
        ifd=r.ifd; instr=r.qa
        dn = (NAME.get(instr>>26,'?') if ifd['valid'] and not ifd['is_vec'] else ('VEC' if ifd['valid'] else '-'))
        st=(t, hex(r.pc), dn, nm(r.dx1['ctrl']), nm(r.x1x2['ctrl']), nm(r.x2m['ctrl']), nm(r.mw['ctrl']), hex(r.qb), r.regs[3])
        r.step(intr(t)); lg=r.log[-1]
        if lg['inject']: st=st[:2]+('HWop',)+st[3:]
        rows.append(st+(lg['stall'],lg['mispredict']))
    print(title)
    print(f"{'cyc':>3} | {'F(pc)':6} | {'D':5} | {'X1':5} | {'X2':5} | {'M':5} | {'W':5} | q_b(M)  | R3   | note")
    for (t,pc,d,x1,x2,mm,w,qb,r3,stl,mp) in rows[start:]:
        note=('[STALL]' if stl else '')+(' [MISPREDICT]' if mp else '')
        print(f"{t:>3} | {pc:6} | {d:5} | {x1:5} | {x2:5} | {mm:5} | {w:5} | {qb:7} | {r3:4} | {note}")
for dist in (1,2,3):
    p={0:0x10, 0x10:E('LDM',rd=2,imm=0x30), 0x11:E('NOP'),0x12:E('NOP'),0x13:E('NOP')}
    a=0x14; p[a]=E('LDD',rd=1,rs1=2); a+=1
    for i in range(dist-1): p[a]=E('NOP'); a+=1
    p[a]=E('ADD',rd=3,rs1=1,rs2=4); p[a+1]=E('HLT')
    trace(p, 18+dist, start=6, title=f"\n--- LDD R1,0(R2) ; {'NOP ; '*(dist-1)}ADD R3,R1,R4   (distance {dist}, M[0x30]=0x1234)")
