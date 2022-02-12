default:
  @just --list --unsorted --color=always | rg -v "    default"

# apply virtualenv for python deps - creating if necessary
venv:
  #!/usr/bin/env bash
  if [ -d venv ]; then
    source venv/bin/activate
  else
    python3 -m venv venv
    source venv/bin/activate
    pip install -r requirements.txt
  fi

# apply virtualenv and start a development server
develop: venv
  #!/usr/bin/env bash
  (sleep 2 && xdg-open http://127.0.0.1:8000/) &
  mkdocs serve
