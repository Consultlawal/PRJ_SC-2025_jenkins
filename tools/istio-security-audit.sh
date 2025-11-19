#!/bin/bash
mkdir -p reports/json

kubectl get peerauthentication -A -o json > reports/json/istio-peerauth.json
kubectl get destinationrule -A -o json > reports/json/istio-dr.json
kubectl get gateway -A -o json > reports/json/istio-gateways.json
