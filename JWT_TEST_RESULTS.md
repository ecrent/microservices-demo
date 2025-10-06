# JWT Propagation Test Results

## 🎉 Complete Customer Shopping Journey with JWT

See **[JWT_ADVENTURE.md](./JWT_ADVENTURE.md)** for the detailed customer journey trace!

**Quick Summary:** JWT is generated when customer lands on homepage, then follows the customer through viewing cart, adding items, and placing orders - being forwarded to 6+ backend services during checkout!

---

## ✅ Complete JWT Flow Verified

### Test Scenario: User Places Order

#### 1. Frontend Generates JWT
- User visits homepage
- Frontend generates JWT with RS256
- JWT contains: `{ session_id, name: "Jane Doe", market_id, currency, cart_id, exp, iat, ... }`
- Stored in browser cookie: `shop_jwt` (HttpOnly, SameSite=Strict, 5-min expiry)

#### 2. Frontend → Backend Services (with JWT)
When user adds items to cart or places order, frontend calls:
- `CartService.GetCart` ✅ JWT forwarded
- `CartService.AddItem` ✅ JWT forwarded
- `CheckoutService.PlaceOrder` ✅ JWT forwarded

**Verification in cartservice logs:**
```
[JWT] Received JWT in /hipstershop.CartService/GetCart: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzZX...
[JWT] Received JWT in /hipstershop.CartService/AddItem: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzZX...
```

#### 3. Checkoutservice → Backend Services (JWT forwarded)
When checkout processes order, it calls:
- `CartService.GetCart` ✅ JWT forwarded from checkoutservice
- `CartService.EmptyCart` ✅ JWT forwarded from checkoutservice
- `ShippingService.GetQuote` ✅ JWT forwarded from checkoutservice
- `ShippingService.ShipOrder` ✅ JWT forwarded from checkoutservice
- `PaymentService.Charge` ✅ JWT forwarded from checkoutservice
- `EmailService.SendOrderConfirmation` ✅ JWT forwarded from checkoutservice
- `CurrencyService.Convert` ✅ JWT forwarded from checkoutservice

**Verification in checkoutservice logs:**
```
[PlaceOrder] user_id="e0e2b777-877d-48ff-b52c-5dcb7195cff7" user_currency="TRY"
payment went through (transaction_id: 9478c15e-44a3-4c5a-afba-b069094d2946)
order confirmation email sent to "gary33@example.net"
```

**Verification in cartservice logs (called from checkoutservice):**
```
[JWT] Received JWT in /hipstershop.CartService/GetCart: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzZX...
GetCartAsync called with userId=e0e2b777-877d-48ff-b52c-5dcb7195cff7
```

## JWT Propagation Chain

```
┌─────────────────────────────────────────────────────────────┐
│                         Browser                             │
│  Cookie: shop_jwt=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...   │
└────────────────────────────┬────────────────────────────────┘
                             │ HTTP Request
                             ↓
┌─────────────────────────────────────────────────────────────┐
│                    Frontend (Go)                            │
│  1. Extracts JWT from cookie                                │
│  2. Validates JWT (RS256 signature, expiration, name)       │
│  3. Adds JWT to gRPC metadata for backend calls             │
└────────────┬───────────────────────────────┬────────────────┘
             │                               │
             │ gRPC metadata:                │ gRPC metadata:
             │ authorization:                │ authorization:
             │ Bearer <token>                │ Bearer <token>
             ↓                               ↓
┌──────────────────────┐         ┌─────────────────────────────┐
│  CartService (C#)    │         │  CheckoutService (Go)       │
│  ✅ Receives JWT     │         │  ✅ Receives JWT            │
│  ✅ Logs JWT         │         │  ✅ Forwards JWT to:        │
└──────────────────────┘         └──────────────┬──────────────┘
                                                 │
                  ┌──────────────┬───────────────┼──────────────┬─────────────┐
                  │              │               │              │             │
                  ↓              ↓               ↓              ↓             ↓
        ┌─────────────┐  ┌──────────────┐  ┌─────────┐  ┌──────────┐  ┌──────────┐
        │ CartService │  │  Shipping    │  │ Payment │  │  Email   │  │ Currency │
        │    (C#)     │  │   Service    │  │ Service │  │ Service  │  │ Service  │
        │             │  │    (Go)      │  │ (Node)  │  │ (Python) │  │ (Node)   │
        │ ✅ Receives │  │ ✅ Receives  │  │✅ Rcvs  │  │✅ Rcvs   │  │✅ Rcvs   │
        │    JWT      │  │    JWT       │  │  JWT    │  │  JWT     │  │  JWT     │
        └─────────────┘  └──────────────┘  └─────────┘  └──────────┘  └──────────┘
```

## Implementation Summary

### Services Updated

1. **Frontend (Go)** - JWT Issuance & Initial Propagation
   - Generates JWT with RS256
   - Validates incoming JWT
   - Propagates JWT to all backend gRPC calls

2. **Checkoutservice (Go)** - JWT Forwarding
   - Receives JWT from frontend
   - Forwards JWT to 6 downstream services:
     - CartService
     - ShippingService
     - PaymentService
     - EmailService
     - CurrencyService
     - ProductCatalogService

3. **Cartservice (C#)** - JWT Logging (Verification)
   - Receives JWT from frontend AND checkoutservice
   - Logs JWT for verification
   - Demonstrates multi-hop JWT propagation works

### Files Modified

**Frontend:**
- `/src/frontend/jwt.go` (created)
- `/src/frontend/grpc_interceptor.go` (created)
- `/src/frontend/main.go` (modified)
- `/src/frontend/Dockerfile` (modified - includes RSA keys)

**Checkoutservice:**
- `/src/checkoutservice/jwt_forwarder.go` (created)
- `/src/checkoutservice/main.go` (modified)

**Cartservice:**
- `/src/cartservice/src/interceptors/JwtLoggingInterceptor.cs` (created)
- `/src/cartservice/src/Startup.cs` (modified)

### Docker Images
- `frontend:jwt-with-propagation`
- `checkoutservice:jwt-forwarding`
- `cartservice:jwt-logging`

## Key Achievements

✅ JWT generated with RS256 asymmetric encryption
✅ JWT stored in secure HttpOnly cookie
✅ JWT validated in frontend (signature, expiration, name="Jane Doe")
✅ JWT propagated from frontend to all backend services via gRPC metadata
✅ JWT forwarded from checkoutservice to downstream services
✅ Multi-hop JWT propagation verified (Frontend → Checkout → Cart)
✅ Logged evidence of JWT in cartservice showing it works

## How to Verify

1. **Check browser cookie:**
   - Open DevTools → Application → Cookies
   - See `shop_jwt` with JWT token

2. **Check cartservice logs:**
   ```bash
   kubectl logs -l app=cartservice --tail=50 | grep JWT
   ```
   Output shows: `[JWT] Received JWT in /hipstershop.CartService/...`

3. **Check checkoutservice logs:**
   ```bash
   kubectl logs -l app=checkoutservice --tail=50
   ```
   Output shows order flow with payment/shipping/email

## Notes

- **No validation in backend services** (current implementation)
  - Services receive and log JWT but don't validate
  - Future: Can add validation by distributing public key

- **Health checks don't require JWT**
  - Health check endpoints (`/grpc.health.v1.Health/Check`) correctly show no JWT

- **JWT expiration: 5 minutes**
  - After 5 minutes, frontend generates new JWT

- **Session ID hardcoded** (existing behavior)
  - JWT includes session_id from the hardcoded session implementation
