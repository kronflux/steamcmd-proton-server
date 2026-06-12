#!/bin/bash
# Sons of the Forest (modded) — identical server logic; RedLoader is enabled
# via INSTALL_REDLOADER in the preset. Reuses the base module's hooks.
# NOTE: baked pair — /data overlays of this module must be self-contained
# (cross-module sourcing is not supported through the overlay).
source "$(dirname "${BASH_SOURCE[0]}")/../sons-of-the-forest/setup.sh"
