# WhatBattery

A macOS battery health and live power tool. Menu bar app + CLI. Shows design vs
full-charge capacity, wear %, cycle count, temperature, voltage, live
charge/discharge watts, and the connected power adapter.

Apple Silicon, macOS 14+. Part of the "What*" family (WhatCable, WhatPort).

> Status: early scaffold. The CLI works against real hardware today. The menu
> bar app, widget, Pro plugins, and distribution are specced but not yet built.
> See [SPEC.md](SPEC.md).

## Try it

```bash
swift build
swift run whatbattery          # one-shot summary
swift run whatbattery --json   # machine-readable snapshot
swift run whatbattery --watch  # live, refreshes every 2s
swift test                     # 21 tests
```

Example:

```
WhatBattery 0.1.0-dev

Model         Mac17,2
Health        100% (6,221 / 6,249 mAh)
Charge        100%, fully charged
Cycles        42 (design 1000)
Temperature   30.1 C
Power         0.0 W  (100W pd charger)
Voltage       13.23 V
```

## Layout

```
WhatBatteryCore            Pure Swift. Models, health math, formatters. No IOKit.
WhatBatteryDarwinBackend   IOKit AppleSmartBattery reader + SMC reader.
WhatBatteryAppKit          Plugin registry (the seam Pro features plug into).
WhatBatteryCLI             The `whatbattery` command.
```

## Where the data comes from

- **Battery health** (capacity, cycles, voltage, temperature, adapter) comes
  from the IOKit `AppleSmartBattery` service.
- **Live power** (discharge watts, DC-in) comes from the SMC: `PPBR` for the
  live battery rail, `VD0R/ID0R/PDTR` for DC-in.

Both readers are focused copies of the battery code already shipping in
WhatCable.

## Not doing iOS

A sandboxed iOS app cannot read cycle count, capacity, voltage, or temperature
(only `UIDevice.batteryLevel` in 5% steps). The "read a tethered iPhone from the
Mac" path needs private, version-fragile diagnostic APIs and mostly duplicates
what the Mac already reports about itself. Mac only, by decision. See SPEC.md.
