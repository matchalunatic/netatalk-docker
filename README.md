# netatalk-docker

Custom netatalk image. Builds netatalk from a pinned upstream release with ACL
support enabled, and replaces `env_setup.sh` so one instance can serve some
volumes read-only and others read-write, including on read-only bind mounts.

Files: `Dockerfile`, `env_setup.sh`, `entrypoint.sh` (upstream, pinned),
`compose.example.yml`.

## Why not the upstream image

Two problems:

1. `netatalk/netatalk` is built with `-Dwith-acls=false`. On Linux netatalk only
   ever compiles POSIX ACLs, so with ACLs off it derives a volume's access from
   raw mode bits. On a read-only mount the share directory cannot be chowned and
   (on ZFS with NFSv4 ACLs) its mode cannot be widened, so the volume is dropped
   from the server's volume list. This image builds with `-Dwith-acls=true`.

2. `env_setup.sh` runs under `set -e` and chmod/chowns every share directory. On
   a read-only mount that fails with EROFS and aborts the entrypoint. And
   `AFP_READONLY` is a single global flag: both volumes become ro or both rw.

## Volumes

`NETATALK_SHARES` is a `;`-separated list of `path:name:mode:ea`:

    NETATALK_SHARES="/mnt/afpbackup:shared:ro;/mnt/afpshare:mac-files:rw"

- mode is `rw` or `ro`, default `ro`.
- ea is `sys`, `ad`, `samba` or `none`, optional (default: auto-detect). Set it
  on read-only volumes: the auto-detect probe writes an xattr to the volume
  root, which a read-only mount refuses.
- name is optional, defaults to basename(path).
- Escape `;`, `:` and `\` with a backslash if they appear in a path or name.

With `NETATALK_SHARES` unset the upstream `SHARE_NAME` / `SHARE_NAME2` variables
are used as before (paths `/mnt/afpshare` and `/mnt/afpbackup`), first rw,
second ro; `AFP_SHARE1_MODE` / `AFP_SHARE2_MODE` override those two.
`AFP_READONLY` still forces everything read-only.

Read-only volumes also get `stat vol = no`. Netatalk otherwise omits a volume
from `FPGetSrvrParms` unless the connecting user has r-x on the volume root,
which a read-only, ACL-driven directory often cannot grant. The option only
affects listing; the exported access rights are unchanged.

`NETATALK_RO_DBPATH` moves read-only volumes' CNID database onto a writable
path (netatalk requires one even for read-only volumes). It is created and
chowned per volume:

    -e 'NETATALK_RO_DBPATH=/mnt/afpshare/.afpdb'

These modes set the AFP access list and mount options; the mount mode (`:ro`)
applies to the whole process, so use both for a genuine read-only share.

## Build

    docker build -t matchalunatic/netatalk:latest .
    docker push matchalunatic/netatalk:latest

The base Alpine image and the netatalk version are pinned in the Dockerfile;
bump `NETATALK_VERSION` deliberately. The only build-flag difference from
upstream's Dockerfile is `-Dwith-acls=true`.

## Known limitation

On a read-only volume netatalk logs `does not support Extended Attributes or
read-only volume` at startup. This is the EA auto-detect probe against the
read-only volume root; `ea` set explicitly avoids the probe, `NETATALK_RO_DBPATH`
covers the CNID database. Files list and serve regardless.
