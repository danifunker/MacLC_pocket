#!/usr/bin/env python3
"""
VIA Clock Source Diagnostic Tool

This script helps you trace what's driving the VIA shift register clock (CB1)
in your Mac LC FPGA core. Use it to verify your hypothesis about the deadlock.

Your hypothesis:
- VIA is in external clock mode (ACR=0x1c)
- VIA expects Egret to provide CB1 clock
- Egret firmware stuck in loop, never toggles CB1
- Egret might be waiting for VIA to initiate
- Possible confusion about who drives what

This tool analyzes your logs and RTL to find the answer.
"""

import re
import sys
from pathlib import Path

def parse_via_acr(acr_value):
    """Parse VIA ACR register to determine shift register mode."""
    acr = int(acr_value, 16) if isinstance(acr_value, str) else acr_value
    
    # ACR bits 4:2 = shift register mode
    sr_mode = (acr >> 2) & 0x07
    
    modes = {
        0b000: "Disabled",
        0b001: "Shift in under T2 control",
        0b010: "Shift in under PHI2 control",
        0b011: "Shift in under external clock (CB1)",
        0b100: "Shift out free-running at T2 rate",
        0b101: "Shift out under T2 control",
        0b110: "Shift out under PHI2 control",
        0b111: "Shift out under external clock (CB1)"
    }
    
    mode_desc = modes.get(sr_mode, "Unknown")
    uses_ext_clk = sr_mode in [0b011, 0b111]
    is_shift_out = sr_mode >= 0b100
    
    return {
        'mode': sr_mode,
        'description': mode_desc,
        'uses_external_clock': uses_ext_clk,
        'is_shift_out': is_shift_out,
        'acr_value': acr
    }

