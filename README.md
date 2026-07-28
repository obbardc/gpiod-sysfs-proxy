<!-- SPDX-License-Identifier: MIT -->
<!-- SPDX-FileCopyrightText: 2024 Bartosz Golaszewski <bartosz.golaszewski@linaro.org> -->

# gpiod-sysfs-proxy

[libgpiod](https://git.kernel.org/pub/scm/libs/libgpiod/libgpiod.git/)-based
compatibility layer for the linux GPIO sysfs interface.

It uses [FUSE](https://www.kernel.org/doc/html/v6.3/filesystems/fuse.html)
(Filesystem in User Space) in order to expose a filesystem that can be mounted
over `/sys/class/gpio` to simulate the kernel interface.

## Running

Running the script with a mountpoint parameter will mount the simulated gpio
class directory and then exit. The script can also be run with `-f` or `-d`
switches for foreground or debug operation respectively.

The recommended command-line mount options to use are:

```
gpiod-sysfs-proxy <mountpoint> -o allow_other -o default_permissions
```

This allows non-root users to access the filesystem and enables permission
checks by the kernel.

For a complete list of available command-line options, please run:

```
gpiod-sysfs-proxy --help
```

## Integration

### systemd

The package installs a systemd template unit:

```
gpiod-sysfs-proxy@.service
```

No instance is enabled by default. The instance name is the
systemd-escaped mountpoint. To expose the compatibility filesystem at
`/run/gpio`:

```
systemctl enable --now gpiod-sysfs-proxy@run-gpio.service
```

or, to mount over `/sys/class/gpio` (only works when that directory already
exists, i.e. the kernel sysfs GPIO interface is enabled):

```
systemctl enable --now gpiod-sysfs-proxy@sys-class-gpio.service
```

You can generate the escaped instance name for any path with:

```
systemd-escape --path /run/gpio
systemd-escape --path /sys/class/gpio
```

The `sys-class-gpio` instance also works on a kernel where sysfs GPIO support
is disabled (so `/sys/class/gpio` does not exist): an instance-specific drop-in
pulls in the bundled `run-gpio-sys.mount` and `sys-class.mount` units, which
overlay the missing `gpio` directory onto `/sys/class` before the proxy starts
and tear it back down when the instance is stopped. Nothing else enables those
mounts, and they are skipped when `/sys/class/gpio` already exists. See the
[Non-existent `/sys/class/gpio`](#non-existent-sysclassgpio) caveat below for
the underlying mechanism.

## Caveats

Due to how FUSE works, there are certain limitations to the level of
compatibility we can assure as well as some other issues the user may need
to have to work around.

### Non-existent `/sys/class/gpio`

If the GPIO sysfs interface is disabled in Kconfig, the `/sys/class/gpio`
directory will not exist and the user-space can't create directories inside
of sysfs. There are two solutions: either the user can use a different
mountpount or - for full backward compatibility - they can use overlayfs on
top of `/sys/class` providing the missing `gpio` directory.

Example:

```
mkdir -p /run/gpio/sys /run/gpio/class/gpio /run/gpio/work
mount -t sysfs sysfs /run/gpio/sys
mount -t overlay overlay -o lowerdir=/run/gpio/sys/class,upperdir=/run/gpio/class,workdir=/run/gpio/work,ro
gpiod-sysfs-proxy /sys/class/gpio <options>
```

### Links in `/sys/class/gpio`

The kernel sysfs interface at `/sys/class/gpio` contains links to directories
living elsewhere (specifically: under the relevant device entries) in sysfs.
For obvious reasons we cannot replicate that so, instead we expose actual
directories representing GPIO chips and exported GPIO lines.

### Polling of the `value` attribute

We currently don't support multiple users polling the `value` attribute at
once. Also: unlike the kernel interface, reading from `value` will not block
after the value has been read once.

### Static GPIO base number

Some legacy GPIO drivers hard-code the base GPIO number. We don't yet support
it but it's planned as a future extension in the form of an argument that will
allow to associate a hard-coded base with a GPIO chip by its label.

## Similar projects

* [sysfs-gpio-shim](https://github.com/info-beamer/sysfs-gpio-shim), written in
C. Officially only supports Raspberry Pi.


## Testing

To test this project, you need to build a test image first using OpenEmbedded.

Install `kas` using the [upstream instructions](https://kas.readthedocs.io/en/latest/userguide/getting-started.html).

Install other tools required, for instance on debian:
```
sudo apt install

TODO
```

Then build the image:
```
kas-container build tests/yocto/gpiod-sysfs-proxy-tests.yml
```

The build writes its downloads and shared state next to the build directory,
as `downloads/` and `sstate-cache/`. Keep them between builds; they are what
makes a rebuild take minutes instead of hours.


### Continuous integration

`.github/workflows/ci.yml` runs two jobs. The `reuse` job checks that every
file carries SPDX copyright and licensing information; run the same check
locally with:
```
pip3 install reuse
reuse lint
```

The `ptest` job builds the same image on a GitHub Actions runner and runs the
ptests in QEMU. It merges an extra kas fragment,
`tests/yocto/ci.yml`, which adapts the build to a runner: it enables
`rm_work` (the runner has only ~25 GB of disk), pins the parallelism to the
4 available cores, and points `SSTATE_MIRRORS`/`SOURCE_MIRROR_URL` at the
Yocto Project mirrors so that as much as possible is downloaded rather than
compiled.

#### Builds that do not fit in one run

GitHub destroys a runner after 6 hours with no opportunity to run any further
steps, so a cold Yocto build that overruns loses everything it produced and
the next run starts from scratch again. The workflow avoids that by giving
bitbake its own, shorter budget:

* `BUILD_TIMEOUT_MINUTES` (270 by default) caps the build step. The step runs
  bitbake under `timeout`, which sends `SIGTERM` when the budget is up.
* bitbake writes each task's sstate object as that task completes, so
  everything finished before the signal is already on disk and is kept.
* The pruning and cache-saving steps are marked `if: always()`, so the partial
  sstate is uploaded exactly as a completed build's would be.
* The job then fails with an explicit message. **Re-run it**: it restores the
  cache it just saved and continues from there. Repeat until a run gets all
  the way through — each one gets further, and only the final one runs the
  ptests.

Roughly 90 minutes of the 6 hour limit is left unused on purpose; pruning and
uploading several GB of cache is not fast, and the QEMU ptest run has to fit
too. Raise `BUILD_TIMEOUT_MINUTES` only if you have measured that headroom to
be excessive.

#### Cache keys

Both caches are saved under keys ending in
`${{ github.run_id }}-${{ github.run_attempt }}`, and restored through a bare
prefix (`yocto-sstate-<arch>-`, `yocto-downloads-`) that matches any previous
entry.

The keys are intentionally weak. sstate objects are content-addressed and
carry their own signatures: bitbake validates each one against the current
metadata and silently rebuilds anything that does not match, so an
out-of-date cache can only ever be *incomplete*, never wrong. Tying the key
to the layer configuration, as the workflow originally did, only meant
throwing away a cache that was still mostly usable. Including `run_attempt`
is what makes the re-run flow above work: without it, a re-run would try to
save under the key it had just restored from and be rejected as a duplicate.

Two things about GitHub's cache are worth knowing when a run seems to have
started cold:

* A repository gets 10 GB in total, and entries are evicted least-recently-
  used once that is exceeded. The `Prune caches to their budgets` step keeps
  the two entries within `SSTATE_BUDGET_MB` and `DL_BUDGET_MB` (5 GB and
  2.5 GB) so that a single run cannot fill the quota and evict itself.
* Caches written on a branch are visible only to that branch and to pull
  requests based on it; **only the default branch's caches are visible
  everywhere**. A pull request from a fresh branch therefore starts from
  whatever `main` last saved. The weekly `schedule:` trigger exists to keep
  that entry fresh, since GitHub also evicts anything unread for 7 days.

### Pinned layer revisions

The layers in `tests/yocto/gpiod-sysfs-proxy-tests.yml` are pinned to a Yocto
Project release rather than tracking `master`:

| Layer | Pinned by |
| --- | --- |
| `bitbake` | tag `yocto-6.0.2` |
| `openembedded-core` | tag `yocto-6.0.2` |
| `meta-yocto` | tag `yocto-6.0.2` |
| `meta-openembedded` | branch `wrynose` (publishes no `yocto-*` tags) |

Exact commits are recorded in `tests/yocto/gpiod-sysfs-proxy-tests.lock.yml`,
which kas reads automatically whenever the config next to it is used. Nothing
moves under you: the same revisions are built locally and in CI until the
lockfile is deliberately updated.

Pinning is not only about reproducibility. It is also what makes
`SSTATE_MIRRORS` worth having, and so what keeps cold builds inside the CI
time limit. The mirror only holds shared state for metadata the Yocto
autobuilder actually built, which a released tag is and an arbitrary `master`
commit is not — so on `master` almost every lookup misses and everything is
compiled locally.

#### Updating the pin

To pick up newer revisions of the branch-tracked layers:
```
kas lock --update tests/yocto/gpiod-sysfs-proxy-tests.yml
```
Commit the resulting lockfile. The `update-lockfile` workflow does exactly
this every Monday and opens a pull request with the result, so that an
upstream regression appears as a failing update PR rather than as a red CI
run on an unrelated change. Because it only refreshes what the config allows
to move, in practice it tracks `meta-openembedded` alone.

> Pull requests opened using `GITHUB_TOKEN` do not trigger workflow runs. To
> get CI on the update PR, close and reopen it, push to its branch, or give
> the workflow a personal access token instead.

Moving to a **new Yocto release** is a manual step: bump the three `yocto-*`
tags together, change the `meta-openembedded` branch to the matching
codename, then regenerate the lockfile as above. Expect the first CI run
afterwards to be slow, since it starts from an sstate cache built for the
previous release.
