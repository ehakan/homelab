#! /bin/sh

REPO_ROOT=$(git rev-parse --show-toplevel)

terraform \
	-chdir="$REPO_ROOT/terraform/stacks/cluster/" \
	output -raw \
	kubeconfig >"$REPO_ROOT/kubeconfig"

terraform \
	-chdir="$REPO_ROOT/terraform/stacks/cluster/" \
	output -raw \
	talosconfig >$REPO_ROOT/talosconfig
