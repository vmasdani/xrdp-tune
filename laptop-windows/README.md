# Lean Windows on an old gaming laptop

`optimize-laptop.bat` tunes Windows 10 or 11 on an old laptop for light gaming and everyday
use: an Intel GPU of the Haswell era with a small NVIDIA chip (here a GeForce 820M), 4 to 8 GB
of RAM, possibly a hard disk. It cuts background load and redraws. Sound, webcam, Bluetooth,
Wi-Fi, printing, Defender and Windows Update keep working: no services are removed, and
Windows Search goes off only on a hard disk. For Linux, use WSL 2.

Double-click it (it asks for administrator rights), read the `[ OK ]` / `[SKIP]` lines, then
restart Windows. The settings at the top of the file control Windows Search, the power plan
and the WSL memory cap. Same style as the small-VM script in guacamole-session-tools.

## Why Windows here and not Linux

The GeForce 820M is a Fermi chip (GF117), not Kepler, despite the 800-series name. On Linux
it has no usable driver. NVIDIA's last driver for Fermi is the 390 series, which no longer
builds on current kernels and is not packaged for Ubuntu 24.04 or later. Nouveau cannot raise
Fermi's clocks. Fermi also has no Vulkan on any driver, and Counter-Strike 2 on Linux runs
only on Vulkan (Kepler or newer, or AMD GCN). On Linux, CS2 does not start on this laptop.

On Windows, the 820M has a real driver (391.35) with DirectX 11, so CS2 starts, and Fallout:
New Vegas runs natively.

## Drivers

- **Intel graphics:** from Windows Update.
- **NVIDIA 820M:** 391.35, the last Fermi driver, for Windows 10 (on Windows Update as
  23.21.13.9135). Its installer refuses Windows 11. People report that the driver from
  Windows Update, or Device Manager > Update driver > Have disk with the extracted
  installer's INF, still works there. Not tested here.
- Check the chip first: Device Manager > Display adapters > NVIDIA > Details > Hardware Ids.
  A GF117 820M has device ID `1140`.

## Which GPU to use per game

The 820M is entry level, about a GeForce GT 720M or Intel Iris 5100, held back by a 64-bit
memory bus. At least one owner measured an Intel HD 4400 beating it (28 fps against 15 in
NFS: Hot Pursuit). Try each game on both: Settings > Display > Graphics (Windows 10:
Graphics settings), add the game's .exe, then choose "Power saving" (Intel) or "High
performance" (NVIDIA). On this old Optimus chip, the NVIDIA Control Panel's per-program
"Preferred graphics processor" may be the setting that takes effect.

- **Fallout: New Vegas (DirectX 9, 2010):** fine on either GPU. A 4 GB patch (FNV 4GB
  Patcher) prevents out-of-memory crashes with mods.
- **Counter-Strike 2:** expect low frame rates. Below Valve's recommended spec, and no
  benchmarks for this chip were found. Lowest preset, 1280x720 or lower, FSR on.

## Memory compression ("MMAgent is bad for games")

`optimize-laptop.bat` keeps memory compression on, on purpose. Compression works only when
RAM runs short. It then squeezes idle pages in RAM instead of writing them to the page file.
With plenty of free RAM (a 16 to 32 GB gaming desktop) it barely works at all, so turning it
off there changes almost nothing; that is where the advice comes from. On a 4 to 8 GB laptop
the alternative to compressing a page is paging it to disk: milliseconds per page on a hard
disk, against microseconds of CPU for decompression. That costs far more stutter. Turn it off
only with RAM to spare, and measure: `Disable-MMAgent -MemoryCompression`, then restart.

## Windows version

Windows 10 22H2 support ended in October 2025 for consumers, and the consumer Extended
Security Updates year ended in October 2026. Windows 11 lists Haswell CPUs as unsupported,
but it installs with the hardware check bypassed (for example a Rufus-made USB) and runs
fine. Fewer preinstalled apps also means less background load, whichever version you use.

## What the script does not do

- Remove apps, services or Defender: those tweaks break updates and features for little gain.
- Change the GPU per game: the right one depends on the game (see above).
- Hibernation and Fast Startup stay on, which suits a laptop.
