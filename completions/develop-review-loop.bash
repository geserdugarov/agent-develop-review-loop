# shellcheck shell=bash
# shellcheck disable=SC2207  # COMPREPLY uses the standard $(compgen ...) idiom
# Bash completion for develop-review-loop.
#
# Install with one of:
#   ln -sfn "$PWD/completions/develop-review-loop.bash" \
#       ~/.local/share/bash-completion/completions/develop-review-loop
#   source completions/develop-review-loop.bash   # for ad-hoc shells
#
# Completes flags, --start-stage and --rerun-from values, task files, and
# .develop-review-loop/run-* directories after --manual-rerun.

_develop_review_loop() {
  local cur prev
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  local opts="
    --max
    --start-stage
    --start-review
    --review-first
    --manual-rerun
    --resume-run
    --rerun-run
    --rerun-from
    --start-ref
    --help
    -h
  "

  case "$prev" in
    --manual-rerun|--resume-run|--rerun-run)
      COMPREPLY=( $(compgen -d -- "${cur:-.develop-review-loop/run-}") )
      [[ ${#COMPREPLY[@]} -gt 0 ]] || COMPREPLY=( $(compgen -d -- "$cur") )
      return
      ;;
    --start-stage)
      COMPREPLY=( $(compgen -W "development review" -- "$cur") )
      return
      ;;
    --rerun-from)
      local stages="" i
      for i in {0..20}; do
        stages+=" development-$i review-$i"
      done
      COMPREPLY=( $(compgen -W "$stages" -- "$cur") )
      return
      ;;
    --max|--start-ref)
      return
      ;;
  esac

  if [[ "$cur" == --* ]]; then
    COMPREPLY=( $(compgen -W "$opts" -- "$cur") )
    return
  fi

  COMPREPLY=( $(compgen -f -- "$cur") )
}

complete -o filenames -F _develop_review_loop develop-review-loop development-review-loop
