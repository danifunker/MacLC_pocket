#!/usr/bin/env python3
"""decode_ism.py — full IWM+ISM-aware reconstruction of MAME `maclc` floppy access.

KEY DISCOVERY (2026-06-13): the maclc ROM switches the SWIM to ISM mode almost
immediately (even for an 800K GCR disk) and does drive-ID + reads in ISM mode.

Register addressing (n = (addr>>9)&0xF = cpuAddrRegHi):
  IWM soft-switch: select = n>>1, value = n&1   (16 switches, stride 0x200)
  ISM register:    reg = n & 7                   (8 registers; bit3/0x1000 ignored)
                   ^^ NOTE our rtl/swim.v uses n>>1 (cpuAddrRegHi[3:1]) -> BUG.

ISM regs (swim1.cpp / docs/swim_ism_read_reference.md):
  0 Data(pop) 1 Mark(pop) 2 Error(rd)/CRC(wr) 3 Param 4 Phases 5 Setup
  6 Mode(rd)/ModeClear(wr) 7 Handshake(rd)/ModeSet(wr)
ISM Mode bits: 7 motor,6 ISM,5 HDSEL(head sel),4 write,3 ACTION,2:1 drvsel,0 fifoclr
ISM Setup bits: 5 IBM(1)/Apple(0), 2 GCR(1)/MFM(0) read select
ISM Handshake bits: 7 avail,6 full,5 error,3:2 sense/wprot,1 ~crc0,0 mark
Drive sense register addressed in ISM = (HDSEL<<3)|(ca2<<2)|(ca1<<1)|ca0  (MAME).

Usage: decode_ism.py <tap.txt>
"""
import sys, re

MAME_NAME = {0x0:"Dir",0x1:"Step",0x2:"Motor",0x3:"Eject/DiskChg",0x4:"RdData/Idx",
    0x5:"Superdrive",0x6:"DoubleSide",0x7:"NoDrive",0x8:"NoDiskInPl",0x9:"NoWrProt",
    0xA:"NotTrack0",0xB:"NoTachPulse",0xC:"RdData/Idx",0xD:"MFMModeOn",0xE:"NoReady",0xF:"HD/is_2m"}
ISM_RD = {0:"Data",1:"Mark",2:"Error",3:"Param",4:"Phases",5:"Setup",6:"Mode",7:"Handshk"}
ISM_WR = {0:"Data",1:"Mark",2:"CRC",3:"Param",4:"Phases",5:"Setup",6:"ModeClr",7:"ModeSet"}
LINE = re.compile(r"^(\d+) F(\d+) (VIA|SWIM) (RD|WR) off=([0-9A-F]+) byte=([0-9A-F]+) mask=([0-9A-F]+) pc=([0-9A-F]+)")

