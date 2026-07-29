#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Qualcomm Technologies, Inc. and/or its subsidiaries

"""Prune a directory down to a size budget before it is uploaded as a cache.

GitHub Actions gives a repository 10 GB of cache in total and evicts whole
entries, least-recently-used, once that is exceeded. An unbounded sstate or
downloads directory will therefore grow until it starts evicting itself (and
everything else) between runs.

Files are deleted oldest-mtime-first, which for sstate approximates
least-recently-useful: objects for the current metadata are rewritten or
re-fetched every build, while objects left over from superseded revisions age
out.
"""

import argparse
import os
import sys


def collect(root):
    """Return (files, total_bytes) where files is a list of (mtime, size, path)."""
    files = []
    total = 0
    for dirpath, _, filenames in os.walk(root):
        for name in filenames:
            path = os.path.join(dirpath, name)
            try:
                st = os.lstat(path)
            except OSError:
                continue
            if not os.path.isfile(path) or os.path.islink(path):
                continue
            files.append((st.st_mtime, st.st_size, path))
            total += st.st_size
    return files, total


def prune_empty_dirs(root):
    for dirpath, dirnames, filenames in os.walk(root, topdown=False):
        if dirpath == root or dirnames or filenames:
            continue
        try:
            os.rmdir(dirpath)
        except OSError:
            pass


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory")
    parser.add_argument(
        "--budget-mb",
        type=int,
        required=True,
        help="maximum size to leave behind, in MiB",
    )
    args = parser.parse_args()

    if not os.path.isdir(args.directory):
        print(f"{args.directory}: does not exist, nothing to prune")
        return 0

    budget = args.budget_mb * 1024 * 1024
    files, total = collect(args.directory)
    mib = 1024 * 1024

    print(
        f"{args.directory}: {total // mib} MiB in {len(files)} files "
        f"(budget {args.budget_mb} MiB)"
    )

    if total <= budget:
        return 0

    files.sort()
    removed = 0
    count = 0
    for _, size, path in files:
        if total - removed <= budget:
            break
        try:
            os.remove(path)
        except OSError as exc:
            print(f"warning: cannot remove {path}: {exc}", file=sys.stderr)
            continue
        removed += size
        count += 1

    prune_empty_dirs(args.directory)
    print(
        f"{args.directory}: removed {count} files, {removed // mib} MiB; "
        f"{(total - removed) // mib} MiB left"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
