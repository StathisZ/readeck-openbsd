# readeck-openbsd

Scripts to build and run [Readeck](https://readeck.org) on OpenBSD.

Readeck is a self-hosted read-it-later service, developed by the [Readeck project](https://codeberg.org/readeck/readeck) and licensed under AGPL-3.0. This repository doesn't include or modify its source. It adds what OpenBSD lacks: a way to build the binary, a system user, an `rc.d` script and an upgrade path.

## Why a build step

Readeck publishes binaries for Linux, FreeBSD, macOS and Windows, but not for OpenBSD. There is no port or package either, so it has to be built from source. The build needs Go, Node.js and Python, and around 1 GB of free memory for the compile alone. Running Readeck needs none of these. Therefore the default is to build on another machine and copy the binary to the server. A server with enough memory can also build it itself (see below).

## What's here

- `readeck-build` clones a Readeck release, builds the web assets and compiles an OpenBSD/amd64 binary. It runs on Linux, or on the OpenBSD server itself.
- `readeck.sh` runs on the server as root. It installs the binary, creates the `_readeck` user and `/var/readeck`, writes a minimal config, adds an `rc.d` script and publishes Readeck to your tailnet.

## Requirements

- The build machine needs Go 1.21 or newer, git, npm, and Python 3 with the `babel` module. Go downloads the exact version Readeck asks for.
- The server needs OpenBSD on amd64 and root access. It needs Tailscale only if you keep the default publishing step.

## Build and install

```
./readeck-build 0.23.4
scp readeck readeck.sh root@server:
ssh root@server sh readeck.sh
```

Then open the address that `tailscale serve status` shows. The first account you create becomes the admin.

## Building on the server

If the server has the memory, it can build Readeck itself:

```
pkg_add go git node gmake py3-babel
./readeck-build 0.23.4
cp readeck /root/readeck
sh readeck.sh
```

`readeck-build` uses `gmake` when it finds it, because Readeck's Makefile needs GNU make. This path is untested. The cross-compiled build is the tested one.

## Defaults

- Readeck listens on `127.0.0.1:8099`. Change `port=` in `readeck.sh` if that port is taken.
- Tailscale publishes it on HTTPS port 8445, to your tailnet only. Run the script with `TSPORT=<port>` to use another port.
- The config, the database and the saved articles all live in `/var/readeck`. That is the directory to back up.

## Without Tailscale

Tailscale is the default because it keeps Readeck off the public internet. To reach Readeck another way, for example through `relayd` or `httpd` with TLS, delete the last section of `readeck.sh` and point your proxy at `127.0.0.1:8099`.

## Upgrading

Build the new version, copy it to `/root/readeck` and run `readeck.sh` again. The script stops Readeck, copies the old binary and `/var/readeck` aside, installs the new binary and checks the login page. If the new version doesn't answer, it restores the old binary and the data. Because the data is restored too, a rollback is safe even after a database migration.

## The SQLite driver

`readeck-build` sets `CGO_ENABLED=0`. Readeck then uses its pure-Go SQLite driver instead of the CGO driver it ships by default. This has two benefits. The build machine needs no OpenBSD C toolchain, and the binary links an unversioned `libc.so`, so it isn't tied to one libc version.

Readeck logs a warning about this driver on every start. Upstream used it as the default in 0.18 and returned to CGO in 0.19. A CGO build needs either an OpenBSD sysroot on the build machine or a native build on OpenBSD.

## Tested on

- OpenBSD 7.9 on amd64, with Readeck 0.23.4 built on Linux Mint with Go 1.26.8.
- The test covered a first install, an upgrade, and an upgrade with a broken binary that rolled back.

## Uninstall

```
rcctl stop readeck
rcctl disable readeck
tailscale serve --https=8445 off
rm /etc/rc.d/readeck /usr/local/bin/readeck
userdel _readeck
groupdel _readeck
rm -r /var/readeck        # only if you want your saved articles gone too
```

After an upgrade, also remove `/usr/local/bin/readeck.bak` and `/var/readeck.bak`.

by Stathis — https://nevrast.xyz