def main():
    path=sys.argv[1]
    ism=0
    ca0=ca1=ca2=lstrb=q6=q7=enable=selext=0
    phase_oe=0
    mode=0; setup=0
    ism_switch_seq=0
    transitions=[]
    handshakes=[]     # (seq,pc,headsel,ca2,ca1,ca0,mreg,sense,full_byte)
    phase4_reads=[]   # reg4 reads (phase readback) (seq,pc,oe,val_byte)
    data_reads=[]     # reg0/1 reads (seq,pc,which,byte)
    mode_writes=[]; setup_writes=[]
    ism_full=[]
    ism_acc=0
    # IWM switch detector
    sw_seq=0

    with open(path) as fh:
        for ln in fh:
            m=LINE.match(ln)
            if not m: continue
            seq=int(m.group(1)); region=m.group(3); kind=m.group(4)
            off=int(m.group(5),16); byte=int(m.group(6),16); pc=m.group(8)
            if region=="VIA":
                continue
            n=(off>>9)&0xF
            if not ism:
                sel=n>>1; val=n&1
                if sel==0:ca0=val
                elif sel==1:ca1=val
                elif sel==2:ca2=val
                elif sel==3:lstrb=val
                elif sel==4:enable=val
                elif sel==5:selext=val
                elif sel==6:q6=val
                elif sel==7:q7=val
                if kind=="WR" and q7==1 and q6==1:
                    b6=(byte>>6)&1
                    if sw_seq==0 and b6==1: sw_seq=1
                    elif sw_seq==1 and b6==0: sw_seq=2
                    elif sw_seq==1: sw_seq=0
                    elif sw_seq==2 and b6==1: sw_seq=3
                    elif sw_seq==2: sw_seq=0
                    elif sw_seq==3 and b6==1:
                        ism=1; mode=0x40; ism_switch_seq=seq; sw_seq=0
                        transitions.append((seq,pc,"IWM->ISM"))
                    elif sw_seq==3: sw_seq=0
            else:
                ism_acc+=1
                reg=n&7
                ism_full.append((seq,pc,kind,reg,byte,ca2,ca1,ca0,lstrb,(mode>>5)&1,mode,setup))
                if kind=="WR":
                    if reg==4:
                        ca0=byte&1; ca1=(byte>>1)&1; ca2=(byte>>2)&1; lstrb=(byte>>3)&1
                        phase_oe=(byte>>4)&0xF
                    elif reg==5:
                        setup=byte; setup_writes.append((seq,pc,byte))
                    elif reg==6:   # mode clear
                        mode &= ~byte & 0xFF
                        mode_writes.append((seq,pc,"clr",byte,mode))
                        if byte & 0x40:
                            ism=0; transitions.append((seq,pc,"ISM->IWM"))
                    elif reg==7:   # mode set
                        mode |= byte
                        mode_writes.append((seq,pc,"set",byte,mode))
                else: # RD
                    headsel=(mode>>5)&1
                    if reg==4:
                        phase4_reads.append((seq,pc,phase_oe,byte))
                    elif reg==7:   # Handshake: sense in bit2/3
                        sense=(byte>>2)&1
                        mreg=(headsel<<3)|(ca2<<2)|(ca1<<1)|ca0
                        handshakes.append((seq,pc,headsel,ca2,ca1,ca0,mreg,sense,byte))
                    elif reg in (0,1):
                        data_reads.append((seq,pc,ISM_RD[reg],byte))

    print(f"# transitions: {transitions[:8]}{' ...' if len(transitions)>8 else ''}  (total {len(transitions)})")
    print(f"# ISM accesses total: {ism_acc}")
    print(f"# setup writes: {[(s,p,'%02X'%b) for s,p,b in setup_writes][:12]}")
    print(f"# mode writes (first 20): ")
    for s,p,k,b,mo in mode_writes[:20]:
        bits=[]
        if mo&0x80:bits.append('motor')
        if mo&0x40:bits.append('ISM')
        if mo&0x20:bits.append('HDSEL')
        if mo&0x10:bits.append('WRITE')
        if mo&0x08:bits.append('ACTION')
        print(f"    seq{s} pc{p} {k} data={b:02X} -> mode={mo:02X} [{','.join(bits)}]")

    print(f"\n## ISM HANDSHAKE (sense) READS: {len(handshakes)} total")
    # truth table
    agg={}
    for (seq,pc,hs,ca2,ca1,ca0,mreg,sense,byte) in handshakes:
        agg.setdefault(mreg,{}).setdefault(sense,0); agg[mreg][sense]+=1
    print("  truth table (mame_reg -> sense bits seen):")
    for mreg in sorted(agg):
        bits=" ".join(f"{b}x{c}" for b,c in sorted(agg[mreg].items()))
        print(f"    0x{mreg:X} {MAME_NAME[mreg]:<12} HDSEL={mreg>>3} ca210={mreg&7:03b}  -> {bits}")
    print("  first 40 in order (seq pc HDSEL ca2 ca1 ca0 -> reg sense hbyte):")
    for ev in handshakes[:40]:
        (seq,pc,hs,ca2,ca1,ca0,mreg,sense,byte)=ev
        print(f"    {seq} {pc} hs={hs} {ca2}{ca1}{ca0} -> 0x{mreg:X} {MAME_NAME[mreg]:<11} sense={sense} hbyte={byte:02X}")

    print(f"\n## ISM reg4 (Phases) READS where some lines are INPUTS (oe<0xF): possible sense-on-phase")
    inp=[(s,p,oe,b) for (s,p,oe,b) in phase4_reads if oe!=0xF]
    print(f"   {len(inp)} of {len(phase4_reads)} phase reads had input lines; first 20:")
    for s,p,oe,b in inp[:20]:
        print(f"    seq{s} pc{p} oe={oe:04b} val={b:02X} (low nibble={b&0xF:04b})")

    print(f"\n## ISM Data/Mark FIFO reads: {len(data_reads)} total; first 30:")
    for s,p,w,b in data_reads[:30]:
        print(f"    seq{s} pc{p} {w}={b:02X}")

    print(f"\n## FULL ISM ACCESS LOG (first {min(len(ism_full),140)} of {len(ism_full)}):")
    print(f"   {'seq':>7} {'pc':>8} RW {'reg':<8} byte  ca210 lstrb HDSEL mode setup")
    for (seq,pc,kind,reg,byte,ca2,ca1,ca0,lstrb,hsel,mo,setp) in ism_full[:140]:
        name=(ISM_WR if kind=='WR' else ISM_RD)[reg]
        print(f"   {seq:>7} {pc} {kind} {name:<8} {byte:02X}    {ca2}{ca1}{ca0}    {lstrb}     {hsel}    {mo:02X}   {setp:02X}")

if __name__=="__main__":
    main()