def analyze_log_file(logfile):
    """Analyze Mac LC core logs to find VIA configuration and deadlock."""
    
    print("=" * 70)
    print("VIA Clock Source Analysis")
    print("=" * 70)
    print()
    
    acr_values = []
    pb_values = []
    ifr_values = []
    sr_writes = []
    pc_locations = []
    
    with open(logfile, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            
            # Find ACR writes
            match = re.search(r'ACR\s*[=:]\s*([0-9a-fA-Fx]+)', line, re.IGNORECASE)
            if match:
                acr_values.append((line_num, match.group(1)))
            
            # Find Port B values (CB1 is bit 4)
            match = re.search(r'PB_out\s*[=:]\s*([0-9a-fA-Fx]+)', line, re.IGNORECASE)
            if match:
                pb_values.append((line_num, match.group(1)))
            
            # Find IFR values
            match = re.search(r'IFR\s*[=:]\s*([0-9a-fA-Fx]+)', line, re.IGNORECASE)
            if match:
                ifr_values.append((line_num, match.group(1)))
            
            # Find SR writes
            if 'SR WRITE' in line.upper() or 'SR_WRITE' in line.upper():
                sr_writes.append((line_num, line))
            
            # Find Egret PC locations
            match = re.search(r'PC[=:\s]+([0-9a-fA-Fx]+)', line, re.IGNORECASE)
            if match and 'egret' in line.lower():
                pc_locations.append((line_num, match.group(1)))
    
    # Analyze ACR values
    print("📊 VIA ACR (Auxiliary Control Register) Analysis")
    print("-" * 70)
    
    if acr_values:
        last_acr = acr_values[-1][1]
        acr_info = parse_via_acr(last_acr)
        
        print(f"Last ACR value: 0x{acr_info['acr_value']:02X}")
        print(f"Shift register mode: {acr_info['mode']} - {acr_info['description']}")
        print(f"Uses external clock (CB1): {acr_info['uses_external_clock']}")
        print(f"Direction: {'OUT' if acr_info['is_shift_out'] else 'IN'}")
        
        if acr_info['uses_external_clock']:
            print()
            print("⚠️  VIA is in EXTERNAL CLOCK mode!")
            print("   This means VIA expects CB1 to be driven by Egret/CUDA")
            print()
    else:
        print("No ACR values found in log")
    
    print()
    
    # Analyze Port B bit 4 (CB1)
    print("🔌 CB1 Clock Signal Analysis (Port B bit 4)")
    print("-" * 70)
    
    if pb_values:
        # Check last 10 values to see if CB1 is toggling
        recent_pb = pb_values[-10:] if len(pb_values) >= 10 else pb_values
        cb1_values = []
        
        for line_num, pb_hex in recent_pb:
            pb = int(pb_hex, 16) if isinstance(pb_hex, str) else pb_hex
            cb1 = (pb >> 4) & 1
            cb1_values.append(cb1)
            print(f"  Line {line_num}: PB=0x{pb:02X}, CB1 (bit 4) = {cb1}")
        
        # Check if CB1 is stuck
        if all(v == cb1_values[0] for v in cb1_values):
            print()
            print(f"❌ CB1 is STUCK at {cb1_values[0]}!")
            print("   CB1 is not toggling - this is your deadlock!")
        else:
            print()
            print("✅ CB1 is toggling")
    else:
        print("No Port B values found in log")
    
    print()
    
    # Analyze SR writes
    print("✍️  Shift Register Write Activity")
    print("-" * 70)
    
    if sr_writes:
        print(f"Found {len(sr_writes)} SR write(s)")
        for line_num, line in sr_writes[-5:]:
            print(f"  Line {line_num}: {line[:80]}")
    else:
        print("No SR writes found")
    
    print()
    
    # Analyze Egret PC (program counter) to see if it's stuck
    print("🔄 Egret Firmware Status")
    print("-" * 70)
    
    if pc_locations:
        # Get last 10 PC values
        recent_pc = pc_locations[-10:] if len(pc_locations) >= 10 else pc_locations
        
        pc_vals = [int(pc, 16) for _, pc in recent_pc]
        unique_pcs = set(pc_vals)
        
        print(f"Last 10 PC locations: {len(unique_pcs)} unique values")
        
        if len(unique_pcs) <= 3:
            print()
            print("❌ Egret firmware appears STUCK in a loop!")
            print(f"   Repeating PC values: {', '.join(f'0x{pc:04X}' for pc in unique_pcs)}")
            print()
            print("   This confirms your hypothesis:")
            print("   - Egret is waiting for something from VIA")
            print("   - But VIA is waiting for CB1 clock from Egret")
            print("   - Classic circular dependency deadlock!")
        else:
            print("✅ Egret firmware is progressing")
    
    print()
    
    # Generate diagnosis
    print("=" * 70)
    print("🔍 DIAGNOSIS")
    print("=" * 70)
    print()
    
    if acr_values and pb_values:
        last_acr = acr_values[-1][1]
        acr_info = parse_via_acr(last_acr)
        
        if acr_info['uses_external_clock']:
            print("Your hypothesis is CORRECT! Here's what's happening:")
            print()
            print("1. VIA is configured for EXTERNAL CLOCK mode (ACR=0x{:02X})".format(acr_info['acr_value']))
            print("2. VIA expects Egret to provide CB1 clock pulses")
            print("3. But CB1 is stuck (not toggling)")
            print("4. Egret firmware is stuck in a loop waiting for VIA")
            print()
            print("ROOT CAUSE: Circular dependency")
            print("  - VIA waiting for: CB1 clock from Egret")
            print("  - Egret waiting for: ??? (need to check Egret code)")
            print()
            print("SOLUTIONS:")
            print()
            print("Option A: Fix Egret firmware to provide CB1 clock")
            print("  - Check what Egret is waiting for before starting clock")
            print("  - Likely needs TIP/TREQ handshake to be correct")
            print("  - Check Port B bits 1-3 for handshake state")
            print()
            print("Option B: Add CB1 auto-clock wrapper (like you had before)")
            print("  - Detect when VIA writes to SR in shift-out mode")
            print("  - If Egret CB1 not toggling, provide clock automatically")
            print("  - Release after 8 clocks and let Egret take over")
            print()
            print("Option C: Check VIA shift-out initialization")
            print("  - VIA might need to drive CB2 first")
            print("  - Egret might be waiting to see CB2 valid")
            print("  - Then Egret starts providing CB1 clock")

def check_rtl_clock_source(rtl_file):
    """Check RTL to see what's driving CB1."""
    
    print()
    print("=" * 70)
    print("RTL Clock Source Check")
    print("=" * 70)
    print()
    
    if not Path(rtl_file).exists():
        print(f"RTL file not found: {rtl_file}")
        return
    
    with open(rtl_file, 'r') as f:
        content = f.read()
    
    # Find CB1 assignments
    cb1_patterns = [
        r'(\w+)\s*<=\s*.*cb1',
        r'assign\s+(\w*cb1\w*)\s*=',
        r'\.cb1\s*\(\s*(\w+)\s*\)',
    ]
    
    cb1_sources = []
    for pattern in cb1_patterns:
        matches = re.finditer(pattern, content, re.IGNORECASE | re.MULTILINE)
        for match in matches:
            cb1_sources.append(match.group(0))
    
    if cb1_sources:
        print("Found CB1 signal assignments:")
        for source in set(cb1_sources):
            print(f"  {source}")
    else:
        print("No CB1 assignments found")
    
    # Look for clock override/wrapper logic
    if 'cb1_override' in content.lower() or 'wrapper_cb1' in content.lower():
        print()
        print("✅ Found CB1 override/wrapper logic in RTL")
        print("   This suggests auto-clock generation is present")
    else:
        print()
        print("❌ No CB1 override logic found")
        print("   CB1 is directly connected to Egret output")

def main():
    if len(sys.argv) < 2:
        print("Usage: python3 diagnose_via_clock.py <logfile> [rtl_file]")
        print()
        print("Examples:")
        print("  python3 diagnose_via_clock.py latest-logs.txt")
        print("  python3 diagnose_via_clock.py latest-logs.txt egret_wrapper.sv")
        sys.exit(1)
    
    logfile = sys.argv[1]
    
    if not Path(logfile).exists():
        print(f"Error: Log file not found: {logfile}")
        sys.exit(1)
    
    # Analyze logs
    analyze_log_file(logfile)
    
    # Check RTL if provided
    if len(sys.argv) > 2:
        rtl_file = sys.argv[2]
        check_rtl_clock_source(rtl_file)
    
    print()
    print("=" * 70)
    print("Next Steps:")
    print("=" * 70)
    print()
    print("1. Check Port B bits 1-3 (TREQ/TIP/SYS_SESSION) in your logs")
    print("2. Look at Egret firmware at stuck PC addresses")
    print("3. Verify VIA's CB2 output is valid before expecting CB1")
    print("4. Consider enabling CB1 auto-clock wrapper")
    print("5. Compare to MAME logs to see correct sequence")

if __name__ == '__main__':
    main()
