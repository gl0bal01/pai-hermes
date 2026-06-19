#!/usr/bin/env python3
"""
patch_hermes_config.py — additive patcher for ~/.hermes/config.yaml.

Adds or removes a single entry under skills.external_dirs WITHOUT destroying
the user's existing entries, comments, formatting, or anchors. Used by both
install.sh and uninstall.sh in place of the old duplicated inline heredocs.

Design (security/robustness hardening):
  H5 — the config path is read from argv (or HERMES_CONFIG env), NEVER
       shell-interpolated into a `python3 -c "..."` string. A path containing
       a single quote, $(...), or backticks is inert here: it is only ever a
       filesystem path argument, never source code.
  H7 — ruamel.yaml round-trip (YAML(typ='rt')) preserves comments, key order,
       block/flow style, and anchors that PyYAML safe_dump would have flattened.
  H2 — writes atomically: a temp file in the SAME directory is flushed +
       fsynced, the result is re-parsed to prove it is valid YAML, and only
       then os.replace() swaps it into place. The original is never truncated
       in place, so a crash mid-write cannot leave an empty/half config.
  H4 — does NOT inject any `template_vars` key. The old
       `skills.setdefault("template_vars", True)` was an undocumented scope
       violation (CLAUDE.md "External dirs: Append, never replace"; the
       contract forbids touching unrelated keys) and is dropped entirely.

Usage:
    python3 patch_hermes_config.py --add-external-dir PATH [CONFIG]
    python3 patch_hermes_config.py --remove-external-dir PATH [CONFIG]

CONFIG defaults to the HERMES_CONFIG environment variable. PATH may also come
from the SKILL_DIR environment variable when the flag value is omitted.

Exit codes:
    0  success (changed, or already in the desired state — idempotent)
    2  usage / validation error (bad args, unparseable YAML, wrong shape)
    3  missing ruamel.yaml dependency (actionable message on stderr)
"""

import argparse
import io
import os
import sys
from pathlib import Path

try:
    from ruamel.yaml import YAML
    from ruamel.yaml.error import YAMLError
except ImportError:  # pragma: no cover - exercised via install.sh dependency gate
    sys.stderr.write(
        "ERROR: ruamel.yaml is required but not importable.\n"
        "Install it with: pip install --user ruamel.yaml\n"
        "(install.sh attempts this automatically; if it failed, install "
        "ruamel.yaml into the Python that runs Hermes and re-run.)\n"
    )
    sys.exit(3)


def _yaml() -> YAML:
    """Round-trip YAML configured to preserve the user's formatting."""
    y = YAML(typ="rt")
    y.preserve_quotes = True
    # Keep block style; do not collapse the user's indentation choices.
    y.default_flow_style = False
    return y


def _load(yaml: YAML, cfg_path: Path):
    """Load the config, returning a round-trip mapping. Exit 2 on bad shape."""
    try:
        raw = cfg_path.read_text()
    except OSError as exc:
        sys.stderr.write(f"ERROR: cannot read {cfg_path}: {exc}\n")
        sys.exit(2)

    try:
        data = yaml.load(raw)
    except YAMLError as exc:
        sys.stderr.write(f"ERROR: {cfg_path} is not valid YAML: {exc}\n")
        sys.exit(2)

    if data is None:
        data = {}
    if not isinstance(data, dict):
        sys.stderr.write(f"ERROR: {cfg_path} root is not a mapping\n")
        sys.exit(2)
    return data


def _dump_to_str(yaml: YAML, data) -> str:
    buf = io.StringIO()
    yaml.dump(data, buf)
    return buf.getvalue()


def _atomic_write(yaml: YAML, cfg_path: Path, data) -> None:
    """H2: write to a temp file in the same dir, fsync, validate, os.replace."""
    new_text = _dump_to_str(yaml, data)

    # Re-parse the rendered text BEFORE swapping it in. A round-trip that
    # somehow produced invalid YAML must never reach disk as the live config.
    try:
        reparsed = yaml.load(new_text)
    except YAMLError as exc:
        sys.stderr.write(f"ERROR: refusing to write unparseable YAML: {exc}\n")
        sys.exit(2)
    if not isinstance(reparsed, dict):
        sys.stderr.write("ERROR: rendered config is not a mapping; aborting\n")
        sys.exit(2)
    if new_text.strip() == "":
        sys.stderr.write("ERROR: rendered config is empty; aborting\n")
        sys.exit(2)

    directory = cfg_path.parent
    # Temp file in the SAME directory so os.replace is an atomic rename, not a
    # cross-filesystem copy.
    fd = None
    tmp_path = None
    try:
        import tempfile

        fd, tmp_name = tempfile.mkstemp(
            prefix=cfg_path.name + ".", suffix=".tmp", dir=str(directory)
        )
        tmp_path = Path(tmp_name)
        with os.fdopen(fd, "w") as f:
            fd = None  # ownership transferred to the file object
            f.write(new_text)
            f.flush()
            os.fsync(f.fileno())
        # Preserve the original file's mode if it exists.
        try:
            mode = cfg_path.stat().st_mode & 0o777
            os.chmod(tmp_path, mode)
        except OSError:
            pass
        os.replace(str(tmp_path), str(cfg_path))
        tmp_path = None  # replaced; nothing to clean up
    finally:
        if fd is not None:
            os.close(fd)
        if tmp_path is not None and tmp_path.exists():
            try:
                tmp_path.unlink()
            except OSError:
                pass


