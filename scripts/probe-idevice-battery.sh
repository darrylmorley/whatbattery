#!/usr/bin/env bash
# Feasibility probe: read a tethered/paired iPhone or iPad's battery from this Mac,
# the coconutBattery "iPhone/iPad" model. The Mac talks to the device over the
# lockdown diagnostics relay (USB or WiFi); no app on the device, just paired/trusted.
#
# Goal: confirm which AppleSmartBattery fields come back so we know whether an
# iDevice battery view is buildable at parity. Needs pymobiledevice3 + the device
# unlocked and trusted.
#
# Usage: scripts/probe-idevice-battery.sh
set -euo pipefail

if ! command -v pymobiledevice3 >/dev/null 2>&1; then
    echo "ERROR: pymobiledevice3 not found (pip install pymobiledevice3)." >&2
    exit 1
fi

echo "=== Connected devices (USB + network) ==="
pymobiledevice3 usbmux list 2>/dev/null || true
echo

UDID="$(idevice_id -l 2>/dev/null | head -n1 || true)"
if [[ -z "${UDID}" ]]; then
    UDID="$(idevice_id -n 2>/dev/null | head -n1 || true)"
fi
if [[ -z "${UDID}" ]]; then
    echo "No device visible. Plug in over a DATA cable and tap Trust, or pair over WiFi." >&2
    exit 1
fi
echo "Using device: ${UDID}"
echo

echo "=== Device identity (mobilegestalt) ==="
pymobiledevice3 diagnostics mobilegestalt \
    --key ProductType --key ProductVersion --key DeviceName \
    --udid "${UDID}" 2>/dev/null || echo "(mobilegestalt read failed)"
echo

# The battery fields live in the device IORegistry under the AppleSmartBattery
# class, the same node we read on the Mac. These are the parity-critical keys.
echo "=== AppleSmartBattery (IORegistry diagnostics relay) ==="
pymobiledevice3 diagnostics ioregistry \
    --ioclass AppleSmartBattery \
    --udid "${UDID}" 2>/dev/null \
  || pymobiledevice3 diagnostics ioregistry \
       --name AppleSmartBattery \
       --udid "${UDID}" 2>/dev/null \
  || echo "(AppleSmartBattery IORegistry read failed; try: pymobiledevice3 diagnostics ioregistry --udid ${UDID})"
echo

echo "Parity fields to confirm in the output above:"
echo "  DesignCapacity, AppleRawMaxCapacity / NominalChargeCapacity  -> Health %"
echo "  CycleCount                                                   -> Cycles"
echo "  CurrentCapacity / AppleRawCurrentCapacity                    -> Charge %"
echo "  Temperature                                                  -> Temp"
