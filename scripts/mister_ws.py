#!/usr/bin/env python3
"""Send kbd:* commands to the MiSTer Remote websocket.

Usage:
    python scripts/mister_ws.py up down confirm        # send each in order, with default delay
    python scripts/mister_ws.py --delay 0.6 osd        # custom delay before close
    python scripts/mister_ws.py --host my-mister.local osd

Each positional argument is sent as "kbd:<arg>". Special forms:
    sleep:0.5   -> wait that many seconds

The default host/port come from the MISTER_HOST / MISTER_HTTP_PORT
environment variables (set those in scripts/local.env or your shell
profile). Falls back to MiSTer.local : 8182 if neither is set.
"""
import asyncio, sys, os, argparse, json
import websockets

async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host",
                    default=os.environ.get("MISTER_HOST", "MiSTer.local"))
    ap.add_argument("--port", type=int,
                    default=int(os.environ.get("MISTER_HTTP_PORT", "8182")))
    ap.add_argument("--delay", type=float, default=0.35,
                    help="delay between key sends (seconds)")
    ap.add_argument("keys", nargs="+")
    args = ap.parse_args()

    url = f"ws://{args.host}:{args.port}/api/ws"
    async with websockets.connect(url) as ws:
        # drain a couple of initial server messages
        try:
            for _ in range(2):
                msg = await asyncio.wait_for(ws.recv(), timeout=0.5)
                print(f"<< {msg}")
        except asyncio.TimeoutError:
            pass

        for k in args.keys:
            if k.startswith("sleep:"):
                await asyncio.sleep(float(k.split(":", 1)[1]))
                continue
            payload = f"kbd:{k}"
            print(f">> {payload}")
            await ws.send(payload)
            await asyncio.sleep(args.delay)

        # drain any final replies
        try:
            for _ in range(3):
                msg = await asyncio.wait_for(ws.recv(), timeout=0.3)
                print(f"<< {msg}")
        except asyncio.TimeoutError:
            pass

if __name__ == "__main__":
    asyncio.run(main())
