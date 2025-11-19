#!/bin/bash
mkdir -p reports/json

kubectl get networkpolicies -A -o json > reports/json/calico.json