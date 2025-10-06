# JWT Adventure: Complete Customer Shopping Journey

## 🛍️ Customer Journey Trace

### Timeline of Events

```
👤 Customer arrives at Online Boutique website
    ↓
🏠 Step 1: Homepage Visit
    ↓
🛒 Step 2: View Cart
    ↓
➕ Step 3: Add Item to Cart
    ↓
💳 Step 4: Place Order
    ↓
✅ Step 5: Order Confirmation
```

---

## 🔐 JWT Adventure (Detailed Flow)

### **Step 1: Customer Lands on Homepage** 
**Action:** Browser sends HTTP GET request to `/`

**What Happens in Frontend:**
1. ✅ Frontend checks for existing JWT cookie
2. ✅ No JWT found → Generates new JWT
3. ✅ Signs JWT with RSA private key (RS256)
4. ✅ Sets cookie: `shop_jwt` (HttpOnly, SameSite=Strict, 5-min expiry)

**JWT Payload Generated:**
```json
{
  "session_id": "1aa2f09b-3731-4855-b5c8-4e82f0f82a56",
  "name": "Jane Doe",
  "market_id": "US",
  "currency": "USD",
  "cart_id": "cart-uuid-1aa2f09b",
  "iss": "https://auth.hipstershop.com",
  "sub": "urn:hipstershop:user:1aa2f09b-3731-4855-b",
  "aud": ["urn:hipstershop:api"],
  "exp": 1759775814,    // 5 minutes from now
  "iat": 1759775514,
  "jti": "f0775671-3b0b-4505-97c5-7f97bde535cc"
}
```

**Response to Browser:**
```
HTTP/1.1 200 OK
Set-Cookie: shop_jwt=eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...; Max-Age=300; HttpOnly; SameSite=Strict
```

---

### **Step 2: View Cart**
**Action:** Browser sends HTTP GET request to `/cart`

**Frontend → CartService Flow:**

```
┌──────────────────────────────────────────────────────────┐
│ Browser                                                  │
│ Sends: Cookie: shop_jwt=eyJhbGciOiJSUzI1NiIsInR...      │
└────────────────────┬─────────────────────────────────────┘
                     │ HTTP GET /cart
                     ↓
┌──────────────────────────────────────────────────────────┐
│ Frontend Service (Go)                                    │
│ 1. Extracts JWT from cookie                             │
│ 2. Validates JWT (signature ✓, expiration ✓, name ✓)   │
│ 3. Calls CartService.GetCart via gRPC                   │
│ 4. Adds JWT to gRPC metadata                            │
└────────────────────┬─────────────────────────────────────┘
                     │ gRPC Call
                     │ metadata: {
                     │   "authorization": "Bearer eyJhbG..."
                     │ }
                     ↓
┌──────────────────────────────────────────────────────────┐
│ CartService (C#)                                         │
│ ✅ Receives JWT in metadata                             │
│ ✅ Logs: "[JWT] Received JWT in GetCart: Bearer ..."   │
│ ✅ Returns cart items for session                       │
└──────────────────────────────────────────────────────────┘
```

**CartService Log Evidence:**
```
[JWT] Received JWT in /hipstershop.CartService/GetCart: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzZX...
GetCartAsync called with userId=1aa2f09b-3731-4855-b5c8-4e82f0f82a56
```

---

### **Step 3: Add Item to Cart**
**Action:** Browser sends HTTP POST to `/cart` with product_id=OLJCESPC7Z, quantity=1

**Frontend → CartService Flow:**

```
┌──────────────────────────────────────────────────────────┐
│ Browser                                                  │
│ POST /cart                                               │
│ Cookie: shop_jwt=eyJhbGciOiJSUzI1NiIsInR...             │
│ Body: product_id=OLJCESPC7Z&quantity=1                  │
└────────────────────┬─────────────────────────────────────┘
                     ↓
┌──────────────────────────────────────────────────────────┐
│ Frontend Service                                         │
│ 1. Validates JWT from cookie                            │
│ 2. Calls CartService.AddItem via gRPC                   │
│ 3. Adds JWT to metadata                                 │
└────────────────────┬─────────────────────────────────────┘
                     │ gRPC metadata: authorization: Bearer <JWT>
                     ↓
┌──────────────────────────────────────────────────────────┐
│ CartService                                              │
│ ✅ Receives JWT                                          │
│ ✅ Logs: "[JWT] Received JWT in AddItem..."            │
│ ✅ Adds product to cart                                 │
└──────────────────────────────────────────────────────────┘
```

