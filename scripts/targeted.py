import sys; sys.path.insert(0,'/home/claude/scripts')
from models import *
E=enc
def mk(d):
    m=[0]*4096
    for a,w in d.items(): m[a]=w
    return m
# T1: 2-instruction polling loop waiting for the ISR to set R1
poll = mk({0:0x10, 1:0x40,
  0x10:E('LDM',rd=1,imm=0), 0x11:E('AND',rd=2,rs1=1,rs2=1), 0x12:E('JZ',imm=0x11), 0x13:E('HLT'),
  0x40:E('LDM',rd=1,imm=1), 0x41:E('RTI')})
# T1b: same loop, 3 instructions (NOP padding)
poll3 = mk({0:0x10, 1:0x40,
  0x10:E('LDM',rd=1,imm=0), 0x11:E('AND',rd=2,rs1=1,rs2=1), 0x12:E('NOP'), 0x13:E('JZ',imm=0x11), 0x14:E('HLT'),
  0x40:E('LDM',rd=1,imm=1), 0x41:E('RTI')})
# T2: HW pulse while software INT 0 ISR is running; then main waits for the HW ISR via polling R1 (3-instr loop)
nest = mk({0:0x10, 1:0x40, 2:0x60,
  0x10:E('LDM',rd=1,imm=0), 0x11:E('INT'), 0x12:E('AND',rd=2,rs1=1,rs2=1), 0x13:E('NOP'), 0x14:E('JZ',imm=0x12), 0x15:E('HLT'),
  0x40:E('LDM',rd=1,imm=1), 0x41:E('RTI'),
  0x60:E('NOP'),0x61:E('NOP'),0x62:E('NOP'),0x63:E('NOP'),0x64:E('NOP'),0x65:E('NOP'),0x66:E('RTI')})
for name,m,pulse in [('poll2',poll,30),('poll3',poll3,30)]:
    for fix in [(),('starve',)]:
        r=Rtl(m,fix=fix).run(lambda t:1 if t==pulse else 0, max_cycles=3000)
        print(f"{name:6s} fix={fix}: halted={r['halted']} cycles={r['cycles']} irqs={r['inject_at']}")
# find when INT ISR runs in T2
r=Rtl(nest); 
for t in range(40): r.step(0)
print('T2 D-stage trace:', ' '.join(f"{x['t']}:{x['D']}" for x in r.log[:30]))
for pulse in [12,13,14,15,16,17,18]:
    for fix in [(),('irqlatch',)]:
        rr=Rtl(nest,fix=fix).run(lambda t:1 if t==pulse else 0, max_cycles=3000)
        print(f"T2 pulse@{pulse} fix={fix}: halted={rr['halted']} cycles={rr['cycles']} irqs={rr['inject_at']}")
