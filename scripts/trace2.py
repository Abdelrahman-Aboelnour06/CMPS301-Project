import sys; sys.path.insert(0,'/home/claude/scripts')
from trace import trace, E
# Suspect 7: INT 1 with ISR at 0x40
trace({0:0x10, 3:0x40, 0x10:E('SETC'), 0x11:E('INT',idx=1), 0x12:E('HLT'), 0x40:E('NOP'), 0x41:E('RTI')}, 26, start=3,
      title='\n--- SETC ; INT 1 ; HLT   (M[3]=0x40: NOP ; RTI)')
# starvation: 2-instruction poll loop, pulse at t=30
trace({0:0x10, 1:0x40, 0x10:E('LDM',rd=1,imm=0), 0x11:E('AND',rd=2,rs1=1,rs2=1), 0x12:E('JZ',imm=0x11), 0x13:E('HLT'),
       0x40:E('LDM',rd=1,imm=1), 0x41:E('RTI')}, 40, start=26, intr=lambda t: 1 if t==30 else 0,
      title='\n--- poll: L: AND R2,R1,R1 ; JZ L    (INTR.IN pulse at cycle 30; pending stays 1 forever)')
