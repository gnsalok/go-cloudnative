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
