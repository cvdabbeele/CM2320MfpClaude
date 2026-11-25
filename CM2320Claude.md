# CM2320Claude: History

**Date:** 2026-11-25 (session start)
**Printer:** HP Color LaserJet CM2320fxi MFP, macOS, Intel Mac

Note: the request named the history file CM2330Claude.md. This file is CM2320Claude.md, to match the printer model and driver name. Rename it if the typo was intentional.

## 1. Current setup (as found)

- Queue `HP_Color_LaserJet_CM2320fxi_MFP__XXXXXX_`: device `dnssd://...pdl-datastream` (raw PDL on the network). Make-and-model reported as "Generic PostScript Printer".
- Queue `HP_Color_LaserJet_CM2320fxi_MFP__XXXXXX__2`: PPD "HP LaserJet Series PCL 4/5" (`cupsFilter rastertohp`), device `dnssd://...RAW`.
- Both PPDs live in `/etc/cups/ppd/`. No HP driver package is installed (`/Library/Printers/PPDs` is empty).
- Missing features reported by the user: recto/verso, tray (bin) selection, and others.

## 2. Printer capabilities (read from the device over IPP, no download)

Source: `ipptool get-printer-attributes` against the local CUPS queue (`work/get-attrs.test`).

- `document-format-supported`: application/pdf, application/postscript, application/vnd.cups-raster, application/vnd.cups-raw and others. The device accepts PostScript and PDF.
- `sides-supported`: one-sided, two-sided-long-edge, two-sided-short-edge (duplex is available).
- `print-color-mode-supported`: monochrome, color.
- `media-source-supported`: auto, top, manual. The optional third tray is not reported by the IPP attributes.
- `media-supported`: Letter, Legal, Executive, Ledger, A3, A4, A5, B5, C5, DL, Monarch, No. 10, and others.
- `output-bin-supported`: face-down only.
- `finishings-supported`: none.

## 3. Physical inputs (from the photo)

- Tray 1: front multipurpose tray.
- Tray 2: 250-sheet cassette.
- Tray 3: lower optional 500-sheet tray.
- ADF on top. Duplex unit installed (the "fxi" model).

Tray names in the new driver are still to be decided (see open questions).

## 4. Driver search

- HP support page `support.hp.com/.../3597338/`: not reachable from this machine (curl returned no connection). A subagent also timed out on both regional pages.
- `printerdrivers.com/hp-color-laserjet-cm2320fxi-mfp-driver/`: reachable. It lists driver packages of about 22 MB and about 318-320 MB, with no clear macOS-specific entry in the page text. Third-party site, not official. Not downloaded.
- Web search: HP community posts say macOS print drivers for this series came through Apple Software Update, and that the older full-feature Mac package was for Mac OS X 10.7. No newer full-feature macOS package was confirmed.

