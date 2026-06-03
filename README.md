# Agent loop of develop and review

[![CI](https://github.com/geserdugarov/agent-develop-review-loop/actions/workflows/ci.yml/badge.svg)](https://github.com/geserdugarov/agent-develop-review-loop/actions/workflows/ci.yml)

Simple bash scripts for a `development >> review` loop with HITL at the end.

## Setup

Link the scripts into `~/bin` (make sure `~/bin` is on `$PATH`):

```bash
mkdir -p "$HOME/bin"
ln -sfn "$PWD/develop-review-loop" "$HOME/bin/develop-review-loop"
ln -sfn "$PWD/develop-review-loop-watch" "$HOME/bin/develop-review-loop-watch"
```

## Usage

```bash
cd /path/to/target/repo
develop-review-loop ./task.md [--max N] [--start-stage development|review]
develop-review-loop --manual-rerun .develop-review-loop/run-YYYYMMDD-HHMMSS-PID [--max N]
```

Exit codes: `0` review passed, `1` cap hit without passing, `2` usage / preflight error.

Optional runtime configuration is read from `./.env` in the target repo. See
[`.env.example`](.env.example) for a starting point.

## Documentation

See [`docs/README.md`](docs/README.md) for full project documentation, including
setup details, Bash tab completion, all CLI flags and configuration variables,
artifacts layout, control flow, review-first and manual rerun modes, and security
notes.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for the
full text.