**CartService Log Evidence:**
```
[JWT] Received JWT in /hipstershop.CartService/AddItem: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzZX...
AddItemAsync called with userId=1aa2f09b-3731-4855-b5c8-4e82f0f82a56, productId=OLJCESPC7Z, quantity=1
```

---

### **Step 4: Place Order (THE BIG ONE! 🚀)**
**Action:** Browser sends HTTP POST to `/cart/checkout` with shipping/payment info

**Multi-Service JWT Journey:**

```
┌──────────────────────────────────────────────────────────┐
│ Browser                                                  │
│ POST /cart/checkout                                      │
│ Cookie: shop_jwt=eyJhbGciOiJSUzI1NiIsInR...             │
└────────────────────┬─────────────────────────────────────┘
                     ↓
┌──────────────────────────────────────────────────────────┐
│ Frontend Service                                         │
│ 1. Validates JWT                                         │
│ 2. Calls CheckoutService.PlaceOrder via gRPC            │
│ 3. ✅ Forwards JWT in metadata                          │
└────────────────────┬─────────────────────────────────────┘
                     │ gRPC with JWT
                     ↓
┌──────────────────────────────────────────────────────────┐
│ CheckoutService (Go) - THE ORCHESTRATOR                 │
│ ✅ Receives JWT from frontend                           │
│ Now CheckoutService calls 6 downstream services:        │
│                                                          │
│ [PlaceOrder] user_id="..." user_currency="TRY"          │
└──┬───┬───┬───┬───┬────────────────────────────────────┬──┘
   │   │   │   │   │                                    │
   │   │   │   │   │  All with JWT forwarded!           │
   ↓   ↓   ↓   ↓   ↓                                    ↓
┌────┐ ┌─────┐ ┌────┐ ┌─────┐ ┌────────┐ ┌──────────────┐
│Cart│ │Ship │ │Pay │ │Email│ │Currency│ │ProductCatalog│
│Svc │ │Svc  │ │Svc │ │Svc  │ │Svc     │ │Svc           │
└────┘ └─────┘ └────┘ └─────┘ └────────┘ └──────────────┘
  ✅     ✅      ✅     ✅       ✅          ✅
  JWT    JWT    JWT    JWT      JWT        JWT
  rcvd   rcvd   rcvd   rcvd     rcvd       rcvd
```

**Detailed Checkout Flow:**

1. **CheckoutService → CartService.GetCart**
   - ✅ JWT forwarded from checkoutservice
   - CartService logs: `[JWT] Received JWT in /hipstershop.CartService/GetCart`

2. **CheckoutService → ShippingService.GetQuote**
   - ✅ JWT forwarded
   - Gets shipping cost estimate

3. **CheckoutService → PaymentService.Charge**
   - ✅ JWT forwarded
   - Processes payment
   - CheckoutService logs: `payment went through (transaction_id: 15aca15f...)`

4. **CheckoutService → ShippingService.ShipOrder**
   - ✅ JWT forwarded
   - Creates tracking ID

5. **CheckoutService → CartService.EmptyCart**
   - ✅ JWT forwarded (MULTI-HOP VERIFIED!)
   - CartService logs: `[JWT] Received JWT in /hipstershop.CartService/EmptyCart`

6. **CheckoutService → EmailService.SendOrderConfirmation**
   - ✅ JWT forwarded
   - Sends confirmation email
   - CheckoutService logs: `order confirmation email sent to "brandihall@example.com"`

