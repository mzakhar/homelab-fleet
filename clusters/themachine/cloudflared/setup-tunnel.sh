#!/usr/bin/env bash
# Idempotent Cloudflare Tunnel bootstrap for themachine.
#
# Creates (or reuses) a remotely-managed tunnel named "themachine", points
# public zakharhome.org hostnames at in-cluster Traefik, creates proxied DNS CNAMEs,
# and prints the kubectl command to install the tunnel-token secret.
#
# Requires: curl, jq, and CLOUDFLARE_API_TOKEN with scopes:
#   Account > Cloudflare Tunnel > Edit
#   Zone    > DNS               > Edit   (zone: zakharhome.org)
#
# Usage: CLOUDFLARE_API_TOKEN=... ./setup-tunnel.sh
set -euo pipefail

: "${CLOUDFLARE_API_TOKEN:?set CLOUDFLARE_API_TOKEN}"

API="https://api.cloudflare.com/client/v4"
TUNNEL_NAME="themachine"
ZONE_NAME="zakharhome.org"
# All hostnames route to in-cluster Traefik; host-based Ingress does the rest.
HOSTNAMES=(
  "${ZONE_NAME}"
  "synth.${ZONE_NAME}"
  "books.${ZONE_NAME}"
  "cleanmail.${ZONE_NAME}"
  "dashboard.${ZONE_NAME}"
)
ORIGIN_SERVICE="http://traefik.kube-system.svc.cluster.local:80"

cf() {
  local method=$1 path=$2 body=${3:-}
  local args=(-sS -X "$method" "$API$path" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")
  [ -n "$body" ] && args+=(--data "$body")
  local resp
  resp=$(curl "${args[@]}")
  if [ "$(jq -r '.success' <<<"$resp")" != "true" ]; then
    echo "Cloudflare API error on $method $path:" >&2
    jq -r '.errors' <<<"$resp" >&2
    exit 1
  fi
  jq '.result' <<<"$resp"
}

echo "==> Resolving account and zone"
ZONE=$(cf GET "/zones?name=$ZONE_NAME")
ZONE_ID=$(jq -r '.[0].id // empty' <<<"$ZONE")
ACCOUNT_ID=$(jq -r '.[0].account.id // empty' <<<"$ZONE")
[ -n "$ZONE_ID" ] || { echo "zone $ZONE_NAME not found" >&2; exit 1; }
[ -n "$ACCOUNT_ID" ] || { echo "could not resolve account id from zone" >&2; exit 1; }
echo "    account=$ACCOUNT_ID zone=$ZONE_ID"

echo "==> Tunnel: $TUNNEL_NAME"
TUNNEL_ID=$(cf GET "/accounts/$ACCOUNT_ID/cfd_tunnel?name=$TUNNEL_NAME&is_deleted=false" \
  | jq -r '.[0].id // empty')
if [ -z "$TUNNEL_ID" ]; then
  TUNNEL_ID=$(cf POST "/accounts/$ACCOUNT_ID/cfd_tunnel" \
    "{\"name\":\"$TUNNEL_NAME\",\"config_src\":\"cloudflare\"}" | jq -r '.id')
  echo "    created tunnel $TUNNEL_ID"
else
  echo "    reusing tunnel $TUNNEL_ID"
fi

echo "==> Ingress config: ${HOSTNAMES[*]} -> $ORIGIN_SERVICE"
INGRESS_RULES=$(printf '%s\n' "${HOSTNAMES[@]}" | jq -R --arg svc "$ORIGIN_SERVICE" \
  '{hostname: ., service: $svc}' | jq -s '. + [{service: "http_status:404"}]')
cf PUT "/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/configurations" \
  "$(jq -n --argjson rules "$INGRESS_RULES" '{config: {ingress: $rules}}')" >/dev/null
echo "    applied"

for HOSTNAME in "${HOSTNAMES[@]}"; do
  echo "==> DNS: $HOSTNAME CNAME ${TUNNEL_ID}.cfargotunnel.com (proxied)"
  RECORD_ID=$(cf GET "/zones/$ZONE_ID/dns_records?type=CNAME&name=$HOSTNAME" \
    | jq -r '.[0].id // empty')
  DNS_BODY=$(jq -n --arg name "$HOSTNAME" --arg target "${TUNNEL_ID}.cfargotunnel.com" \
    '{type:"CNAME", name:$name, content:$target, proxied:true, ttl:1}')
  if [ -z "$RECORD_ID" ]; then
    cf POST "/zones/$ZONE_ID/dns_records" "$DNS_BODY" >/dev/null
    echo "    created"
  else
    cf PUT "/zones/$ZONE_ID/dns_records/$RECORD_ID" "$DNS_BODY" >/dev/null
    echo "    updated"
  fi
done

echo "==> Tunnel token"
TOKEN=$(cf GET "/accounts/$ACCOUNT_ID/cfd_tunnel/$TUNNEL_ID/token" | jq -r '.')

cat <<EOF

Done. On themachine, install the token secret (cloudflared deployment reads it):

  kubectl create namespace cloudflared --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n cloudflared create secret generic cloudflared-tunnel-token \\
    --from-literal=token='$TOKEN' \\
    --dry-run=client -o yaml | kubectl apply -f -

Then let Flux reconcile (or: flux reconcile kustomization flux-system --with-source)
and verify: ${HOSTNAMES[*]/#/https:\/\/}
EOF
