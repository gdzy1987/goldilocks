#!/bin/bash

set -e

kind_required_version=0.6.1
kind_node_image="kindest/node:v1.15.6@sha256:18c4ab6b61c991c249d29df778e651f443ac4bcd4e6bdd37e0c83c0d33eaae78"
vertical_pod_autoscaler_tag=vertical-pod-autoscaler-0.6.3
install_vpa=${1:-true}
install_goldilocks=${2:-true}

## Test Infra Setup
## This will use Kind, Reckoner, and Helm to setup a test infrastructure locally for goldilocks

function version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1";
}

cd "$( cd "$(dirname "$0")" ; pwd -P )"

required_clis="reckoner helm kind"
for cli in $required_clis; do
  command -v "$cli" >/dev/null 2>&1 || { echo >&2 "I require $cli but it's not installed.  Aborting."; exit 1; }
done

kind_version=$(kind version | cut -c2-)

if version_gt "$kind_required_version" "$kind_version"; then
     echo "This script requires kind version greater than or equal to $kind_required_version!"
     exit 1
fi

## Create the kind cluster

kind create cluster \
  --config kind.yaml \
  --name test-infra \
  --image="$kind_node_image" || true

# shellcheck disable=SC2034
until kubectl cluster-info; do
    echo "Waiting for cluster to become available...."
    sleep 3
done

if $install_vpa; then
  ## Install VPA

  if [ ! -d "autoscaler" ] ; then
      git clone "https://github.com/kubernetes/autoscaler.git"
  fi

  cd autoscaler/vertical-pod-autoscaler
  git checkout "$vertical_pod_autoscaler_tag"
  ./hack/vpa-up.sh

  cd ../../
fi

## Helm Init
kubectl -n kube-system create sa tiller --dry-run -o yaml --save-config | kubectl apply -f -;
kubectl create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount="kube-system:tiller" --serviceaccount=kube-system:tiller -o yaml --dry-run | kubectl -n "kube-system" apply -f -

helm init --wait --upgrade --service-account tiller

## Reckoner

reckoner plot course.yml

if $install_goldilocks; then
  ## Install Goldilocks
  kubectl get ns goldilocks || kubectl create ns goldilocks
  kubectl -n goldilocks apply -f ../manifests/controller
  kubectl -n goldilocks apply -f ../manifests/dashboard
fi

echo "Your test environment should now be running."
