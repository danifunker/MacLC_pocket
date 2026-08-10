# Mac LC ROM Boot Sequence Analysis

## Power-On to Sad Mac: Complete Boot Stage Reference

Analysis based on SuperMario source code (1994-02-09) cross-referenced with MacLCROM.map.  
Intended audience: MiSTer FPGA core developers.

---

## Table of Contents

1. [Boot Sequence Overview](#boot-sequence-overview)
2. [Detailed Boot Stages](#detailed-boot-stages)
3. [AppleTalk / NetBoot Analysis](#appletalk--netboot-analysis)
4. [Sad Mac / Critical Error Display](#sad-mac--critical-error-display)
5. [Key ROM Addresses (MacLCROM.map)](#key-rom-addresses)
6. [Source File Reference](#source-file-reference)

---

## Boot Sequence Overview

```
POWER ON
   |
   v
[1] ROM Reset Vector (offset 0x04) --> ResetEntry (offset 0x2A)
   |
   v
[2] StartBoot: CPU init, disable interrupts, RESET hardware
   |
   v
[3] JumpIntoROM: VIA/hardware base detection (Universal.a)
   |
   v
[4] StartTest1: POST diagnostics, RAM test (USTStartup.a)
   |
   v
[5] StartInit1: Hardware config, VIA init, PRAM, RAM config, MMU
   |
   v
[6] SCC/IWM/SCSI/Sound hardware init
   |
   v
[7] Exception vectors, cache enable, timing calibration
   |
   v
[8] BootRetry: Memory Manager, trap dispatcher, heap setup
   |
   v
[9] Interrupt system, Power Manager, Egret/Cuda init
   |
   v
[10] Resource Manager, Notification Manager, Time Manager
   |
   v
[11] Slot Manager init (gray screens appear here)
   |
   v
[12] Gestalt, processor interrupts enabled (SR = $2000)
   |
   v
[13] I/O subsystem: Device Manager, LoadDrivers (floppy, NetBoot, sound, video, serial)
   |
   v
[14] SCSI Manager, ADB, cursor, fonts, TextEdit
   |
   v
[15] DrawBeepScreen (gray pattern on all screens)
   |
   v
[16] Sound Manager, File System init
   |
   v
[17] SCSI Boot init (for async SCSI systems)
   |
   v
[18] BootMe --> FindStartupDevice (boot device search loop)
   |
   v
[19] Boot blocks loaded --> Happy Mac icon
   |
   v
[20] InitSys7Toolbox (called from boot blocks / Boot3.a)
   |
   v
[21] System startup complete --> Finder launched
```

---

## Detailed Boot Stages

### Stage 1: ROM Header and Reset Vector
**Source:** `OS/StartMgr/StartTop.a`, `OS/StartMgr/StartInit.a:1165`  
**ROM offset:** 0x00

The 68K reads its initial SP from ROM offset 0x00 and its reset PC from offset 0x04.

```
Offset  Symbol          Purpose
0x00    (SP value)      Initial stack pointer
0x04    StartPC         Reset vector -> ResetEntry
0x0A    StBoot          Restart entry -> JMP StartBoot
0x0E    BadDisk         Eject and reboot -> JMP StartBoot
0x22    DispOff         Offset to dispatch table
0x26    Critical        Critical error -> JMP CritErr
0x2A    ResetEntry      Reset entry point -> JMP StartBoot
0x2E    RomLoc          ROM location flags
0x48    (offset)        Offset to InitSys7Toolbox (used by Boot3.a)
```

### Stage 2: StartBoot - CPU State Initialization
**Source:** `OS/StartMgr/StartInit.a:1229-1293`  
**ROM offset:** ~0xB8 area

```asm
StartBoot:
    MOVE    #$2700,SR           ; Disable ALL processor interrupts
    ; Test for 68040 CPU by attempting to enable data cache
    ; Enable/disable caches based on CPU type (040/030/020)
    ; Disable MMU (clear Translation Control register)
    RESET                       ; ***** Reset The World *****
    BSR6    JumpIntoROM         ; Init hardware (Universal.a)
    BRA.L   StartTest1          ; Run universal diagnostics
```

**What the FPGA must implement:**
- 68K must fetch reset vectors from ROM base
- `RESET` instruction resets all external hardware
- VIA, SCC, IWM, SCSI chips must respond to hardware reset

### Stage 3: JumpIntoROM / Universal Hardware Init
**Source:** `OS/StartMgr/Universal.a` (offset 0x2E00 in ROM)  
**Key routines:** `InitVIAs`, `GetHardwareInfo`, `GetExtHardwareInfo`

This stage detects the hardware configuration:
- Identifies the Mac model via the ProductInfo table
- Determines VIA type (VIA1, VIA2, RBV)
- Gets base addresses for all hardware peripherals
- Returns flags indicating which hardware is present

### Stage 4: StartTest1 - POST Diagnostics
**Source:** `OS/StartMgr/USTStartup.a`

- RAM size detection and basic memory test
- Hardware validation
- Cache initialization
- Returns with A6 pointing to RAM chunk table

**On failure:** Calls `CritErr` which displays the Sad Mac icon.

### Stage 5: StartInit1 - Core Hardware Configuration
**Source:** `OS/StartMgr/StartInit.a:1294-1627`

This is the main initialization sequence after diagnostics pass:

| Step | Routine | Purpose |
|------|---------|---------|
| 5a | `GetHardwareInfo` | Detect Mac model, fill ProductInfo |
| 5b | `GetExtHardwareInfo` | Extended hardware features |
| 5c | `InitVIAs` | Initialize VIA1, VIA2/RBV chips |
| 5d | `ValidatePRAM` | Check PRAM integrity |
| 5e | `ConfigureRam` | Set up RAM banks, determine sizes |
| 5f | `WhichCPU` | Detect 68000/010/020/030/040 |
| 5g | `WhichBoard` | Detect logic board type |
| 5h | `InitMMU` | Generate MMU tables, enable translation |
| 5i | Set up low memory | MemTop, BufPtr, CpuFlag, BoxFlag, etc. |

**After this stage:**
- A4 = pointer to BootGlobs (logical space)
- A5 = top of usable memory
- A6 = top of memory
- SP = middle of usable logical space
- MMU is active (if present)
- Low memory globals are initialized

### Stage 6: Hardware Peripheral Init
**Source:** `OS/StartMgr/StartInit.a:1510-1570`

| Step | Routine | Purpose |
|------|---------|---------|
| 6a | `SetupHWBases` | Set hardware base address low memory globals |
| 6b | `InitSCC` | Initialize Serial Communication Controller |
| 6c | `InitIWM` | Initialize floppy disk controller |
| 6d | `InitSCSIHw` | Initialize SCSI hardware (if not async SCSI) |
| 6e | `InitSndHW` | Initialize sound hardware |
| 6f | `InitMMUGlobals` | Set up MMU-related globals |

### Stage 7: System Foundation
**Source:** `OS/StartMgr/StartInit.a:1575-1627`

| Step | Routine | Purpose |
|------|---------|---------|
| 7a | `SysErrInit` | Install exception vectors |
| 7b | `InstallFPSP` | Install 68040 FP emulation (if 040) |
| 7c | `EnableExtCache` | Enable external cache |
| 7d | `DisableIntSources` | Mask all interrupt sources |
| 7e | `SetUpTimeK` | Calibrate TimeDBRA and TimeSCCDB timing loops |
| 7f | `InitHiMemGlobals` | Set up high memory (clip BufPtr if >8MB on 24-bit) |

**Note:** `TimeSCCDB` is specifically used by AppleTalk for timing.

### Stage 8: BootRetry - Memory Manager & Trap Dispatcher
**Source:** `OS/StartMgr/StartInit.a:1628-1710`  
**ROM offset:** 0x1A6

This is the **boot retry point** - the system returns here if boot fails.

| Step | Routine | Purpose |
|------|---------|---------|
| 8a | `InitGlobalVars` | Initialize global variables |
| 8b | `DisableIntSources` | Re-mask all interrupts |
| 8c | `InitDispatcher` | Initialize trap dispatcher |
| 8d | `InitMMUTrap` | Install SwapMMUMode trap |
| 8e | `InitMemMgr` | **Initialize Memory Manager** |
| 8f | `SetUpSysAppZone` | Set up system/application heap zones |
| 8g | `CompBootStack` | Move SP to middle of RAM |
| 8h | `_SetApplLimit` | Set application heap limit |
| 8i | `InitMemoryDispatch` | Set up MemoryDispatch globals |
| 8j | Allocate `ExpandMem` | Extended low-memory record |

### Stage 9: Interrupt System & Power Management
**Source:** `OS/StartMgr/StartInit.a:1710-1740`

| Step | Routine | Purpose |
|------|---------|---------|
| 9a | `InitIntHandler` | Initialize interrupt vectors and dispatch tables |
| 9b | `InstallPrivTrap` | Set up FPPriv if FPU present |
| 9c | `InitPmgrVars` | Initialize Power Manager (if portable) |
| 9d | `InitEgretOrCuda` | Initialize Egret/Cuda Manager (if present) |
| 9e | `InitSwitcherTable` | Initialize Switcher's table |

### Stage 10: High-Level System Managers
**Source:** `OS/StartMgr/StartInit.a:1745-1775`

| Step | Routine | Purpose |
|------|---------|---------|
| 10a | `GetPRAM` | Read 20 bytes of PRAM and TIME |
| 10b | `SetPRAM32` | Force PRAM to 32-bit mode |
| 10c | `InitRSRCMgr` | **Initialize Resource Manager** |
| 10d | `NMInit` | Initialize Notification Manager |
| 10e | `InitTimeMgr` | Initialize Time Manager |
| 10f | `_ShutDown` (INIT) | Initialize ShutDown queue |

### Stage 11: Slot Manager & Interrupts Enabled
**Source:** `OS/StartMgr/StartInit.a:1775-1815`

| Step | Routine | Purpose |
|------|---------|---------|
| 11a | `InitSlots` | **Initialize slot cards, gray screens appear** |
| 11b | `InitDTQueue` | Initialize Deferred Task Manager |
| 11c | `EnableOneSecInts` | Enable 1-second clock interrupts |
| 11d | `Enable60HzInts` | Enable VBL (60Hz) interrupts |
| 11e | `MOVE #$2000,SR` | **ENABLE PROCESSOR INTERRUPTS** |

**This is where the first visible output appears** - InitSlots grays the screens on all video cards.

### Stage 12: Gestalt & Code Fragment Manager
**Source:** `OS/StartMgr/StartInit.a:1815-1845`

| Step | Routine | Purpose |
|------|---------|---------|
| 12a | `initGestalt` | Initialize Gestalt selector manager |
| 12b | `BlockMove68040` | Optimize BlockMove for 040 (if applicable) |
| 12c | `GoNative` | Load NCODs for PowerPC (if PowerPC machine) |

**On GoNative failure:** `_SysError` with `dsGNLoadFail` -> Sad Mac.

### Stage 13: Driver Loading
**Source:** `OS/StartMgr/StartInit.a:1845-1875` and `LoadDrivers` routine at line 3290

| Step | Driver | RefNum/ID | Notes |
|------|--------|-----------|-------|
| 13a | Initialize drive queue | - | `DrvQHdr` |
| 13b | `InitIOPStuff` | - | I/O Processor init |
| 13c | `InitDeviceMgr` | - | Unit I/O table |
| 13d | **Floppy (.Sony)** | - | Via `_Open` if IWM/SWIM exists |
| 13e | **NetBoot (.netBOOT)** | ID 49 | **Loaded from ROM resource if hasNetBoot** |
| 13f | RAM Disk (.EDisk) | ID 48 | If hasEDisk |
| 13g | Sound (.Sound) | - | Via `_Open` |
| 13h | **Video (FROVideo)** | - | Opens default video driver |
| 13i | Backlight | ID -16511 | If hasPwrControls |
| 13j | Serial (SERD) | - | From ROM resource |

**IMPORTANT for FPGA:** The NetBoot driver (.netBOOT, DRVR ID 49) is installed at this stage. It is loaded via `_GetNamedResource` from ROM resources and installed into the unit table at an entry >= 48 (to avoid the AppleTalk driver area which occupies unit table entries 1-47).

### Stage 14: SCSI, ADB, Cursor, Fonts
**Source:** `OS/StartMgr/StartInit.a:1845-1870`

| Step | Routine | Purpose |
|------|---------|---------|
| 14a | `InitSCSIMgr` | Initialize old and new SCSI Managers |
| 14b | `INSTALLBASSCOMMON` | Initialize Bass (font system) |
| 14c | `FORCEINITFONTSCALL` | More font init |
| 14d | `InitCrsrDev` | Initialize cursor globals (before ADB!) |
| 14e | `InitADB` | **Initialize ADB interface** |
| 14f | `InitCrsrMgr` | Initialize cursor variables |
| 14g | `InitReliability` | Initialize Reliability Manager |
| 14h | `TEGlobalInit` | Initialize TextEdit vectors |

### Stage 15: Screen Setup
**Source:** `OS/StartMgr/StartInit.a:1860-1875`

| Step | Routine | Purpose |
|------|---------|---------|
| 15a | `EnableSlotInts` | Enable NuBus slot interrupts |
| 15b | `DrawBeepScreen` | **Draw gray pattern on all screens** |
| 15c | `WarmStart` set | Write warm start constant |

### Stage 16: Sound & File System
**Source:** `OS/StartMgr/StartInit.a:1875-1900`

| Step | Routine | Purpose |
|------|---------|---------|
| 16a | `InitSoundMgr` | Initialize Sound Manager |
| 16b | `_InitFS` | Initialize File System (40 FCBs) |
| 16c | `SetupDockBases` | Initialize docking bar base addresses |
| 16d | `INITSCSIBOOT` | Initialize SCSI boot (if async SCSI) |

### Stage 17: Transfer to BootMe
**Source:** `OS/StartMgr/StartInit.a:1875`

```asm
    BRA     BootMe          ; Exit Stage Right
```

Control transfers to `StartBoot.a`.

### Stage 18: BootMe - Find Startup Device
**Source:** `OS/StartMgr/StartBoot.a:292-399` and `OS/StartMgr/StartSearch.a:265-350`

```
BootMe:
    |
    +-- CheckForROMDisk         ; Check for bootable ROM disk
    |   (if found, skip FindStartupDevice)
    |
    +-- FindStartupDevice       ; Main boot device search
        |
        +-- EmbarkOnSearch      ; Read PRAM default startup device
        |   |
        |   +-- _GetDefaultStartup   ; Get default device from PRAM
        |   +-- _GetOSDefault        ; Get default OS from PRAM
        |
        +-- LoadSlotDrivers     ; Execute slot card boot code
        |
        +-- LoadSCSIDrivers     ; Load SCSI device drivers (via SCSILoad or ITTBOOT)
        |
        +-- WaitForPollDrive    ; Wait for default SCSI drive to spin up
        |   |                     (timeout from PRAM, default ~7 seconds)
        |   |
        |   +-- [polling loop with PollDelay between retries]
        |   +-- [timeout: DisableDynWait, continue without it]
        |
        +-- [Main search loop]:
            |
            +-- VisualUpdate        ; Update disk icon animation
            +-- FindNextCandidate   ; Walk drive queue for next device
            +-- SelectDevice        ; Set up parameter block
            +-- CheckMouseEject     ; Eject if mouse button held
            +-- GetStartupInfo      ; Read boot blocks from device
            |   |
            |   +-- SUCCESS --> HappyMac icon --> return
            |   +-- FAILURE --> ReactToFailure
            |       |
            |       +-- OffLinErr: device not ready, try later
            |       +-- NoDriveErr: device gone, disable in BootMask
            |       +-- Other: eject and retry
            |
            +-- [Loop back to FindNextCandidate]
            +-- [If queue exhausted, start over from @NextPass]
```

**The search loop runs indefinitely** until a bootable device is found. On portables, it will eventually sleep. On desktops (like Mac LC), it loops forever showing the floppy disk icon with a blinking `?`.

### Stage 19: Boot Blocks Execution
**Source:** `OS/StartMgr/StartBoot.a:350-400`

After `FindStartupDevice` returns successfully:
1. Happy Mac icon is displayed
2. Boot blocks from the startup device are validated
3. If executable boot blocks (old or new format), they are executed via `JSR BBEntry(A6)`
4. If boot blocks fail, the boot device is ejected/disabled and BootMe restarts

**On boot block failure (with NetBoot):**
```asm
; Close the netBoot driver and clear AppleTalk vectors
IF HasNetBoot THEN
    move    #-(49+1),ioRefNum(a0)   ; refnum of the netBoot driver
    _Close                          ; close it
    moveq.l #-1, d0
    move.l  d0,AGBHandle            ; clear the appletalk dispatch vector
    move.l  d0,AtalkHk2             ; clear the LapManager hook
ENDIF
    bra     BootMe                  ; try again
```

### Stage 20: InitSys7Toolbox
**Source:** `OS/StartMgr/StartBoot.a:640-741`

Called from Boot3.a (disk-based boot code) via ROM vector at offset 0x48:

| Step | Routine | Purpose |
|------|---------|---------|
| 20a | `_InitAllPacks` | Make packages available |
| 20b | `NewGestaltSelectors` | Additional Gestalt selectors |
| 20c | `ALIASMGRINSTALL` | Alias Manager |
| 20d | `SetupGlobals/Gestalt` | Comm Toolbox |
| 20e | `InitDialogMgrGlobals` | Dialog Manager |
| 20f | `PPCINSTALL` | PPC Toolbox |
| 20g | `NMINIT` | Notification Manager reinit |
| 20h | `__InitComponentManager` | Component Manager |
| 20i | `TSMgrInstall` | Text Services Manager |
| 20j | `InitADBDrvr` | ADB driver reinit |
| 20k | `_SecondaryInit` | Slot secondary initialization |
| 20l | `OpenSlots` | Open all slot drivers |
| 20m | `_InitGraf` / `_InitPalettes` | Reinit QuickDraw with new devices |
| 20n | `_InitFonts` | Reinit Font Manager |
| 20o | `CacheInstall` | Install disk cache |
| 20p | `LateLoad` | Wait for late SCSI devices, load their drivers |
| 20q | VM Final Init | If VM loaded, finalize it |

---

## AppleTalk / NetBoot Analysis

### How NetBoot Works During Boot

The NetBoot system is a **boot device driver** that participates in the standard `FindStartupDevice` search. It is NOT a background initialization that runs independently - it is invoked as part of the normal boot device search.

### NetBoot Architecture

```
FindStartupDevice (StartSearch.a)
    |
    +-- Walks the Drive Queue looking for bootable devices
    |
    +-- .netBOOT driver (DRVR ID 49) installs itself in Drive Queue
    |   during LoadDrivers (Stage 13e) if:
    |     1. hasNetBoot is true (it IS true for Mac LC)
    |     2. The DRVR resource exists in ROM
    |     3. DOOPEN succeeds (checks PRAM BOOT_ENABLE flag)
    |
    +-- When FindStartupDevice tries to read boot blocks from
    |   the netBoot drive, it calls _Read on the driver
    |
    +-- DOREAD (NetBoot.c) is called:
        |
        +-- FINDNOPENDRIVER: Opens the protocol boot driver
        |   |
        |   +-- Reads PRAM to get boot protocol
        |   +-- If protocol == DrSwATalk (AppleTalk):
        |   |   Opens ".ATBOOT" driver inline
        |   +-- Else: Searches slot ROM for boot protocol entry
        |
        +-- PBControl(getBootBlocks): Asks protocol driver for boot blocks
        |   |
        |   +-- .ATBOOT driver calls get_image() (GetServer.c):
        |       |
        |       +-- MPPOpen()           ; Open AppleTalk
        |       +-- DDPOpenSocket()     ; Open DDP socket (BOOTSOCKET=10)
        |       +-- find_server()       ; NBP lookup for "BootServer"
        |       |   |
        |       |   +-- PLookupName()   ; NBP lookup with timeout
        |       |   +-- [sends user record requests via DDP]
        |       |   +-- [waits for server replies]
        |       |
        |       +-- [Image download loop]:
        |           +-- sendImageRequest()
        |           +-- [wait for packets via socket listener]
        |           +-- [retransmit with exponential backoff]
        |           +-- [timeout: retransThreshold < lookup_timeout]
        |
        +-- If boot blocks obtained: PBControl(getSysVol)
        |   +-- Hook into ExtFS for volume mounting
        |
        +-- If error:
            +-- Returns FATAL (mapped to NoDriveErr) or
            +-- Returns non-fatal (mapped to OffLinErr)
```

### When AppleTalk Initialization Happens

AppleTalk is initialized **only when the NetBoot driver is actually read from** during the boot device search. The sequence is:

1. **Stage 13e** (`LoadDrivers`): The `.netBOOT` driver DRVR is loaded from ROM resources and installed in the unit table. At this point, `DOOPEN` is called which:
   - Reads PRAM to check `BOOT_ENABLE` flag
   - If enabled, adds itself to the Drive Queue
   - **AppleTalk is NOT initialized yet**

2. **Stage 18** (`FindStartupDevice`): When the search loop reaches the netBoot drive in the Drive Queue and calls `GetStartupInfo` (which does `_Read`):
   - `DOREAD` is called
   - `FINDNOPENDRIVER` opens the `.ATBOOT` driver
   - `.ATBOOT` calls `get_image()` which calls `MPPOpen()` - **THIS is when AppleTalk actually initializes**

### How Long AppleTalk Blocks

The AppleTalk boot process has **two timeout mechanisms**:

1. **NBP Lookup timeout** (`find_server`):
   - Controlled by `nbpVars` parameter (from PRAM)
   - Default: interval=4 (4*8=32 ticks between lookups), count=1
   - Total lookup time: approximately `interval * 8 * count * 8` ticks
   - If no server found: returns `NOT_FOUND`

2. **Image download timeout** (`get_image` main loop):
   - `retransThreshold` starts at `lookup_timeout / 8`
   - Doubles on each failed retransmission (exponential backoff)
   - Loop exits when `retransThreshold >= lookup_timeout`
   - This means total timeout is approximately `lookup_timeout` ticks

### When NetBoot Exits

The NetBoot driver exits (and AppleTalk activity stops) when:

1. **Server not found** (`NOT_FOUND`): `find_server()` returns `INVALID_ADDR`. `get_image()` returns `NOT_FOUND`, which is mapped to `FATAL` by `DOREAD`, which maps to `NoDriveErr`. `ReactToFailure` disables this drive in `BootMask` so it won't be tried again.

2. **Image too large** (`IMAGE_TOO_BIG`): Falls through to error exit.

3. **Image download timeout**: `retransThreshold` exceeds `lookup_timeout`, loop exits.

4. **Success**: Boot blocks are returned, system continues booting.

5. **Boot block execution failure**: The `ReBoot` code in `StartBoot.a` explicitly:
   ```asm
   move    #-(49+1),ioRefNum(a0)   ; refnum of the netBoot driver  
   _Close                          ; close the driver
   moveq.l #-1, d0
   move.l  d0,AGBHandle            ; clear AppleTalk dispatch vector
   move.l  d0,AtalkHk2             ; clear LapManager hook
   ```

### For FPGA: AppleTalk Phase Behavior

If the Mac LC is configured for NetBoot in PRAM:
- The `.netBOOT` driver will be in the Drive Queue
- When `FindStartupDevice` tries it, AppleTalk will initialize
- **The boot search will BLOCK** while AppleTalk NBP lookup runs
- After the timeout, `DOREAD` returns an error
- `ReactToFailure` marks the netBoot drive as failed (`BootMask` cleared)
- The search continues with other devices

**If the Mac LC is NOT configured for NetBoot** (or PRAM `BOOT_ENABLE` is 0):
- `DOOPEN` returns `openErr`
- The driver is NOT added to the Drive Queue
- AppleTalk is **never initialized**
- No AppleTalk traffic occurs

**To skip AppleTalk entirely on your FPGA:**
- Ensure PRAM byte for boot flags has `BOOT_ENABLE` (bit in the flags byte) cleared
- Or: ensure the DRVR resource for `.netBOOT` is not present in ROM resources
- Or: don't respond to the `_GetNamedResource` call for `.netBOOT` DRVR

---

## PRAM Layout for Egret/Cuda (256-byte XPRAM)

### Traditional 20-byte PRAM Mapping to XPRAM

The ROM's `ReadPram` routine in `SysUtil.a` reads the traditional 20-byte PRAM from XPRAM:

```
XPRAM 0x10-0x1F  -->  Traditional PRAM bytes 0-15  -->  Low memory $1F8-$207
XPRAM 0x08-0x0B  -->  Traditional PRAM bytes 16-19 -->  Low memory $208-$20B
```

### Serial Port / AppleTalk Configuration

| XPRAM addr | Low memory | PRAM byte | Field | Notes |
|------------|-----------|-----------|-------|-------|
| **0x10** | $1F8 | 0 | `SPValid` | Must be **0xA8** for valid PRAM |
| **0x11** | $1F9 | 1 | `SPATalkA` | AppleTalk node hint (port A) |
| **0x12** | $1FA | 2 | `SPATalkB` | AppleTalk node hint (port B) |
| **0x13** | $1FB | 3 | `SPConfig` | **Port config: hi nibble=A, lo nibble=B** |

`SPConfig` port usage values (per nibble):
- `0` = port not configured (free)
- `1` = **useATalk** (AppleTalk active on this port)
- `2` = useAsync (async serial)
- Others defined in SysEqu.a

### Extended PRAM Validity

| XPRAM addr | Value | Purpose |
|------------|-------|---------|
| **0x0C-0x0F** | `'NuMc'` (0x4E754D63) | Extended PRAM validity signature |

If this signature is missing, `InitUtil` will:
1. Write `'NuMc'` to 0x0C-0x0F
2. Clear ALL extended PRAM from 0x20 through 0xFF, wrapping to 0x00-0x07
3. Write `PRAMInitTbl` defaults to XPRAM 0x76-0x89
4. **Addresses 0x08-0x1F are preserved** (traditional PRAM area)

### NetBoot PRAM (bootVars structure)

| XPRAM addr | bootVars field | Default | Purpose |
|------------|---------------|---------|---------|
| **0x04** | `osType` | 0x00 | Preferred OS (0=Mac OS) |
| **0x05** | `protocol` | 0x00 | Boot protocol (0=default/ATalk, 1=ATalk, 2=IP) |
| **0x06** | `errors` | 0x00 | Last error |
| **0x07** | `flags` | 0x00 | **Bit 7 = BOOT_ENABLE (must be 1 for NetBoot)** |

### PRAM Validity Summary

Your core needs **two** validity signatures:

1. **Traditional PRAM validity**: XPRAM byte **0x10** must be **0xA8**
   - If not 0xA8, InitUtil resets all traditional PRAM to defaults
   
2. **Extended PRAM validity**: XPRAM bytes **0x0C-0x0F** must be **0x4E 0x75 0x4D 0x63** (`'NuMc'`)
   - If not present, InitUtil clears XPRAM 0x20-0xFF and 0x00-0x07, then writes defaults to 0x76-0x89

### Current FPGA Core PRAM Issues

With the current defaults:
- XPRAM 0x10 = 0x02 (labeled "Video depth") -- **WRONG, should be 0xA8 for SPValid**
- XPRAM 0x0C-0x0F = 0x00 -- **Missing 'NuMc' signature**

Because SPValid (0x10) is not 0xA8, `InitUtil` reinitializes the traditional PRAM with safe defaults:
- SPConfig = 0x00 (no ports configured for AppleTalk)
- This means AppleTalk is NOT enabled via SPConfig

Because 'NuMc' (0x0C-0x0F) is missing, `InitUtil` clears extended PRAM including:
- XPRAM 0x04-0x07 (NetBoot bootVars) -> all zeros -> BOOT_ENABLE=0 -> NetBoot disabled

**Conclusion: With your current PRAM defaults, NEITHER AppleTalk NOR NetBoot should be active during boot. If you are seeing a hang that appears to be "AppleTalk initialization", it is likely caused by something else - most probably SCC or VIA hardware behavior.**

### Recommended PRAM Defaults for FPGA Core

```
XPRAM 0x0C = 0x4E  ('N')  -- Extended PRAM validity
XPRAM 0x0D = 0x75  ('u')  
XPRAM 0x0E = 0x4D  ('M')
XPRAM 0x0F = 0x63  ('c')
XPRAM 0x10 = 0xA8         -- SPValid (traditional PRAM validity)
XPRAM 0x11 = 0x00         -- SPATalkA (node hint)
XPRAM 0x12 = 0x00         -- SPATalkB (node hint)
XPRAM 0x13 = 0x00         -- SPConfig (0=no AppleTalk, keep this 0x00)
```

To **enable** AppleTalk later (for MiSTer communication), set:
```
XPRAM 0x13 = 0x01         -- SPConfig port B = useATalk (AppleTalk on printer port)
```
or
```
XPRAM 0x13 = 0x10         -- SPConfig port A = useATalk (AppleTalk on modem port)
```

### SCC Hardware Requirements During Boot

The SCC (Zilog 8530) is accessed during boot at these stages:

1. **InitSCC** (Stage 6b): Writes register 9 with 0xC0 (hardware reset both channels)
   - Reads `SCCRd` base once (synchronization read: `tst.b (a1)`)
   - Writes register select byte and then data to `SCCWr` base
   - **The SCC must accept these writes without hanging the bus**

2. **SetUpTimeK / SCCTime** (Stage 7e): Calibration loop
   ```asm
   movea.l SCCRd,a0         ; SCC read base address
   @loop:
       btst.b  #0,(A0)      ; Read SCC status register 0, test bit 0
       dbra    d0,@loop     ; Count iterations until VIA timer fires
   ```
   - This reads SCC Read Register 0 (RR0) of channel B repeatedly
   - **The SCC must return a valid byte for each read** - it does NOT need to have any specific bit set
   - The loop is timed by VIA Timer 2 and will exit via interrupt regardless of SCC response
   - **If the SCC does not respond to reads (bus hangs), the CPU will freeze here**

3. **Serial driver installation** (Stage 13j): The SERD resource is loaded and its install code runs
   - This typically just installs the driver in the unit table without opening it
   - Should not access SCC hardware

**For the SCC to not cause hangs:**
- It must respond to bus reads at the SCCRd address (return any byte, even 0x00)
- It must accept bus writes at the SCCWr address (acknowledge the write cycle)
- It does NOT need to actually function as a serial controller during boot
- The timing calibration only needs it to complete read cycles; the actual bit values don't matter for boot success

---

## SCC Local Loopback Bug (WR14 = 0x11)

### The Problem

The FPGA SCC implementation is getting stuck because the AppleTalk LocalTalk driver
writes **WR14 = 0x11** to the SCC, which sets:
- **Bit 0** (`BR_Enable` = 0x01): Enable baud rate generator
- **Bit 4** (`LoopBck` = 0x10): Local loopback mode

With local loopback enabled, all transmitted data is internally routed back to the
receiver. The LocalTalk driver uses this as a hardware self-test: it sends test data
and checks if it comes back. On a **real Mac LC with no LocalTalk cable**, the test
would still succeed via loopback, but subsequently the driver would fail to establish
a real network connection (no external responses) and eventually give up.

### Z8530 WR14 Register Definition (from SCCIOPSysEqu.aii)

```
Bit 0: BR_Enable    (0x01) - Enable baud rate generator
Bit 1: BR_SrcRTxC   (0x02) - BR source is RTxC pin
Bit 2: ReqFunc      (0x04) - Request Function
Bit 3: AutoEcho     (0x08) - Auto enable mode
Bit 4: LoopBck      (0x10) - Local loop back mode
Bit 5-7: Command bits (self-clearing):
         Srch_Mode    (0x20) - Enter search mode
         Reset_MCLock (0x40) - Reset missing clock latch
         Disable_DPLL (0x60) - Disable DPLL
         DPLL_BR      (0x80) - DPLL source is BRG
         DPLL_RTxC    (0xA0) - DPLL source is RTxC
         DPLL_FM      (0xC0) - Set DPLL to FM mode
         DPLL_NRZI    (0xE0) - Set DPLL to NRZI mode
```

### What the AppleTalk Code Does

The actual LocalTalk driver code is in the pre-compiled `AppleTalk.ROM.RSRC` binary
(resources: `lmgr` 0, `atlk` 1, `ltlk` 0-7, `DRVR` 9/.MPP, `DRVR` 10/.ATP).
The source is NOT in this repository - it comes from a separate AppleTalk source tree.

The boot-time initialization flow is:
1. `Boot3.a:LoadAppleTalk` loads `lmgr` resource from ROM
2. `lmgr` (NetBootlmgr.a) installs `.MPP` and `.ATP` drivers, then loads `atlk` resource
3. `atlk` (resource ID 1 = built-in LocalTalk) initializes the SCC for SDLC mode
4. The `atlk` install code configures SCC for LocalTalk (230.4 kbps SDLC) and runs a
   self-test using loopback

### Why This Happens During Boot (Not NetBoot Related!)

**Critical insight:** This is NOT the NetBoot path. This is the **normal Boot3.a
AppleTalk loading sequence** that runs AFTER boot blocks are loaded from disk. The
sequence in `Boot3.a:1597` is:

```asm
LoadAppleTalk:
    btst.b  #hwCbAUX,HWCfgFlags    ; are we under A/UX?
    bnz.s   @noALAP
    move.l  #'lmgr',d5             ; load and execute lmgr resource
    clr.w   d6
    clr.w   d3
    bsr     ExecuteFromSystem       ; loads from ROM or System file
@noALAP:
```

This runs unconditionally (unless A/UX) as part of normal system startup. However,
it checks `SPConfig` first (in `Boot3.a:1281-1293`):

```asm
    move.b  SPConfig,d0             ; Get serial port configuration
    and.b   #$0f,d0                 ; Mask off Port B bits
    beq.s   @appleTalkIsActive      ; If 0, AppleTalk IS active (default!)
    cmp.b   #useATalk,d0            ; Configured for AppleTalk?
    beq.s   @appleTalkIsActive      ; Yes
    ; ...set emAppleTalkInactiveOnBoot flag...
```

**IMPORTANT:** `SPConfig` low nibble = 0 means AppleTalk IS considered active!
This is the default state. The `lmgr` and `atlk` code WILL load and initialize.

### The Root Cause in the FPGA

The LocalTalk `atlk` driver:
1. Writes WR14 = 0x11 (BRG enable + local loopback) for self-test
2. Sends test strings through SCC TX
3. Expects to receive them back via internal loopback (this succeeds)
4. Concludes hardware is present
5. Attempts to establish network connection (sends LLAP frames)
6. Because loopback is still active (or the driver proceeds to normal
   operation expecting external responses), it gets stuck in a loop

On a **real Mac LC**, the behavior after the loopback test is:
- The driver clears loopback mode (writes WR14 = 0x01, BRG enable only)
- Configures SCC for external SDLC communication
- Attempts AARP/NBP operations
- If no LocalTalk network is connected, these time out
- AppleTalk initializes in a "disconnected" state and boot continues

### FPGA Fix Options

**Option 1: Do NOT honor WR14 bit 4 (local loopback)**

In your SCC implementation, ignore bit 4 of WR14. Never enable internal loopback.
This means:
- The self-test will FAIL (no data comes back)
- The driver will skip/abort LocalTalk initialization
- Boot continues normally

This is the **simplest and safest fix**. The loopback feature is only used for
self-test and never for actual communication.

**Option 2: Honor loopback but ensure proper CTS/DCD behavior**

On a real Mac LC without a LocalTalk network connected:
- **CTS (Clear To Send)** on the LocalTalk port would be **deasserted** (no cable)
- **DCD (Data Carrier Detect)** would be **deasserted**

After the loopback self-test, the driver checks CTS/DCD status. If no cable is
connected, CTS would be low, causing the driver to recognize no network is present.

If your SCC implementation has CTS permanently asserted (or loopback causes CTS to
appear asserted), the driver thinks a network is connected and keeps trying.

For this option:
- Implement WR14 loopback correctly
- But ensure that after the driver clears loopback mode, CTS reflects the actual
  external hardware state (deasserted = no cable)
- RR0 bit 5 (CTS) should be 0 when no LocalTalk transceiver/cable is connected
- RR0 bit 3 (DCD) should be 0 when no LocalTalk carrier is detected

**Option 3: Set SPConfig to disable AppleTalk**

Set XPRAM byte 0x13 to 0x02 (useAsync) instead of 0x00:
- `SPConfig` low nibble = 2 means Port B configured for async serial
- This means `SPConfig & 0x0F != 0` and `!= useATalk(1)`
- `emAppleTalkInactiveOnBoot` gets set
- AppleTalk is NOT loaded during boot

**BUT**: `SPConfig = 0x00` means "not configured" which the ROM treats as
"AppleTalk is active" (see the `beq.s @appleTalkIsActive` check above).
So the default 0x00 actually ENABLES AppleTalk loading! This is counterintuitive.

To disable AppleTalk via PRAM:
```
XPRAM 0x13 = 0x22    ; Both ports set to useAsync (0x2 << 4 | 0x2)
```

**Recommended approach: Use Option 1 (disable SCC loopback) combined with Option 3
(set SPConfig to 0x22).** Option 1 is the immediate fix; Option 3 prevents AppleTalk
from being loaded at all, saving boot time.

---

## Sad Mac / Critical Error Display

### What Triggers Sad Mac

The Sad Mac (dead Mac) icon is displayed by `CritErr` in `OS/StartMgr/StartFail.a`. It is called via the ROM header's `Critical` vector at offset 0x26:

```asm
Critical    JMP     CritErr     ; [26] jump to critical error handler
```

**CritErr is called when:**
1. POST diagnostics fail in `StartTest1` (RAM test failure, hardware failure)
2. Any code calls the `Critical` vector during early boot (before trap dispatcher is ready)

**CritErr does:**
1. Saves all registers to `SERegs` (debug area)
2. Determines screen parameters (via Slot Manager if available)
3. Switches video to 1-bit mode
4. Fills entire screen with **black**
5. Calculates center position for icon
6. Draws the **Sad Mac icon** (32x32 pixels, white on black)
7. Displays **major error code** (D7) below the icon - 8 hex digits
8. Displays **minor error code** (D6) below that - 8 hex digits
9. Jumps to `TMRestart` (Test Manager) which loops/halts

### Sad Mac Error Codes

The major code (D7) contains:
- High word: Test Manager state information
- Low word: Code indicating which test failed

The minor code (D6) contains additional info (e.g., which RAM chip failed).

### SystemError (_SysError trap)

After the trap dispatcher is initialized, errors go through `_SysError` instead:

**Source:** `OS/StartMgr/StartErr.a:386`

`_SysError` is a trap that can display dialog boxes for recoverable errors or trigger the Sad Mac for fatal errors. Key error codes:

| Code | Constant | Meaning |
|------|----------|---------|
| varies | dsOldSystem | System on disk is too old |
| varies | dsGNLoadFail | Fatal GoNative load error |
| varies | dsNoFPU | FPU not installed dialog |
| varies | dsParityErr | Parity error (code 101) |

### DSErrorHandler

For errors after the full system is initialized, `DSErrorHandler` (referenced in the ROM map at offset 0x280E) manages the error dialog display, potentially allowing the user to restart or continue.

---

## Key ROM Addresses

From `MacLCROM.map` (segment ROMLC at base 0x7F):

### Boot Entry Points
| Symbol | Offset | Description |
|--------|--------|-------------|
| BASEOFROM | 0x0 | ROM base reference |
| STARTINIT1 | 0xB8 | Main init after POST |
| BOOTRETRY | 0x1A6 | Boot retry entry point |
| BOOTME | 0x1D10 | Transfer to boot device search |
| MYBOOT | 0x1D10 | Same as BOOTME |

### Hardware Init
| Symbol | Offset | Description |
|--------|--------|-------------|
| JUMPINTOROM | 0x2E00 | Universal hardware init entry |
| INITVIAS | 0x2E8C | VIA initialization |
| GETHARDWAREINFO | 0x2F18 | Hardware detection |
| CONFIGURERAM | 0xA70 | RAM configuration |
| INITMMUTRAP | 0x3E00 | MMU trap setup |
| INITMMUGLOBALS | 0x3E0C | MMU globals |

### Manager Init
| Symbol | Offset | Description |
|--------|--------|-------------|
| INITMEMMGR | 0x11A0 | Memory Manager |
| INITRSRCMGR | 0x11D0 | Resource Manager |
| INITIOMGR | 0x10F0 | I/O Manager |
| INITSLOTS | 0x1210 | Slot Manager |
| INITEVENTS | 0x22E0 | Event Manager |
| INITCRSRMGR | 0x1060 | Cursor Manager |

### Boot Device Search
| Symbol | Offset | Description |
|--------|--------|-------------|
| FINDSTARTUPDEVICE | 0x1350 | Main search routine |
| EMBARKONSEARCH | 0x1430 | Initialize search state |
| LOADDRIVERS | 0x1560 | Load standard drivers |
| LOADSLOTDRVRS | 0x14F0 | Load slot drivers |
| PLANSTRATEGY | 0x1590 | Search strategy |
| FINDNEXTCANDIDATE | 0x15A0 | Next drive queue entry |
| SELECTDEVICE | 0x15D0 | Set up device params |
| REACTTOFAILURE | 0x1620 | Handle boot failure |
| HAPPYMAC | 0x1750 | Display Happy Mac icon |
| OPENNETBOOTPATCH | 0x1250 | NetBoot open patch |
| CLOSENETBOOTPATCH | 0x130A | NetBoot close patch |

### Error Handling
| Symbol | Offset | Description |
|--------|--------|-------------|
| CRITERR | 0x2310 | Critical error -> Sad Mac |
| PUTICON | 0x2524 | Plot compressed icon |
| SYSERRINIT | 0x25F0 | Exception vector setup |
| SYSTEMERROR | 0x2720 | _SysError trap handler |
| DSERRORHANDLER | 0x280E | DS error dialog handler |

---

## Source File Reference

All paths relative to: `base/SuperMarioProj.1994-02-09/`

### Boot Sequence (in execution order)
| File | Purpose |
|------|---------|
| `OS/StartMgr/StartTop.a` | ROM base reference (BaseOfROM) |
| `OS/StartMgr/StartInit.a` | Main ROM init: reset vectors through BootMe |
| `OS/StartMgr/Universal.a` | Hardware detection (JumpIntoROM, GetHardwareInfo) |
| `OS/StartMgr/USTStartup.a` | POST diagnostics (StartTest1) |
| `OS/StartMgr/StartBoot.a` | BootMe, boot block execution, InitSys7Toolbox |
| `OS/StartMgr/StartSearch.a` | FindStartupDevice, boot device search loop |
| `OS/StartMgr/StartFail.a` | CritErr, Sad Mac icon display |
| `OS/StartMgr/StartErr.a` | SystemError, _SysError trap, exception handlers |
| `OS/StartMgr/StartAlert.a` | Boot-time alert dialogs |
| `OS/StartMgr/Boot1.a` | Disk boot block code (phase 1) |
| `OS/StartMgr/Boot2.a` | System file location (phase 2) |
| `OS/StartMgr/Boot3.a` | Manager init from System file (phase 3) |

### NetBoot / AppleTalk
| File | Purpose |
|------|---------|
| `OS/NetBoot/NetBoot.c` | Boot management driver (DOOPEN, DOREAD, DOCLOSE) |
| `OS/NetBoot/NetBoot.a` | Assembly glue for NetBoot driver |
| `OS/NetBoot/GetServer.c` | AppleTalk boot protocol (get_image, find_server) |
| `OS/NetBoot/ATBoot.c` | AppleTalk Boot Protocol driver |
| `OS/NetBoot/ATBootEqu.h` | Boot protocol constants and structures |
| `OS/NetBoot/NetBoot.h` | NetBoot driver structures and constants |

### Build Configuration
| File | Purpose |
|------|---------|
| `Make/Universal.make` | Mac LC ROM build configuration (hasNetBoot = TRUE) |
| `Make/FeatureList` | Feature flags including hasNetBoot |

### ROM Map
| File | Purpose |
|------|---------|
| `bin/MPW-3.2.3/ROM Maps/MacLCROM.map` | Complete symbol-to-offset mapping |

---

## Summary for FPGA Development

### Critical Path to Display

The minimum path from power-on to any screen output:

1. CPU fetches reset vector from ROM (Stage 1-2)
2. Hardware detection and VIA init (Stage 3-5)
3. RAM detected and MMU configured (Stage 5e-5h)
4. Slot Manager inits video cards (Stage 11a) - **first gray screen**
5. DrawBeepScreen (Stage 15b) - **gray pattern**
6. FindStartupDevice search loop (Stage 18) - **blinking ? floppy icon**
7. Success: **Happy Mac** / Failure: stays in search loop

### The Stuck-at-AppleTalk Problem

If your FPGA is stuck at AppleTalk initialization, the most likely cause is:

1. **PRAM has BOOT_ENABLE set for NetBoot** - The `.netBOOT` driver opens and adds itself to the drive queue
2. **`DOREAD` is called** during `FindStartupDevice` and it calls `MPPOpen()` + `DDPOpenSocket()` + `find_server()`
3. **`find_server` does NBP lookups** which involve sending packets on the network and waiting for responses
4. The system is **blocking in the `get_image()` loop** waiting for NBP replies or image data that will never come

### Fix Options

1. **Clear PRAM NetBoot flag**: Ensure the PRAM byte that controls `BOOT_ENABLE` is 0
2. **Remove .netBOOT DRVR resource**: If it's not in ROM resources, it can't be loaded
3. **Respond to SCC/network appropriately**: If the `.ATBOOT` driver opens the SCC for AppleTalk, make sure the SCC returns appropriate status so the driver times out quickly
4. **Stub out AppleTalk response**: Make `MPPOpen()` return an error, which will cause `get_image()` to return immediately
