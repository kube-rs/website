#!/bin/bash
set -euxo pipefail

curl -sSL https://raw.githubusercontent.com/kube-rs/.github/main/maintainers.md -o docs/syncs/maintainers.md
curl -sSL https://raw.githubusercontent.com/kube-rs/kube-rs/master/CONTRIBUTING.md -o docs/syncs/contributing.md
curl -sSL https://raw.githubusercontent.com/kube-rs/kube-rs/master/ADOPTERS.md -o docs/syncs/adopters.md
curl -sSL https://raw.githubusercontent.com/kube-rs/.github/main/code-of-conduct.md -o docs/syncs/code-of-conduct.md
curl -sSL https://raw.githubusercontent.com/kube-rs/.github/main/SECURITY.md -o docs/syncs/security.md

# main readme requires some re-formatting to be used as getting-started
curl -sSL https://raw.githubusercontent.com/kube-rs/kube-rs/master/README.md -o docs/syncs/getting-started.md
sd "^# kube-rs" "# Getting Started" docs/syncs/getting-started.md

# changelog requires some re-formatting (don't want to change all automation scripts in kube-rs repo)
echo "# Changelog" > docs/syncs/changelog.md
curl -sSL https://raw.githubusercontent.com/kube-rs/kube-rs/master/CHANGELOG.md >> docs/syncs/changelog.md
sd "^(.+ / [\d-]+)\n===================" "## \$1" docs/syncs/changelog.md
sd "UNRELEASED\n===================" "## Unreleased" docs/syncs/changelog.md

# TODO: maybe move these files into this repo as they have no interaction effects
curl -sSL https://raw.githubusercontent.com/kube-rs/.github/main/governance.md -o docs/syncs/governance.md
curl -sSL https://raw.githubusercontent.com/kube-rs/.github/main/TOOLS.md -o docs/syncs/tools.md
curl -sSL https://raw.githubusercontent.com/kube-rs/kube-rs/master/architecture.md -o docs/syncs/architecture.md

# TODO: consider building this website from kube-rs repo directly to get links working?
# .. but this means we cannot get docs from other repos