def _get_external_dirs(data):
    """Return (skills_map, external_list_or_None). Exit 2 on wrong shapes."""
    skills = data.get("skills")
    if skills is None:
        skills = {}
        data["skills"] = skills
    if not isinstance(skills, dict):
        sys.stderr.write("ERROR: 'skills' key is not a mapping\n")
        sys.exit(2)

    ext = skills.get("external_dirs")
    if ext is not None and not isinstance(ext, list):
        sys.stderr.write("ERROR: 'skills.external_dirs' is not a list\n")
        sys.exit(2)
    return skills, ext


def add_external_dir(cfg_path: Path, target: str) -> int:
    yaml = _yaml()
    data = _load(yaml, cfg_path)
    skills, ext = _get_external_dirs(data)

    if ext is None:
        # Create the list fresh; append-only semantics still hold.
        skills["external_dirs"] = [target]
    elif target in ext:
        # Idempotent: already present, leave every existing entry untouched.
        print("ALREADY_PRESENT")
        return 0
    else:
        # Append — never replace or reorder the user's existing entries.
        ext.append(target)

    _atomic_write(yaml, cfg_path, data)
    print("ADDED")
    return 0


def remove_external_dir(cfg_path: Path, target: str) -> int:
    yaml = _yaml()
    data = _load(yaml, cfg_path)
    skills, ext = _get_external_dirs(data)

    if not ext or target not in ext:
        print("NOT_PRESENT")
        return 0

    # Remove only the matching entry/entries; keep every other entry as-is.
    for i in range(len(ext) - 1, -1, -1):
        if ext[i] == target:
            del ext[i]

    _atomic_write(yaml, cfg_path, data)
    print("REMOVED")
    return 0


def _resolve_path_arg(flag_value, env_key: str):
    """Flag value wins; otherwise fall back to the named env var."""
    if flag_value:
        return flag_value
    env_value = os.environ.get(env_key)
    if env_value:
        return env_value
    return None


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(
        description="Additively patch skills.external_dirs in a Hermes config."
    )
    group = ap.add_mutually_exclusive_group(required=True)
    group.add_argument(
        "--add-external-dir",
        metavar="PATH",
        nargs="?",
        const="",
        help="append PATH to skills.external_dirs if absent (idempotent). "
        "Falls back to $SKILL_DIR when PATH is omitted.",
    )
    group.add_argument(
        "--remove-external-dir",
        metavar="PATH",
        nargs="?",
        const="",
        help="remove PATH from skills.external_dirs if present (idempotent). "
        "Falls back to $SKILL_DIR when PATH is omitted.",
    )
    ap.add_argument(
        "config",
        nargs="?",
        help="path to config.yaml (defaults to $HERMES_CONFIG). Treated only "
        "as a filesystem path, never as code (H5).",
    )
    args = ap.parse_args(argv)

    cfg = _resolve_path_arg(args.config, "HERMES_CONFIG")
    if not cfg:
        ap.error("config path required (positional arg or $HERMES_CONFIG)")
    cfg_path = Path(cfg)
    if not cfg_path.exists():
        sys.stderr.write(f"ERROR: config not found: {cfg_path}\n")
        return 2

    if args.add_external_dir is not None:
        target = _resolve_path_arg(args.add_external_dir, "SKILL_DIR")
        if not target:
            ap.error("--add-external-dir requires a PATH or $SKILL_DIR")
        return add_external_dir(cfg_path, target)

    target = _resolve_path_arg(args.remove_external_dir, "SKILL_DIR")
    if not target:
        ap.error("--remove-external-dir requires a PATH or $SKILL_DIR")
    return remove_external_dir(cfg_path, target)


if __name__ == "__main__":
    sys.exit(main())
