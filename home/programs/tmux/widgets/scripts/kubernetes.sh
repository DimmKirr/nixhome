#!/usr/bin/env bash
# Current kubectl context + namespace, e.g. "prod:default".
# Outputs "" if no kubeconfig / no context set.

ctx=$(kubectl config current-context 2>/dev/null || true)
[ -z "$ctx" ] && exit 0

ns=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || true)
[ -z "$ns" ] && ns="default"

# Optionally clean up EKS ARNs to just the cluster name.
if [ "${TMUX_WIDGET_K8S_CLEAN_EKS:-1}" = "1" ]; then
  case "$ctx" in
    arn:aws:eks:*) ctx="${ctx##*/}" ;;
  esac
fi

printf '%s:%s' "$ctx" "$ns"
