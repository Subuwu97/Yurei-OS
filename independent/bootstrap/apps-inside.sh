#!/bin/bash
# Download verified Flathub deployments using Yurei's source-built Flatpak.
set -euo pipefail
yurei-software --groups multimedia,gaming
flatpak --system list --app --columns=application,version,branch
