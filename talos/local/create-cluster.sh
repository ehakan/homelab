#!/bin/sh

# create a cluster with the pull through cache registries

talosctl cluster create \
    --provisioner docker \
    --wait \
    --wait-timeout 15m \
    --workers 2 \
    --registry-mirror docker.io=http://172.17.0.1:5000 \
    --registry-mirror registry.k8s.io=http://172.17.0.1:5001 \
    --registry-mirror gcr.io=http://172.17.0.1:5003 \
    --registry-mirror ghcr.io=http://172.17.0.1:5004
