# Istio mTLS Mental Model

This document explains the two security planes in this workshop:

- East-west traffic inside the cluster (`frontend` <-> `backend`)
- North-south traffic entering the cluster (client -> ingress gateway)

## 1) East-west: Service-to-service mTLS inside mesh

Application code uses HTTP:

- `frontend` calls `http://...backend...:8080`

Network path is mTLS between sidecars:

```text
+------------------+        mTLS (Envoy<->Envoy)        +------------------+
| frontend app     | --HTTP--> [frontend sidecar] =====> | [backend sidecar] --HTTP--> backend app |
| (port 8080)      |                                      | (port 8080)      |
+------------------+                                      +------------------+

Legend:
- --HTTP--> : app to local sidecar (same pod)
- =====>    : encrypted/authenticated mTLS over network
```

Key idea:

- App-level URL is `http://`, but wire traffic between pods is encrypted by Istio sidecars.
- `PeerAuthentication: STRICT` enforces that inbound pod traffic must be mTLS.

## 2) North-south: Client to ingress gateway TLS/mTLS

### SIMPLE mode (server-auth TLS)

```text
Client ---- TLS ----> Istio Ingress Gateway ---- HTTP ----> frontend sidecar -> frontend app
           (validates server cert from go-app-tls secret)
```

- Gateway presents `server.crt/server.key` from secret `go-app-tls`.
- Client verifies server chain with `server-ca.crt` (`curl --cacert ...`).

### MUTUAL mode (client cert required)

```text
Client -- mTLS --> Istio Ingress Gateway ---- HTTP ----> frontend sidecar -> frontend app
        (sends client.crt/key)   (verifies client cert using client-ca.crt in go-app-mtls secret)
```

- Gateway still presents server cert.
- Client also presents `client.crt/client.key`.
- Gateway verifies client certificate against trusted CA (`ca.crt` key in secret).

## 2.1 Beginner walkthrough: certs, secrets, and handshake

Think of this as three boxes:

- Client box (your `curl` command).
- Ingress gateway box (Istio Envoy at cluster edge).
- App box (frontend service inside cluster).

Now map certs/secrets to those boxes:

- `go-app-tls` secret in `istio-system`: contains `tls.crt` + `tls.key`; used by ingress gateway to prove server identity to client.
- `go-app-mtls` secret in `istio-system`: contains `tls.crt` + `tls.key` + `ca.crt`; `tls.crt/tls.key` are server identity, `ca.crt` is trusted client CA for verification.
- Local client files: `server-ca.crt` is used by `curl --cacert` to trust gateway server cert; `client.crt/client.key` are used by `curl --cert/--key` only in MUTUAL mode.

SIMPLE mode handshake (server auth only):

1. Client connects to gateway over HTTPS.
2. Gateway sends cert from `go-app-tls` (`tls.crt`).
3. Client verifies that cert using `server-ca.crt`.
4. If valid, encrypted channel is established.
5. Request is routed to frontend service.

MUTUAL mode handshake (both sides auth):

1. Client connects to gateway over HTTPS.
2. Gateway sends server cert (`tls.crt`) as above.
3. Gateway also asks client to send certificate.
4. Client sends `client.crt` and proves key ownership with `client.key`.
5. Gateway verifies client cert against trusted CA in secret key `ca.crt` (`go-app-mtls`).
6. If both validations pass, request is accepted and routed to frontend service.

Failure mapping (common beginner confusion):

- If `credentialName` is wrong or secret missing in `istio-system`: TLS listener fails or handshake fails.
- If client uses wrong `--cacert`: `unable to get local issuer certificate`.
- If gateway is `MUTUAL` but client does not send `--cert/--key`: handshake rejected.
- If ingress service has no endpoints: connection refused/timeouts before TLS starts.

## 3) Who issues which certificate?

There are two independent issuers in this demo:

- Mesh workload cert issuer: Istio CA (`istiod`) for sidecar identities (SPIFFE).
- Ingress cert issuer (local demo): local OpenSSL CA from `docs/certs/generate-local-certs.sh`.

Optional production-like setup:

- Ingress cert issuer can be Let’s Encrypt via cert-manager when you own a real domain.

## 4) Why this separation matters

- Step 4 mTLS success does not depend on ingress secrets.
- Ingress TLS/mTLS success does not prove mesh mTLS between services.
- You need both configured to secure both traffic directions.

## 5) Fast checks during demo

- Mesh cert present on sidecar:

```bash
istioctl proxy-config secret deploy/goapp-go-sample-app-frontend -n go-app
```

- Ingress secret present:

```bash
kubectl -n istio-system get secret go-app-tls
kubectl -n istio-system get secret go-app-mtls
```

- Ingress endpoints ready:

```bash
kubectl -n istio-system get endpoints istio-ingressgateway
```

## 6) Helm chart mental model (what each file does)

Chart root:

- `helm/go-sample-app/Chart.yaml`: chart metadata and version (`name`, `version`, `appVersion`).
- `helm/go-sample-app/values.yaml`: default config for image, frontend/backend, curl client, and Istio flags (`host`, `tls.mode`, `credentialName`, `mtlsStrict`).
- `helm/go-sample-app/values-ingress-simple-tls.yaml`: override to force ingress mode `SIMPLE`.
- `helm/go-sample-app/values-ingress-mtls.yaml`: override to force ingress mode `MUTUAL`.

Templates:

- `helm/go-sample-app/templates/_helpers.tpl`: reusable name and label helpers for consistent object naming.
- `helm/go-sample-app/templates/deployment.yaml`: creates frontend/backend deployments and optional curl test deployment.
- `helm/go-sample-app/templates/service.yaml`: creates frontend/backend ClusterIP services.
- `helm/go-sample-app/templates/istio-gateway.yaml`: creates `Gateway`, `VirtualService`, `DestinationRule`, and optional `PeerAuthentication` for mesh/ingress security behavior.

How to think about rendering:

- Base install uses `values.yaml` (SIMPLE TLS by default).
- Add `-f values-ingress-mtls.yaml` when you want client cert auth at ingress.
- The same app workloads stay the same; only gateway TLS behavior changes.


## 7) Deployment and Service mental model

Traffic flow:

1. Client (or gateway) calls service DNS, e.g. goapp-go-sample-app-frontend.go-app.svc.cluster.local:8080.
2. Kubernetes Service picks one matching frontend Pod.
3. Inside frontend Pod, app handles request.
4. For /call-backend, frontend app calls backend service DNS.
5. Backend Service routes to one backend Pod.

Why this is useful:

- Pods can restart/change IPs; Service DNS stays stable.
- Scaling Deployments (replicas) automatically adds/removes service endpoints.
- Istio routing objects target Services, not individual Pod IPs, so traffic policy remains stable.
