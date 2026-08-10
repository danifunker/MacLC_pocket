#!/usr/bin/env python3
"""decode_tap.py — reconstruct SWIM/IWM drive-sense (drive-ID) reads from a
floppy_tap.lua capture of MAME `maclc`.

The sense register index is {ca2,ca1,ca0,SEL}:
  - ca0/ca1/ca2 + q6/q7 are IWM soft-switches in $F16000-$F17FFF, toggled by ANY
    access (read OR write) to base+(n<<9); n>>1 picks the switch, n&1 the value.
  - SEL/HDSEL is VIA1 Port-A bit5: SEL = (~DDRA5) | ORA5  (matches floppy.v).
A status/sense read is any SWIM READ whose post-toggle state is q6=1,q7=0; the
sense bit is byte bit7.

Usage: decode_tap.py <tap.txt> [--seq-start N] [--seq-end N]
"""
import sys, re

# MAME mac_floppy wpt_r register names (floppy.cpp), indexed by (SEL<<3|ca2<<2|ca1<<1|ca0)
MAME_NAME = {
    0x0:"Dir", 0x1:"Step", 0x2:"Motor", 0x3:"Eject/DiskChg",
    0x4:"RdData/Index", 0x5:"Superdrive", 0x6:"DoubleSide", 0x7:"NoDrive",
    0x8:"NoDiskInPl", 0x9:"NoWrProtect", 0xA:"NotTrack0", 0xB:"NoTachPulse",
    0xC:"RdData/Index", 0xD:"MFMModeOn", 0xE:"NoReady", 0xF:"HD/is_2m",
}
# Our floppy.v driveRegsAsRead bit names, indexed by (ca2<<3|ca1<<2|ca0<<1|SEL)
OUR_NAME = {
    0:"DIRTN", 1:"CSTIN", 2:"STEP", 3:"WRTPRT", 4:"MOTORON", 5:"TK0",
    6:"SWITCHED", 7:"TACH", 8:"RDDATA0", 9:"RDDATA1", 10:"SUPERDR",
    11:"MFMModeOn", 12:"SIDES", 13:"READY", 14:"INSTALLED", 15:"DRVIN",
}

LINE = re.compile(r"^(\d+) F(\d+) (VIA|SWIM) (RD|WR) off=([0-9A-F]+) byte=([0-9A-F]+) mask=([0-9A-F]+) pc=([0-9A-F]+)")

def main():
    path = sys.argv[1]
    seq_start = 0; seq_end = 1<<62
    if "--seq-start" in sys.argv: seq_start = int(sys.argv[sys.argv.index("--seq-start")+1])
    if "--seq-end"   in sys.argv: seq_end   = int(sys.argv[sys.argv.index("--seq-end")+1])

    # IWM soft-switch state
    ca0=ca1=ca2=lstrb=enable=selext=q6=q7=0
    # VIA Port A
    ora5=0; ddra5=0
    # ISM mode tracking (IWM->ISM via 4x bit6 toggle on q7q6=11 writes)
    ism_mode=0; ism_seq=0

    events=[]          # sense reads (IWM status)
    data_reads=[]      # q6=0,q7=0 data reads (GCR path)
    ism_events=[]      # accesses while in ISM mode
    ism_switch_seq=None

    def sel():
        return (0 if ddra5 else 1) | ora5   # (~oe|o)

    with open(path) as fh:
        for ln in fh:
            m=LINE.match(ln)
            if not m: continue
            seq=int(m.group(1)); frame=int(m.group(2)); region=m.group(3)
            kind=m.group(4); off=int(m.group(5),16); byte=int(m.group(6),16); pc=m.group(8)
            if seq<seq_start or seq>seq_end: continue

            if region=="VIA":
                if kind=="WR":
                    reg=(off>>9)&0xF
                    if reg in (0x1,0xF):       # ORA (handshake / no-handshake)
                        ora5=(byte>>5)&1
                    elif reg==0x3:             # DDRA
                        ddra5=(byte>>5)&1
                continue

            # region == SWIM
            n=(off>>9)&0xF
            if not ism_mode:
                # apply soft-switch toggle for THIS access (read or write)
                sw=n>>1; val=n&1
                if   sw==0: ca0=val
                elif sw==1: ca1=val
                elif sw==2: ca2=val
                elif sw==3: lstrb=val
                elif sw==4: enable=val
                elif sw==5: selext=val
                elif sw==6: q6=val
                elif sw==7: q7=val

                # IWM->ISM mode switch detector: 4x bit6 pattern on q7q6=11 writes
                if kind=="WR" and q7==1 and q6==1:
                    b6=(byte>>6)&1
                    if   ism_seq==0 and b6==1: ism_seq=1
                    elif ism_seq==1 and b6==0: ism_seq=2
                    elif ism_seq==1: ism_seq=0
                    elif ism_seq==2 and b6==1: ism_seq=3
                    elif ism_seq==2: ism_seq=0
                    elif ism_seq==3 and b6==1:
                        ism_mode=1; ism_switch_seq=seq
                    elif ism_seq==3: ism_seq=0

                if kind=="RD":
                    s=sel()
                    if q6==1 and q7==0:
                        our_idx=(ca2<<3)|(ca1<<2)|(ca0<<1)|s
                        mame_reg=(s<<3)|(ca2<<2)|(ca1<<1)|ca0
                        events.append((seq,frame,pc,ca2,ca1,ca0,s,mame_reg,our_idx,(byte>>7)&1,byte))
                    elif q6==0 and q7==0:
                        data_reads.append((seq,frame,pc,byte))
            else:
                ism_events.append((seq,frame,pc,kind,(off>>9)&0xF,n&7,byte))

    # ---- report ----
    print(f"# total sense(status) reads: {len(events)}   data reads(q6q7=00): {len(data_reads)}")
    if ism_switch_seq: print(f"# *** IWM->ISM mode switch at seq {ism_switch_seq}; ISM accesses: {len(ism_events)} ***")
    else:              print(f"# no IWM->ISM switch detected (stayed IWM/GCR)")

    # truth table: mame_reg -> observed sense bits
    print("\n## TRUTH TABLE (observed sense bit per addressed register)")
    print(f"{'mame':>4} {'mame_name':<14} {'our':>3} {'our_name':<10} {'SEL':>3} {'bits':<10} {'count':>6}")
    agg={}
    for (seq,frame,pc,ca2,ca1,ca0,s,mreg,oidx,sb,byte) in events:
        agg.setdefault((mreg,oidx,s),{}).setdefault(sb,0)
        agg[(mreg,oidx,s)][sb]+=1
    for (mreg,oidx,s) in sorted(agg):
        bits="".join(f"{b}x{c} " for b,c in sorted(agg[(mreg,oidx,s)].items()))
        print(f"{('0x%X'%mreg):>4} {MAME_NAME[mreg]:<14} {('0x%X'%oidx):>3} {OUR_NAME[oidx]:<10} {s:>3} {bits:<10}")

    # first probe burst (temporal order)
    print("\n## FIRST 80 SENSE READS (temporal order)")
    print(f"{'seq':>9} {'pc':>8}  ca2ca1ca0 SEL  {'mame':>4} {'mame_name':<14} {'our_name':<10} sense")
    for ev in events[:80]:
        (seq,frame,pc,ca2,ca1,ca0,s,mreg,oidx,sb,byte)=ev
        print(f"{seq:>9} {pc:>8}   {ca2} {ca1} {ca0}   {s}   0x{mreg:X}  {MAME_NAME[mreg]:<14} {OUR_NAME[oidx]:<10}  {sb}")

if __name__=="__main__":
    main()
