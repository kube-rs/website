#!/bin/bash
set -eo pipefail

sync() {
    repopath="$1"
    namelocal="$2"
    header="$3"
    # Overwrite the blank file with a big warning and a link to the file on github ui
    uipath=${repopath/main/blob/main}
    uipath=${uipath/master/blob/master}
    echo "<!--GENERATED FROM https://github.com/${uipath} - CHANGES MUST BE MADE THERE -->" > "${namelocal}"
    # Concat optional extra header
    if [ -n "${header}" ]; then
        echo -e "${header}" >> "${namelocal}"
    fi
    # Concat original file contents
    curl -sSL "https://raw.githubusercontent.com/${repopath}" >> "${namelocal}"
    # TODO: swap to use the github api tool ^ to avoid being rate limited in the future

    # TODO: fix relative links in vendored docs somehow
}

main() {
    sync kube-rs/.github/main/maintainers.md docs/maintainers.md
    sync kube-rs/kube-rs/master/CONTRIBUTING.md docs/contributing.md
    # wanted to inline COC, but it links to other documents relatively so won't work
    # for now left out since it is linked through from the contributing guide
    #sync kube-rs/.github/main/code-of-conduct.md docs/code-of-conduct.md
    #sync cncf/foundation/main/code-of-conduct.md docs/code-of-conduct.md "# Code of Conduct\nkube-rs follows the [CNCF code of conduct](https://github.com/cncf/foundation/blob/main/code-of-conduct.md) inlined below."
    sync kube-rs/.github/main/SECURITY.md docs/security.md

    # main readme requires some re-formatting to be used as getting-started
    sync kube-rs/kube-rs/master/README.md docs/getting-started.md
    # drop the first paragraph
    sd "# kube-rs[\w\W]*## Installation" "# Getting Started\n## Installation" docs/getting-started.md

    # changelog requires some re-formatting (don't want to change all automation scripts in kube-rs repo)
    sync kube-rs/kube-rs/master/CHANGELOG.md docs/changelog.md "# Changelog"
    sd "^(.+ / [\d-]+)\n===================" "## \$1" docs/changelog.md
    sd "UNRELEASED\n===================" "## Unreleased" docs/changelog.md

    # TODO: maybe move these files into this repo as they have no interaction effects
    sync kube-rs/.github/main/governance.md docs/governance.md
    sync kube-rs/kube-rs/master/architecture.md docs/architecture.md
}

# shellcheck disable=SC2068
main $@
