# kube-rs website

[![CI](https://github.com/kube-rs/website/actions/workflows/release.yml/badge.svg)](https://github.com/kube-rs/release/actions/workflows/release.yml)

Markdown resources and scripts for generating a **PROTOTYPE** kube-rs website.

See the [**rendered github pages**](https://kube-rs.github.io/website) for best effect.

## Setup

This repo uses [foam](https://foambubble.github.io/foam/) + [`mkdocs`](https://www.mkdocs.org/) with [mkdocs-material](https://squidfunk.github.io/mkdocs-material/).

To browse locally in `code`; [clone + install recommended extensions](https://foambubble.github.io/foam/#getting-started) to browse with [markdown links](https://marketplace.visualstudio.com/items?itemName=tchayen.markdown-links).

To preview the webpage install requirements in a virtualenv and run `mkdocs serve`.

## Organisation

The [mkdocs.yml](./mkdocs.yml) file's `nav` section dictates the structure of the webpage.

## Interactions

This webpage copies certain files from resources elsewhere..

Copied files should not be edited herein because they have other github interaction effects.
These files are copied into the [docs/syncs](./docs/syncs/) folder via the [sync.sh](./sync.sh) script.
