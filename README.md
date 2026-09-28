# hplip-arm64: HP DeskJet 5900 series driver for Apple silicon Macs

This is a native **arm64** build of HP's open-source `hpcups` CUPS filter
(from [HPLIP](https://developers.hp.com/hp-linux-imaging-and-printing) 3.26.6)
for the **HP DeskJet 5938 / 5940 / 5940xi / 5943**. HP's own macOS driver for
these printers is Intel-only and doesn't work on current macOS on Apple silicon
("The printer software is not compatible with this device"). This one runs
natively, with no Rosetta and no changes to security settings.

> Unofficial community build, not supported by HP or Apple.
> Tested on macOS 27, M3 Max, DeskJet 5940 over USB.

## Install

1. Download `hplip-arm64-<version>.pkg` from [Releases](../../releases).
2. Open it. The package isn't signed with an Apple Developer ID, so macOS will
   block it the first time. Go to **System Settings → Privacy & Security**,
   click **Open Anyway** next to the message about the package, and confirm.
   (Or build it yourself; see below.)
3. Connect the printer by USB. Open **System Settings → Printers & Scanners →
   Add Printer**, select the DeskJet 5900 series, and under **Use** choose
   **Select Software…** → **HP Deskjet 5900 Series, hpcups 3.26.6 (arm64)**.

You can also add the printer from Terminal. Get the URI from `lpinfo -v`:

```bash
sudo lpadmin -p DeskJet_5940 -E -v 'usb://HP/Deskjet%205900%20series?serial=YOURSERIAL' -P /Library/Printers/hplip-arm64/ppd/hp-deskjet_5900_series.ppd -o printer-is-shared=false
```

## "Unable to use legacy USB class driver."

If the queue pauses with this message, it's not the driver's fault. If you
ever installed HP's old macOS driver, it left **codeless kexts** in
`/Library/Extensions` (for example `hp_io_enabler_compound.kext` and
`hp_Deskjet_io_enabler.kext`). They tag HP USB printers with

```
"USB Printing Class" = /Library/Printers/hp/Frameworks/HPDM.framework/Runtime/HPIOPrinterClassDriver.plugin
```

Apple's `usb` backend always uses that class driver. The plugin is
i386/x86_64-only, so the backend fails with `Bad CPU type in executable`.
There's no per-queue override, and a replacement backend would have to go in
SIP-protected `/usr/libexec/cups/backend`.

The fix is to move the matching kexts aside and reboot. The backend then uses
Apple's own `USBGenericPrintingClass.plugin`. A helper that only touches
kexts matching your connected printer is included:

```bash
/Library/Printers/hplip-arm64/fix-hp-usb-classdriver.sh            # check only
sudo /Library/Printers/hplip-arm64/fix-hp-usb-classdriver.sh --fix     # move them to a backup folder
sudo /Library/Printers/hplip-arm64/fix-hp-usb-classdriver.sh --restore # put them back
```

Reboot after `--fix` or `--restore`. The kexts only point old USB HP
printers at that Intel-only plugin, which can't run on current macOS anyway.
They're backed up to `/Library/Application Support/hplip-arm64/disabled-kexts`.

## How it works

The job flows through these filters:
`PDF → cgpdftoraster (macOS) → CUPS raster → hpcups (arm64) → PCL3GUI → usb backend`.

The PPD is HPLIP's `hp-deskjet_5900_series.ppd` with two changes. Its
`*cupsFilter` line is replaced by
`*cupsFilter2: "application/vnd.cups-raster application/vnd.hp-pcl3gui2 0 /Library/Printers/hplip-arm64/filter/hpcups"`,
because third-party filters can't be installed in SIP-protected
`/usr/libexec/cups/filter`. And ` (arm64)` is appended to its NickName.

The filter is ad-hoc signed. libjpeg is linked statically, so it depends only
on system libraries, as cupsd's filter sandbox expects.

Installed files:

```
/Library/Printers/hplip-arm64/filter/hpcups
/Library/Printers/hplip-arm64/ppd/hp-deskjet_5900_series.ppd
/Library/Printers/hplip-arm64/{uninstall.sh,fix-hp-usb-classdriver.sh,README.md,LICENSE,NOTICE}
/Library/Printers/PPDs/Contents/Resources/HP Deskjet 5900 Series hpcups arm64.ppd.gz
```

## Patches to HPLIP

These are in [`patches/`](patches). All are small and specific to macOS:

1. Don't link `libImageProcessor` when `--disable-imageProcessor-build` is
   set. HP ships that library only as prebuilt x86 Linux `.so` files.
2. Include `common/utils.h` by explicit path. On case-insensitive APFS,
   `#include "utils.h"` resolved to `prnt/hpcups/Utils.h`.
3. Use `<stdlib.h>` instead of `<malloc.h>` on macOS.
4. Compile `common/utils.c` through a distinctly named wrapper. Without it,
   `hpcups-utils.o` and `hpcups-Utils.o` are the same file on case-insensitive
   filesystems.

## Build from source

You need an Apple silicon Mac, Xcode Command Line Tools, and
[Homebrew](https://brew.sh). The script installs `jpeg-turbo autoconf automake
libtool pkgconf` if they're missing.

```bash
./build.sh                  # downloads + verifies HPLIP, patches, builds -> dist/
./pkg/make-pkg.sh 0.1.0     # optional: installer -> out/hplip-arm64-0.1.0.pkg
```

To install without building the package:

```bash
sudo install -d -o root -g wheel -m 755 /Library/Printers/hplip-arm64/filter /Library/Printers/hplip-arm64/ppd
sudo install -o root -g wheel -m 755 dist/filter/hpcups /Library/Printers/hplip-arm64/filter/
sudo install -o root -g wheel -m 644 dist/ppd/hp-deskjet_5900_series.ppd /Library/Printers/hplip-arm64/ppd/
```

Test offline, with no printer, by pointing a scratch copy of the PPD at the
build output:

```bash
sed "s|/Library/Printers/hplip-arm64/filter/hpcups|$PWD/dist/filter/hpcups|" dist/ppd/hp-deskjet_5900_series.ppd > /tmp/local.ppd
cupsfilter -m application/pdf /etc/hosts > /tmp/test.pdf
cupsfilter -p /tmp/local.ppd -e -m printer/foo /tmp/test.pdf > /tmp/test.pcl   # PJL/PCL3GUI output
```

## Troubleshooting

```bash
sudo cupsctl --debug-logging
tail -f /private/var/log/cups/error_log
sudo cupsctl --no-debug-logging
```

The filter and all its parent directories must be root-owned and not
group- or world-writable. The installer takes care of this.

## Uninstall

```bash
sudo /Library/Printers/hplip-arm64/uninstall.sh                  # warns about queues still using it
sudo /Library/Printers/hplip-arm64/uninstall.sh --remove-queues  # also deletes those queues
```

If you used `fix-hp-usb-classdriver.sh --fix`, run it with `--restore` first
(and reboot) if you want the old HP kexts back.

## Other printers

HPLIP ships hpcups PPDs for many other older HP inkjets that use the same
PCL3/PCL3GUI path. They'd probably work with this filter, but only the 5900
series has been tested. Issues and PRs with test reports are welcome. Models
that need HP's proprietary binary plugin won't work.

## License

GPL-2.0-or-later, the same as HPLIP. See [LICENSE](LICENSE) and
[NOTICE](NOTICE). HPLIP is © HP Development Company, L.P.