Decision pending: the most complete driver could not be confirmed. No third-party installer has been downloaded (untrusted source; needs the user's OK).

## 4b. Update: HP's own macOS package is already on this Mac

Correction to section 4: an HP macOS package for this printer is already in `~/Downloads`:

- `HP-Color-LaserJet-CM2320-MFP-series_v1.5.0.dmg` (10.0 MB, July 2025)
- `HP_Color_LaserJet_CM2320_MFP_series_v1_4_0.dmg` (10.3 MB, August)

Both are mounted read-only and analysed in `work/` (not committed). Contents of v1.5.0:

- `hpPSDriver.pkg`: HP PostScript driver. Includes `hpPostProcessing` (CUPS filter, version 18.2.3) and `hpPostScriptPDE.plugin` (print dialog UI).
- `hpPSDriverSupport.mpkg`: PPDs for macOS 10.5 and 10.6, plus ICC profiles.
- `HP LaserJet CM2320 Support.pkg`: device descriptions for the n, nf and fxi models.
- `HP LaserJet Core.pkg`: scan and fax tools.

The PPD `HP Color LaserJet CM2320 MFP Series` (FileVersion 18.2) has the options the generic queue lacks:

- Duplex (`*Duplex`): Off, Long-Edge, Short-Edge. The default is Off.
- Paper source (`*InputSlot`): Tray 1, Tray 2, Tray 3, Tray 1 (manual). Tray 3 needs the 500-sheet feeder option.
- Duplex unit option (`HPOption_Duplexer`).
- Manual duplex with reinsertion guide, booklet printing, media type, colour and halftone controls, and watermark.
- Filter: `cupsFilter application/vnd.cups-postscript -> /Library/Printers/hp/filter/hpPostProcessing.bundle/.../hpPostProcessing`.

Control path: the print dialog (`hpPostScriptPDE`) writes PPD option values; CUPS passes them to `hpPostProcessing` as options, which applies the booklet and duplex logic before the PostScript goes to the printer.

Not yet done: nothing installed, and no change to the printer queues.

Note on licensing: the HP files are HP's copyrighted material. They should not go into a public GitHub repo. The repo would hold only our own scripts and documentation.

## 4c. Driver files moved, HP installer check, manual install (2026-11-25 22:10)

Moved from `~/Downloads` to `work/drivers/` (not committed):

- `mac/HP-Color-LaserJet-CM2320-MFP-series_v1.5.0.dmg`, `mac/HP_Color_LaserJet_CM2320_MFP_series_v1_4_0.dmg`
- `mac/HP Color LaserJet CM2320 MFP series (v1.5.0 copy, 2011)`: an older copy of the v1.5.0 installer volume.
- `windows/CM2320series-full-solution-AM-EMEA1-v3.1.exe` (336 MB, Windows 10 Full Solution)
- `windows/upd-pcl6-win11-x64-8.2.0.26819.zip` (HP Universal Print Driver PCL6, Windows 11)

Left in `~/Downloads` (not drivers): `CM1310_CM2320_MFP_Series_FW_Update-20140625.dmg` (firmware) and `cm2320 user manual.pdf`.

**HP installer does not work on macOS 26.** The install checks in `hpPSDriver.pkg` and `hpPSDriverPPDs-10.6.pkg` use `SYSTEM_MAJOR_VERSION -eq 10`, so on macOS 26.5.2 they exit 65 and the PostScript driver and PPD are skipped. The installer is also an old bundle-style `.mpkg`.

**HP's filter does run on macOS 26.** `hpPostProcessing` is a universal binary (ppc, i386, x86_64) and is unsigned. It links Carbon, Cocoa, libcups, libstdc++ and weak-links `HPDeviceModel.framework` (not needed). It starts and prints its usage line. The fax backend is ppc/i386 only and cannot run.

Dry-run test (no install), with HP's PPD through `cupsfilter`, then `hpPostProcessing`:

| Option | PostScript sent to printer |
|---|---|
| Duplex=DuplexNoTumble | `<</Duplex true /Tumble false>> setpagedevice` |
| Duplex=DuplexTumble | `<</Duplex true /Tumble true>> setpagedevice` |
| InputSlot=Tray1 | `<</MediaPosition 3 /ManualFeed false>> setpagedevice` |
| InputSlot=Tray2 | `<</MediaPosition 0 /ManualFeed false>> setpagedevice` |
| InputSlot=Tray3 | `<</MediaPosition 1 /ManualFeed false>> setpagedevice` |
| InputSlot=Tray1_Man | `<</MediaPosition 3 /ManualFeed true>> setpagedevice` |
| HPBookletFilter=True | Booklet processor runs in `hpPostProcessing` (exit 0) |

Manual install script: `scripts/install_hp_v150.sh` (run with sudo). It installs the filter bundle, ICC profiles, icon and gzipped PPD into `/Library/Printers`, and adds the queue `HP_CM2320fxi_HPv150` (same dnssd URI as the existing queue, duplex unit and Tray 3 installed, A4). It skips the print dialog plugin (PDE), scan, fax and utilities. Checked: `bash -n` passes; without sudo it stops with an error. Not yet run.

## 4c-2. Install verified (2026-11-25 22:17)

The user ran `sudo scripts/install_hp_v150.sh`. Checked:

- Files present in `/Library/Printers/hp/` (filter bundle, 3 ICC profiles, icon) and the PPD in `/Library/Printers/PPDs/Contents/Resources/`, all owned by root:wheel.
- Queue `HP_CM2320fxi_HPv150` is idle and enabled, with the dnssd URI. Options: Tray 3 = True, Duplex Unit = True, PageSize = A4, InputSlot Tray1/Tray2/Tray3/Tray1_Man, Duplex None/Long/Short, booklet, media types.
- `cupsfilter -e` with the installed PPD runs `hpPostProcessing` from `/Library/Printers/hp/filter/` ("permissions OK", "exited with no errors"). The output has `MediaPosition 1` (Tray 3) and `Duplex true /Tumble false`.
- Real job 638: 2 pages, Tray 2, long-edge duplex, A4. CUPS reports it completed. Confirmed by the user: one sheet from Tray 2, printed on both sides. Duplex and tray selection work under macOS 26 with HP's driver.

## 4d. Windows Full Solution analysis (2026-11-25 22:15)

Extracted with `bsdtar` into `work/winfull/` (nothing executed). The x64 printer driver is in `hppdp612.cab`.

- Driver type: Microsoft Unidrv with HP plug-in DLLs. Model file `hpc2320a.gpd` (GPDFileVersion 072.5300, DriverVer 10/14/2009, 61.093.01.59), PCL 6 (PCL XL).
- Features: Duplex (NONE, VERTICAL, HORIZONTAL), InputBin (PrinterSelect, ManualFeed, Tray1, Tray2, Tray3_500), Tray3 and DuplexUnit installable options, ManualDuplex, MediaType, ColorMode, Collate, AlternateLetterHead, HPOrientRotate180, TextAsBlack, Resolution/FastRes, HP ColorSmart (edge control, halftone, neutral grays).
- Control path: the GPD does not contain the printer commands. Each option calls `*CallbackID` (for example Duplex 202/203, InputBin 90-94) into HP's DLL (`hpc6r093.dll`), which writes binary PCL XL. Reading those commands would need reverse-engineering the DLL.
- Conclusion: the Mac PPD already covers duplex, trays, Tray 3, duplex unit, manual duplex, media type and colour controls, with readable PostScript. Features only in the Windows driver: alternate letterhead mode, rotate 180, text as black. Collate is handled by the macOS print dialog. These three are candidates for CM2320MfpClaude.

## 4e. CM2320MfpClaude built (2026-11-25 22:50)

The user asked for a new driver with all printer features. The driver is written from scratch and contains no HP files, so it can be published.

Design:

- `ppd/CM2320MfpClaude.ppd`: our own PPD. Device features use `setpagedevice` and the printer's ColorSmart operators, with the values found in section 4c (for example MediaPosition 3/0/1 for Tray 1/2/3). Only sizes up to Legal (the printer's maximum); custom size 216-612 x 360-1008 pt. `cupstestppd`: PASS (two warnings about 16K size names).
- `cupsPreFilter` (application/pdf): `cm2320claude-prefilter`, Swift + CoreGraphics, universal binary. Checked first with a probe script that CUPS on macOS 26 runs a PDF pre-filter for both PDF and text jobs.
- Pre-filter features: booklet (left/right binding, pages padded to a multiple of 4, spread turned 90 degrees on a portrait sheet), letterhead mode (blank backs only when the user prints single-sided), rotate 180, watermark (6 texts plus `CMWmCustomText`, all/first page, 3 intensities). Pass-through when no option is on or the input is not a PDF.
- PPD code forces duplex where the pre-filter needs it: `CMBooklet` sets `/Duplex true /Tumble true`, `CMLetterhead` sets `/Duplex true` (OrderDependency 60, after Duplex at 50).
- Not implemented (documented in README): scan/fax, manual duplex, text as black, first page from another tray.

