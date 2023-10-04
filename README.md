# kube-rs website

[![release](https://github.com/kube-rs/website/actions/workflows/release.yml/badge.svg)](https://github.com/kube-rs/website/actions/workflows/release.yml)
Markdown documents and scripts for generating the [kube.rs](https://kube.rs) website.

Hosted on [github pages](https://kube-rs.github.io/website).

## Setup

This repo uses [`mkdocs`](https://www.mkdocs.org/) with [mkdocs-material](https://squidfunk.github.io/mkdocs-material/) and wiki style markdown cross-links.

## Editing
To preview the webpage install requirements in a virtualenv and run `mkdocs serve`.

Wiki links work locally given something like the [marksman markdown language server](https://github.com/artempyanykh/marksman), or through [foam](https://foambubble.github.io/foam/) for vs code with the recommended extensions in this repo.

## Organisation

The [mkdocs.yml](./mkdocs.yml) file's `nav` section dictates the structure of the webpage.

## Interactions

This webpage **copies** certain files from resources elsewhere and the **canonical versions** thus live **outside this repo**.

**Copied files are overwritten herein and should be edited at the root source due to github interaction effects.**

The synchronised files are marked with `<!--GENERATED FROM XXX-->` header, so try to keep an eye out for this.
For a full overview see the [sync.sh](https://github.com/kube-rs/website/blob/main/sync.sh) script.
