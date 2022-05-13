default:
  @just --list --unsorted --color=always | rg -v "    default"

# Start a development server assuming virtualenv deps have been installed
serve:
  #!/usr/bin/env bash
  if [ -z "${VIRTUAL_ENV}" ]; then
    echo "Activate virtualenv first"
    echo "Please run:"
    echo "python3 -m venv venv && source/venv/bin/activate && pip install -r requirements.txt"
    echo "or, if you have already installed it:"
    echo "source venv/bin/activate"
    exit 1
  fi
  (sleep 2 && xdg-open http://127.0.0.1:8000/) &
  mkdocs serve

# Synchronize markdown from other repos in kube-rs org
sync:
  ./sync.sh

# mode: makefile
# End:
# vim: set ft=make :