Tests (`scripts/test.sh`): 102 unit checks (including pixel checks of booklet halves, page orientation, rotation, watermark and blank letterhead backs), 10 integration runs of the filter binary, `cupstestppd`. Line coverage of `src/`: 98.4 %. Dry run with `cupsfilter -e` and the real PPD: booklet 6 pages to 4 sides with short-edge duplex after `Duplex None`; letterhead 6 to 12 pages; Tray 3, grayscale, heavy media and long-edge duplex commands present.

Problems met: `rasterize` test helper read freed bitmap memory (segfault), fixed by copying the pixels; CoreGraphics writes one blank page for a PDF closed without pages; `python3` hung at start-up (process state U, cannot be killed), so the scripts use perl instead; zsh does not split unquoted variables (use `${=var}`).

Repository: `git init` done.

Installed by the user with `sudo ./scripts/install_cm2320mfpclaude.sh` (22:47). Queue `CM2320MfpClaude` is enabled, uses the existing dnssd URI, Tray 3 and duplex unit on, A4 default, `cupsPreFilter` path correct.

Real test prints (22:48), both completed in CUPS, no new entries in `/var/log/cups/error_log`:

- Job 639: 8-page PDF, `CMBooklet=LeftBinding CMWmText=Draft InputSlot=Tray2`. Expected: 2 sheets from Tray 2; sheet 1 front pages 8|1, back 2|7; sheet 2 front 6|3, back 4|5; DRAFT on every page.
- Job 640: 1 text page, `InputSlot=Tray3 ColorModel=Gray Duplex=None`. Expected: 1 sheet from Tray 3.

Paper result, confirmed by the user: both correct (booklet order, fold, DRAFT watermark; one sheet from Tray 3). CM2320MfpClaude works end to end inside cupsd on macOS 26.5.2, including the pre-filter.

## 4f. Repository prepared for GitHub (2026-11-25 23:00)

- Scanned all files to be committed for personal data and secrets: user name, e-mail, printer serial suffix, user paths, IP addresses, passwords, tokens, keys.
- Removed the printer's Bonjour serial suffix from this file. `scripts/install_hp_v150.sh` no longer has a hard-coded device URI: it takes the URI as argument or reuses an existing CM2320 queue's URI, like the CM2320MfpClaude install script.
- Replaced a personal name in a test string.
- Kept: example address `socket://192.168.1.50:9100` (placeholder) in README and install script.
- Not committed (`.gitignore`, local only): `work/` (HP and Windows driver files, builds, test output), `docs/`, `.backup/`, photos.
- LICENSE copyright holder: "CM2320MfpClaude contributors" (can be changed).
- First local commit made. No remote, nothing pushed.

## 5. Plan (proposed)

1. Build a CUPS PPD `CM2320Claude.ppd` for the device, using its own PostScript/PDF support (no proprietary HP filter needed). Expose: duplex (long/short edge), color/mono, paper size, input tray, and copies.
2. Add the missing features through a CUPS filter where possible (for example N-up or booklet), if the tools are available on this Mac.
3. Install it as a new queue `CM2320Claude` and test: one-sided, duplex, tray selection.
4. Keep this file updated after each step.

## 6. Open questions

- Use the official HP package? If you download it from HP in your browser and tell me the file path, I can analyze it locally.
- Tray names: keep "Tray 1 / Tray 2 / Tray 3", or use custom names?
- History file name: keep `CM2320Claude.md` (this file), or rename to `CM2330Claude.md`?
