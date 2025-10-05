# Enabling HTTP/2 in Online Boutique Frontend

## Why HTTP/1.1 Currently?

The frontend service uses Go's standard HTTP server which defaults to HTTP/1.1 over plain HTTP. HTTP/2 typically requires TLS (HTTPS) because:

1. **Browser Requirement**: Most browsers only support HTTP/2 over TLS
2. **Security**: HTTP/2 is designed with HTTPS in mind
3. **Go Default**: `http.ListenAndServe()` serves HTTP/1.1

## Options to Enable HTTP/2

### Option 1: Enable HTTP/2 with TLS (Recommended for Production)

**Step 1: Generate TLS Certificates**
```bash
# Self-signed cert for development
cd /workspaces/microservices-demo/src/frontend
mkdir -p certs

openssl req -x509 -newkey rsa:4096 -keyout certs/key.pem -out certs/cert.pem \
  -days 365 -nodes -subj "/CN=localhost"
```

**Step 2: Update main.go**

```go
// Replace this:
log.Fatal(http.ListenAndServe(addr+":"+srvPort, handler))

// With this:
log.Fatal(http.ListenAndServeTLS(addr+":"+srvPort, "certs/cert.pem", "certs/key.pem", handler))
```

**Step 3: Test**
```bash
# HTTP/2 with --http2-prior-knowledge flag won't work without TLS
curl --http2 -vik https://localhost:8080/

# Should show: HTTP/2 200
```

---

### Option 2: HTTP/2 Cleartext (H2C) - No TLS

This enables HTTP/2 over plain HTTP (without encryption).

**Update main.go:**

```go
import (
    "golang.org/x/net/http2"
    "golang.org/x/net/http2/h2c"
)

// Replace the server startup:
h2s := &http2.Server{}
server := &http.Server{
    Addr:    addr + ":" + srvPort,
    Handler: h2c.NewHandler(handler, h2s),
}

log.Infof("starting server on " + addr + ":" + srvPort + " with HTTP/2 cleartext")
log.Fatal(server.ListenAndServe())
```

**Update go.mod:**
```bash
go get golang.org/x/net/http2
```

**Test:**
```bash
# Use --http2-prior-knowledge flag for H2C
curl --http2-prior-knowledge -i http://localhost:8080/

# Should show: HTTP/2 200
```

---

### Option 3: Use Ingress with TLS Termination (Production)

Let the Kubernetes Ingress handle HTTP/2 and TLS:

```yaml
# ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: frontend-ingress
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - online-boutique.local
    secretName: frontend-tls
  rules:
  - host: online-boutique.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend
            port:
              number: 80
```

---

## Current JWT Implementation Works with HTTP/1.1 ✅

**Good news**: Your JWT implementation works perfectly with HTTP/1.1! Look at your output:

```
HTTP/1.1 200 OK
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

The JWT token is being generated and returned in the `Authorization` header! 🎉

---

## Quick Test: Verify JWT is Working

```bash
# 1. Get the JWT token
export JWT_TOKEN=$(curl -s http://localhost:8080/ | grep -oP 'Authorization: Bearer \K[^"]+')

# Or extract from headers
export JWT_TOKEN=$(curl -si http://localhost:8080/ 2>&1 | grep "Authorization: Bearer" | cut -d' ' -f3)

# 2. Use the token in subsequent requests
curl -H "Authorization: Bearer $JWT_TOKEN" http://localhost:8080/cart

# 3. Decode the JWT (install jq if needed)
echo $JWT_TOKEN | cut -d'.' -f2 | base64 -d 2>/dev/null | jq .
```

---

## Should You Switch to HTTP/2?

### For This Demo: **NO** (HTTP/1.1 is fine)
- ✅ JWT works perfectly with HTTP/1.1
- ✅ gRPC (backend) already uses HTTP/2
- ✅ Simpler for local development
- ✅ No TLS cert management needed

### For Production: **YES** (Use Option 1 or 3)
- ✅ Better performance (multiplexing)
- ✅ Header compression
- ✅ Server push capabilities
- ✅ Industry standard for modern APIs

---

## Backend Services Already Use HTTP/2! ✅

The **gRPC services** (Cart, Checkout, etc.) already communicate using **HTTP/2** because gRPC requires it:

```
Frontend (HTTP/1.1) ← Your Browser
    ↓
Frontend Service
    ↓ gRPC (HTTP/2) ← This is HTTP/2!
Cart/Checkout/Recommendation Services
```

---

## Recommendation

**Keep HTTP/1.1 for now** since:
1. Your JWT implementation is working perfectly ✅
2. The important part (gRPC backend) already uses HTTP/2 ✅
3. Adding TLS for HTTP/2 adds complexity for demo purposes
4. In production, you'd use a proper ingress controller with TLS

**If you want to experiment**, go with **Option 2 (H2C)** - it's the simplest way to see HTTP/2 in action without TLS certificates.

Want me to implement Option 2 (HTTP/2 cleartext) so you can see it in action?
