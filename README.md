# CM2320MfpClaude

**Date:** 2026-11-25 22:48

A macOS printer driver for the **HP Color LaserJet CM2320 MFP series** (CM2320n, CM2320nf, CM2320fxi). It works on current macOS, on Intel and Apple Silicon Macs.

HP's last macOS driver for this printer (v1.5.0, 2011) does not install on macOS 11 or later. The generic driver that macOS picks has no tray selection, no duplex unit option and no colour controls. CM2320MfpClaude is a new driver written from scratch. It contains no HP files.

## How it works

The printer understands PostScript level 3. The driver has two parts:

1. **`ppd/CM2320MfpClaude.ppd`**: a PostScript printer description. It switches the printer's own features (paper size, trays, duplex, media type, colour) with standard `setpagedevice` commands and the printer's ColorSmart operators.
2. **`cm2320claude-prefilter`**: a small CUPS pre-filter (Swift, CoreGraphics). It changes the PDF before CUPS converts it to PostScript, for features the printer cannot do itself: booklet, watermark, rotate 180 degrees and letterhead mode. When none of these options is on, it passes the job through unchanged.

## Features

| Feature | Options | Done by |
|---|---|---|
| Paper size | Letter, Legal, Executive, 8.5x13, A4, A5, A6, B5 (JIS), 16K (3 sizes), 4x6, 5x8, 10x15 cm, postcards, envelopes (#10, Monarch, B5, C5, DL), custom size 76x127 mm to 216x356 mm | Printer |
| Paper source | Automatic, Tray 1, Tray 2, Tray 3, Tray 1 manual feed | Printer |
| Two-sided | Off, long-edge, short-edge | Printer (duplex unit) |
| Installable options | Duplex unit, Tray 3 | Driver settings |
| Media type | 33 types (plain, light, heavy, glossy, HP papers, labels, envelopes, transparency, letterhead, preprinted, recycled, and more) | Printer |
| Colour mode | Colour (ImageREt 3600), grayscale | Printer |
| Colour options | Edge control (off, light, normal, maximum); halftone, RGB colour and neutral grays, each separately for text, graphics and photos | Printer (ColorSmart) |
| Booklet | Left or right binding; two pages per sheet side, pages put in booklet order, short-edge duplex set automatically | Pre-filter |
| Letterhead mode | Single-sided jobs also go through the duplex path, so preprinted paper is loaded the same way for single- and two-sided jobs | Pre-filter |
| Rotate 180 degrees | For envelopes or paper loaded the other way round | Pre-filter |
| Watermark | DRAFT, CONFIDENTIAL, COPY, SAMPLE, INTERNAL, DO NOT COPY; all pages or first page only; light, medium or dark. Custom text from the command line: `lp -o CMWmCustomText="My text"` | Pre-filter |
| Supply levels | Toner levels in the macOS printer queue window | CUPS (SNMP) |

The macOS print dialog itself already provides copies, collate, pages per sheet, page order, odd/even pages, scaling and mirror. The driver does not repeat these.

Not included:

- **Scan and fax.** These need HP's software, which does not run on current macOS. For scanning, use the printer's own buttons (scan to memory card) or its web page.
- **Manual duplex.** The fxi model has a duplex unit, so it is not needed. For the n and nf models, use the print dialog: print the odd pages, put the stack back in the tray, then print the even pages.
- **"Text as black" and "first page from another tray".** The printer has no command for the first one. The second needs a different paper source per page, which a PostScript pre-filter on PDF cannot set.

## Requirements

- macOS 12 or later (tested on macOS 26.5.2, Intel).
- Command Line Tools for Xcode (`xcode-select --install`), to build the pre-filter.
- The printer on the network or USB.

## Build, test, install

```bash
./scripts/build.sh
```

```bash
./scripts/test.sh
```

```bash
sudo ./scripts/install_cm2320mfpclaude.sh
```

The install script reuses the device address of an existing CM2320 queue. You can also give the address yourself (find it with `lpinfo -v`):

```bash
sudo ./scripts/install_cm2320mfpclaude.sh socket://192.168.1.50:9100
```

Optional settings: `TRAY3=False` (no Tray 3), `DUPLEXER=False` (no duplex unit), `PAGESIZE=Letter`, `QUEUE=name`.

To remove the driver:

```bash
sudo ./scripts/uninstall_cm2320mfpclaude.sh
```

## Using it

Choose the printer "HP Color LaserJet CM2320 MFP (CM2320MfpClaude)". In the print dialog, open the printer options section. The paper source, two-sided and media type settings are there, plus the groups "Color Options" and "Layout Extras".

From the command line, for example:

```bash
lp -d CM2320MfpClaude -o InputSlot=Tray3 -o Duplex=DuplexNoTumble document.pdf
```

```bash
lp -d CM2320MfpClaude -o CMBooklet=LeftBinding -o PageSize=A4 document.pdf
```

List all options with `lpoptions -p CM2320MfpClaude -l`.

## Project layout

| Path | Content |
|---|---|
| `ppd/CM2320MfpClaude.ppd` | Printer description |
| `src/CM2320Core.swift` | Pre-filter logic: options, page order, rendering |
| `src/main.swift` | Pre-filter entry point (CUPS interface) |
| `tests/CoreTests.swift` | Unit tests (pixel checks of booklet, rotation, watermark, letterhead) |
| `scripts/` | Build, test, install and uninstall scripts |
| `scripts/install_hp_v150.sh` | Optional: installs the PostScript part of HP's own v1.5.0 driver by hand, from your own copy of HP's installer. Not needed for CM2320MfpClaude. |
| `CM2320Claude.md` | Development history |

## License

MIT, see `LICENSE`. HP and Color LaserJet are trademarks of HP Inc. This project is not affiliated with HP.
