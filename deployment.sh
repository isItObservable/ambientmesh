#!/usr/bin/env bash

################################################################################
### Script deploying the Observ-K8s environment
### Parameters:
### Clustern name: name of your k8s cluster
### dttoken: Dynatrace api token with ingest metrics and otlp ingest scope
### dturl : url of your DT tenant wihtout any / at the end for example: https://dedede.live.dynatrace.com
################################################################################


### Pre-flight checks for dependencies
if ! command -v jq >/dev/null 2>&1; then
    echo "Please install jq before continuing"
    exit 1
fi

if ! command -v git >/dev/null 2>&1; then
    echo "Please install git before continuing"
    exit 1
fi


if ! command -v helm >/dev/null 2>&1; then
    echo "Please install helm before continuing"
    exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
    echo "Please install kubectl before continuing"
    exit 1
fi
echo "parsing arguments"
while [ $# -gt 0 ]; do
  case "$1" in
  --dttoken)
    DTTOKEN="$2"
   shift 2
    ;;
  --dthost)
    DTURL="$2"
   shift 2
    ;;
  *)
    echo "Warning: skipping unsupported option: $1"
    shift
    ;;
  esac
done
echo "Checking arguments"

if [ -z "$DTURL" ]; then
  echo "Error: Dt hostname not set!"
  exit 1
fi

if [ -z "$DTTOKEN" ]; then
  echo "Error: api-token not set!"
  exit 1
fi

kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd/experimental?ref=v0.6.1" | kubectl apply -f -; }


#### Deploy the cert-manager
echo "Deploying Cert Manager ( for OpenTelemetry Operator)"
kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.10.0/cert-manager.yaml
# Wait for pod webhook started
kubectl wait pod -l app.kubernetes.io/component=webhook -n cert-manager --for=condition=Ready --timeout=2m
# Deploy the opentelemetry operator
sleep 10
echo "Deploying the OpenTelemetry Operator"
kubectl apply -f https://github.com/open-telemetry/opentelemetry-operator/releases/latest/download/opentelemetry-operator.yaml


istioctl install -f istio/istio-operator.yaml --skip-confirmation

kubectl create secret generic dynatrace  --from-literal=dynatrace_oltp_url="$DTURL" --from-literal=dt_api_token="$DTTOKEN"
kubectl apply -f openTelemetry-demo/rbac.yaml
kubectl apply -f openTelemetry-demo/openTelemetry-manifest_debut.yaml

#deploy demo application
kubectl create ns otel-demo
kubectl apply -f openTelemetry-demo/openTelemetry-sidecar.yaml -n otel-demo



### Update the ip of the ip adress for the ingres
#TODO to update this part to use the dns entry /ELB/ALB
kubectl apply -f openTelemetry-demo/deployment.yaml -n otel-demo
kubectl apply -f istio/istio_gateway.yaml -n otel-demo

### get the ip adress of ingress ####
IP=""
while [ -z $IP ]; do
  echo "Waiting for external IP"
  IP=$(kubectl get svc -n otel-demo -l gateway.istio.io/managed=istio.io-gateway-controller -ojson | jq -j '.items[].status.loadBalancer.ingress[].ip')
  [ -z "$IP" ] && sleep 10
done
echo 'Found external IP: '$IP
sed -i "s,IP_TO_REPLACE,$IP," openTelemetry-demo/loadgenerator-external.yaml
kubectl apply -f openTelemetry-demo/loadgenerator-external.yaml -n otel-demo


echo "--------------Demo--------------------"
echo "url of the demo: "
echo "Otel demo url: http://$IP"
echo "========================================================"

