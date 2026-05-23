"""Shared path resolution for Binky's localization helpers.

Every translation script in this folder used to hardcode `Dinky/` in its path
(legacy from the sister project) or, in one case, an absolute path on the
original author's machine. That made the scripts non-portable and a daily
foot-gun to maintain. This module is the single source of truth.

Use the constants below instead of building paths inline:

    from _paths import XCSTRINGS_PATH, RESOURCES_DIR

    cat = json.loads(XCSTRINGS_PATH.read_text())
"""
from pathlib import Path

# Repo root: this file lives at <repo>/tools/_paths.py.
PROJECT_ROOT = Path(__file__).resolve().parent.parent

# Swift app source root (contains Localizable.xcstrings, InfoPlist.xcstrings, Resources/).
APP_SRC_DIR = PROJECT_ROOT / "Binky"

# Main user-facing string catalog (UI strings).
XCSTRINGS_PATH = APP_SRC_DIR / "Localizable.xcstrings"

# Info.plist string catalog.
INFO_PLIST_XCSTRINGS_PATH = APP_SRC_DIR / "InfoPlist.xcstrings"

# Per-locale resource folder (.lproj subdirectories with Help.md, etc.).
RESOURCES_DIR = APP_SRC_DIR / "Resources"

# English source for translatable Markdown (Help.md is the only one today).
HELP_MD_EN_PATH = RESOURCES_DIR / "en.lproj" / "Help.md"
