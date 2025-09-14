# Statically Linked [Dropbear SSH](https://github.com/mkj/dropbear) Binaries (built with Zig)

This repo publishes prebuilt **musl-linked static ELF binaries** of Dropbear,
built automatically from upstream [mkj/dropbear](https://github.com/mkj/dropbear)
using [Zig](https://ziglang.org/) for cross-compilation.

These binaries should run on virtually any modern Linux distribution with no
external dependencies. Builds include **X11 forwarding support**.

## Contents

Each release provides these tarballs:

```
dropbear-x86_64-linux-musl.tar.xz
dropbear-aarch64-linux-musl.tar.xz
```

Extracting one yields:

```
dropbear-x86_64-linux-musl/
  dropbearmulti
  dropbear -> dropbearmulti
  dropbearkey -> dropbearmulti
```

`dropbearmulti` is a multi-call binary. Depending on `argv[0]`, it runs as
either `dropbear` (the server) or `dropbearkey` (key generator).

To install, copy the three files somewhere on your `PATH`, e.g.:

```sh
sudo cp dropbearmulti dropbear dropbearkey /usr/local/bin/
```

## Basic Dropbear Tutorial

Generate a host key:

```sh
mkdir -p ~/dropbear-test
cd ~/dropbear-test
dropbearkey -t ed25519 -f key
```

Start the server in the foreground on port 2222:

```sh
dropbear -F -E -p 2222 -r key
```

From another terminal, connect:

```sh
ssh -p 2222 localhost
```

## Build Reproducibility

Binaries are built by [build.sh](./build.sh) and GitHub Actions workflows in
this repo. You can rerun the same process yourself to verify results.

## Notes

* Features: X11 forwarding enabled; PAM and zlib disabled; bundled libtom used.
* These builds are intended for lightweight use in containers or
  resource-constrained environments.
* **Security:** As with any SSH server, configure carefully (authorized\_keys,
  permissions, etc.).
