.PHONY: install run test lint

install:
	python -m venv .venv
	.venv/bin/pip install -e ".[dev]"

run:
	.venv/bin/python -m dataplatform run --data-dir dataplatform_assessment --db accounts.db

test:
	.venv/bin/python -m pytest -q

lint:
	.venv/bin/ruff check . && .venv/bin/ruff format --check .