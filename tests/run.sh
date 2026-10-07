#!/usr/bin/env bash
# Chart tests: render each fixture, assert on the output, and validate the
# manifests with kubeconform (core types plus CRD schemas from the catalog).
set -euo pipefail
cd "$(dirname "$0")/.."
CHART=chart
FIX=tests/fixtures
fail=0
render() { helm template "$1" "$CHART" -n "$2" -f "$FIX/$3" "${@:4}"; }
check() { # name, expected, actual
  if [[ "$2" == "$3" ]]; then echo "ok   $1"; else echo "FAIL $1: want [$2] got [$3]"; fail=1; fi
}
kinds() { yq -N '.kind' | sort | uniq -c | awk '{print $2"="$1}' | paste -sd, -; }

out=$(render orders dev dev-orders.yaml)
check "dev orders kinds" \
  "ConfigMap=1,Deployment=1,ExternalSecret=2,Password=1,PushSecret=1,Service=2,ServiceAccount=1,StatefulSet=1" \
  "$(kinds <<<"$out")"
check "config ExternalSecret reads each ref from its own store" "localdev-params,localdev-secrets" \
  "$(yq -N 'select(.metadata.name=="orders-config") | .spec.data[].sourceRef.storeRef.name' <<<"$out" | sort -u | paste -sd, -)"
check "config template is passed through untouched" "1" \
  "$(yq -N 'select(.metadata.name=="orders-config") | .spec.target.template.data["config.yaml"]' <<<"$out" | grep -c 'password: {{ .ref2 | toJson }}')"
check "dynamic output published under the outputs key" "services.dev.orders.db" \
  "$(yq -N 'select(.kind=="PushSecret") | .spec.data[0].match.remoteRef.remoteKey' <<<"$out")"
check "Service named after the service, port 80" "orders:80" \
  "$(yq -N 'select(.kind=="Service" and .metadata.name=="orders") | .metadata.name + ":" + (.spec.ports[0].port|tostring)' <<<"$out")"

out=$(render orders dev dev-orders.yaml --set platform.rollouts.enabled=true)
check "rollouts in long-lived env" "Rollout" "$(yq -N 'select(.metadata.name=="orders" and .spec.template) | .kind' <<<"$out" | grep -v StatefulSet)"

out=$(render orders sbx-ryan-checkout-v2 sbx-orders.yaml --set platform.rollouts.enabled=true --set deployment.replicas=3)
check "sandbox uses a 1-replica Deployment" "Deployment:1" \
  "$(yq -N 'select(.metadata.name=="orders" and .kind!="Service" and .kind!="ServiceAccount" and .kind!="ExternalSecret") | .kind + ":" + (.spec.replicas|tostring)' <<<"$out")"
check "sandbox labels" "ryan-checkout-v2" "$(yq -N 'select(.kind=="Deployment") | .metadata.labels["platform.mcafeelabs.io/sandbox"]' <<<"$out")"
check "sandbox provisions only isolated outputs" "orders-db,orders-events-queue" \
  "$(yq -N 'select(.metadata.labels["platform.mcafeelabs.io/output"]) | .metadata.name' <<<"$out" | sort -u | paste -sd, -)"
check "sandbox db published under its own key" "sandboxes.ryan-checkout-v2.orders.db" \
  "$(yq -N 'select(.kind=="PushSecret") | .spec.data[0].match.remoteRef.remoteKey' <<<"$out")"

out=$(render orders sbx-ryan-checkout-v2 sbx-orders.yaml --set platform.sandbox.nodePool.enabled=true)
check "sandbox node pool toleration" "sandbox" "$(yq -N 'select(.kind=="Deployment") | .spec.template.spec.tolerations[0].key' <<<"$out")"

out=$(render payments sbx-ryan-checkout-v2 sbx-payments.yaml)
check "payments sandbox: nothing to provision, literal config" "Deployment=1,Secret=1,Service=1,ServiceAccount=1" "$(kinds <<<"$out")"
check "payments sandbox flag" "1" "$(yq -N 'select(.kind=="Secret") | .stringData["config.yaml"]' <<<"$out" | grep -c 'refundsV2: true')"

out=$(render reports dev no-refs-worker.yaml)
check "worker: no Service, literal Secret" "Deployment=1,Secret=1,ServiceAccount=1" "$(kinds <<<"$out")"

out=$(render orders dev dev-orders.yaml --set platform.provisioner=crossplane)
check "crossplane provisioner claims" "PostgresInstance,Queue" \
  "$(yq -N 'select(.apiVersion=="platform.mcafeelabs.io/v1alpha1") | .kind' <<<"$out" | sort | paste -sd, -)"

if helm template bad "$CHART" --set service.name=Bad_Name --set image.repository=x --set image.tag=1 \
  --set service.environment=dev >/dev/null 2>&1; then
  echo "FAIL values schema accepted an invalid service name"; fail=1
else
  echo "ok   values schema rejects invalid names"
fi

echo "--- kubeconform"
for f in "$FIX"/*.yaml; do
  for extra in "" "--set platform.rollouts.enabled=true" "--set platform.provisioner=crossplane"; do
    # shellcheck disable=SC2086
    helm template t "$CHART" -n t -f "$f" $extra
    echo "---"
  done
done | kubeconform -strict -summary -ignore-missing-schemas \
  -skip PostgresInstance,Queue \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  || fail=1

exit $fail