**Log Evidence - CheckoutService:**
```
[PlaceOrder] user_id="a0532aee-2eeb-42d3-a4d4-88a9c8d8df03" user_currency="TRY"
payment went through (transaction_id: 15aca15f-a3e6-45a3-947e-fad6b9e606cb)
order confirmation email sent to "brandihall@example.com"
```

**Log Evidence - CartService (receiving JWT from CheckoutService):**
```
[JWT] Received JWT in /hipstershop.CartService/EmptyCart: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9.eyJzZX...
EmptyCartAsync called with userId=a0532aee-2eeb-42d3-a4d4-88a9c8d8df03
```

---

### **Step 5: Continue Shopping**
**Action:** Browser navigates back to homepage

**What Happens:**
1. Browser still has valid JWT cookie (5-min expiry)
2. Frontend validates existing JWT ✅
3. No new JWT generated (reuses existing one)
4. Customer can continue shopping with same JWT

---

## 🎯 JWT Adventure Summary

### JWT Lifecycle in This Journey:

| Step | Action | JWT Status | Services Involved |
|------|--------|------------|-------------------|
| 1 | Homepage Visit | **Generated** | Frontend |
| 2 | View Cart | **Sent** | Frontend → CartService |
| 3 | Add Item | **Sent** | Frontend → CartService |
| 4 | Checkout | **Sent & Forwarded** | Frontend → Checkout → 6 services |
| 5 | Continue Shopping | **Reused** | Frontend (validates existing) |

### Total JWT Hops in Checkout Flow:

```
Frontend (hop 0 - origin)
   ↓
CheckoutService (hop 1 - receives JWT)
   ↓
   ├→ CartService (hop 2 - multi-hop! 🎉)
   ├→ ShippingService (hop 2)
   ├→ PaymentService (hop 2)
   ├→ EmailService (hop 2)
   ├→ CurrencyService (hop 2)
   └→ ProductCatalogService (hop 2)
```

### Key Observations:

✅ **Single JWT** used for entire shopping session (until 5-min expiry)
✅ **Multi-hop propagation** verified (Frontend → Checkout → Cart)
✅ **All gRPC calls** include JWT in metadata
✅ **No service calls** without JWT (except health checks)
✅ **Automatic forwarding** via interceptors (no manual code needed)

---

## 🔍 How to Verify This Journey Yourself

### 1. Check Browser Cookie
```bash
curl -c /tmp/cookies.txt http://localhost:8080/
cat /tmp/cookies.txt | grep shop_jwt
```

### 2. Decode JWT Payload
```bash
# Extract JWT payload (between first and second dot)
# Use online JWT decoder: https://jwt.io
# Or use: echo "<payload>" | base64 -d
```

### 3. Watch CartService Logs
```bash
kubectl logs -l app=cartservice --tail=50 -f | grep JWT
```

### 4. Watch CheckoutService Logs
```bash
kubectl logs -l app=checkoutservice --tail=50 -f
```

### 5. Simulate Shopping Journey
```bash
# Visit homepage (JWT generated)
curl -c /tmp/cookies.txt http://localhost:8080/

# View cart (JWT sent)
curl -b /tmp/cookies.txt http://localhost:8080/cart

# Add item (JWT sent)
curl -b /tmp/cookies.txt -X POST http://localhost:8080/cart \
  -d "product_id=OLJCESPC7Z&quantity=1"

# Checkout (JWT forwarded to 6 services!)
curl -b /tmp/cookies.txt -X POST http://localhost:8080/cart/checkout \
  -d "email=test@example.com&street_address=123 Main&..."
```

---

## 🎉 Conclusion

The JWT successfully travels through the entire customer journey:

1. **Born** at homepage (frontend generates it)
2. **Lives** in browser cookie (HttpOnly, secure)
3. **Travels** to backend services (gRPC metadata)
4. **Multiplies** during checkout (forwarded to 6 services)
5. **Persists** for 5 minutes (then regenerated)

This demonstrates a **real-world microservices JWT propagation pattern** where:
- Frontend acts as the authentication gateway
- JWT carries user context through the service mesh
- Services automatically forward JWT without custom code
- Multi-hop propagation works seamlessly
