# Headless Service and Pod-to-Pod mTLS (No Istio)

## 1) What is a headless service?

A **headless Service** is a Service with `clusterIP: None`.

- Kubernetes does **not** allocate a virtual IP (VIP) for it.
- DNS returns the **individual Pod IPs** behind the Service.
- For StatefulSets, each pod also gets a stable DNS name:
  - `<pod-name>.<headless-service>.<namespace>.svc.cluster.local`

This is ideal when clients need direct pod identity (common in databases, brokers, quorum systems).

## 2) Difference from a normal Service

### Normal Service (`ClusterIP`)
- Has one stable virtual IP.
- DNS resolves to that Service IP.
- kube-proxy load-balances traffic to backend pods.
- Good for stateless request/response workloads.

### Headless Service (`clusterIP: None`)
- No virtual IP.
- DNS resolves to pod IP(s) directly.
- Client can connect to a specific pod by DNS.
- Good for StatefulSet peer-to-peer communication.

## 3) Exercise goal

Create pod-to-pod **mTLS** for a StatefulSet without Istio.

- Each pod gets a unique cert signed by a shared demo CA.
- Each pod runs an OpenSSL TLS server that **requires client certs**.
- Pods authenticate each other directly.

## 4) Files in this exercise

- `manifests/01-namespace.yaml`
- `manifests/02-services.yaml`
- `manifests/03-configmap-scripts.yaml`
- `manifests/04-statefulset.yaml`

## 5) Deploy

### 5.1 Create namespace

```bash
kubectl apply -f docs/exercises/statefulset-headless-mtls/manifests/01-namespace.yaml
```

### 5.2 Create demo CA secret (one time)

```bash
openssl req -x509 -newkey rsa:4096 -sha256 -days 365 -nodes \
  -subj "/CN=stateful-mtls-demo-ca" \
  -keyout /tmp/mtls-demo-ca.key \
  -out /tmp/mtls-demo-ca.crt

kubectl -n stateful-mtls create secret generic mtls-demo-ca \
  --from-file=ca.crt=/tmp/mtls-demo-ca.crt \
  --from-file=ca.key=/tmp/mtls-demo-ca.key
```

### 5.3 Apply services, scripts, and StatefulSet

```bash
kubectl apply -f docs/exercises/statefulset-headless-mtls/manifests/02-services.yaml
kubectl apply -f docs/exercises/statefulset-headless-mtls/manifests/03-configmap-scripts.yaml
kubectl apply -f docs/exercises/statefulset-headless-mtls/manifests/04-statefulset.yaml
```

### 5.4 Wait for pods

```bash
kubectl rollout status statefulset/mtls-demo -n stateful-mtls
kubectl get pods -n stateful-mtls -o wide
```

## 6) Verify headless vs normal service behavior

Check endpoints:

```bash
kubectl get endpoints -n stateful-mtls mtls-demo-headless
kubectl get endpoints -n stateful-mtls mtls-demo
```

DNS check from temporary pod:

```bash
kubectl run -it --rm dns-test -n stateful-mtls --restart=Never \
  --image=busybox:1.36 -- nslookup mtls-demo-headless.stateful-mtls.svc.cluster.local

kubectl run -it --rm dns-test -n stateful-mtls --restart=Never \
  --image=busybox:1.36 -- nslookup mtls-demo.stateful-mtls.svc.cluster.local
```

Expected:
- Headless name resolves to pod IPs.
- Normal service resolves to one ClusterIP.

## 7) Verify pod-to-pod mTLS

### 7.1 Successful mTLS from pod `mtls-demo-0` to `mtls-demo-1`

```bash
kubectl exec -n stateful-mtls mtls-demo-0 -- sh -c '
  echo | openssl s_client \
    -connect mtls-demo-1.mtls-demo-headless.stateful-mtls.svc.cluster.local:8443 \
    -servername mtls-demo-1.mtls-demo-headless.stateful-mtls.svc.cluster.local \
    -cert /certs/tls.crt \
    -key /certs/tls.key \
    -CAfile /certs/ca.crt \
    -verify_return_error 2>&1 | grep -E "Verify return code|subject="
'
```

Expected: `Verify return code: 0 (ok)`.

### 7.2 Failure case (no client cert)

```bash
kubectl exec -n stateful-mtls mtls-demo-0 -- sh -c '
  echo | openssl s_client \
    -connect mtls-demo-1.mtls-demo-headless.stateful-mtls.svc.cluster.local:8443 \
    -servername mtls-demo-1.mtls-demo-headless.stateful-mtls.svc.cluster.local \
    -CAfile /certs/ca.crt \
    -verify_return_error
'
```

Expected handshake failure because server requires a client certificate.

## 8) Important note

This lab mounts the CA **private key** into pods for easy demo certificate issuance.

That is **not** a production pattern.
For production, use cert-manager, SPIRE, Vault PKI, or another secure CA workflow where private keys are protected and short-lived identities are issued safely.

## 9) Cleanup

```bash
kubectl delete namespace stateful-mtls
rm -f /tmp/mtls-demo-ca.key /tmp/mtls-demo-ca.crt
```
