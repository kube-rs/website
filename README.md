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

This webpage **copies** certain files from resources elsewhere and the **canonical versions** thus live **outside this repo**.

**Copied files are overwritten herein and should be edited at the root source due to github interaction effects.**

The synchronised files are marked with `<!--GENERATED FROM XXX-->` header, so try to keep an eye out for this.
For a full overview see the [sync.sh](https://github.com/kube-rs/website/blob/main/sync.sh) script.
