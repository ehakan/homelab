#!/bin/zsh

### STEP 0: Script Setup

# Get the kubernetes cluster dir (main for this script)
kube_cluster_dir=${0:a:h:h}


### STEP 1: Inject Initial Secrets
### Create the correct namespaces and apply the secrets required in the cluster

# Create secret-management namespace
kubectl apply -f \
  $kube_cluster_dir/apps/secret-management/core/namespace.yaml

# Create the op-access-token secret, used by external-secrets to communicate with the 1password-connect service
access_token=$(op read op://homelab/homelab-localdev-access-token/credential)
kubectl create secret generic \
  --namespace secret-management \
  op-access-token \
  --from-literal=token=$access_token

# op-credentials is used by 1password-connect service to connect to 1p servers
# 1password wants this secret as base64 encoded
credentials=$(op read op://homelab/homelab-localdev-credentials-file/1password-credentials.json | base64)
kubectl create secret generic \
  --namespace secret-management \
  op-credentials \
  --from-literal="1password-credentials.json"=$credentials


### STEP 2: Install Secret Management Services

# Install external-secrets
kubectl kustomize \
  --enable-helm \
  $kube_cluster_dir/apps/secret-management/external-secrets \
  | kubectl apply -f -

# Install onepassword (op-connect)
kubectl kustomize \
  --enable-helm \
  $kube_cluster_dir/apps/secret-management/onepassword \
  | kubectl apply -f -

# Wait for all external-secrets pods to be running and ready
kubectl wait \
  --namespace secret-management \
  --selector app.kubernetes.io/instance=external-secrets \
  --for jsonpath='{.status.phase}'=Running \
  pods
kubectl wait \
  --namespace secret-management \
  --selector app.kubernetes.io/instance=external-secrets \
  --for condition=Ready \
  pods

# Setup ClusterSecretStore
kubectl apply -k \
  $kube_cluster_dir/apps/secret-management/resources


# TODO: install argocd

# TODO: wait for argocd to settle down

# TODO: apply the app-of-apps manifests

# TODO: apply confetti only if it's actually successful
echo "Bootstrap complete! 🎉"
open raycast://confetti

