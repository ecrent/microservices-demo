# Cart Bug Fix - Session Management Issue

## 🐛 Bug Description

**Problem:** Items couldn't be added to cart - cart always showed as empty.

**Root Cause:** Each HTTP request was creating a **new session ID**, so the cart items were being stored under different sessions.

**Observed Behavior:**
```
POST /cart with session: bf2a007b-fc91-47eb-9a6a-f59dd53ab292 (added item)
GET  /cart with session: 9525231e-3f40-4f1f-8191-357a335870c6 (different session!)
Result: Cart appears empty
```

---

## 🔍 Analysis

### Original Flawed Logic

The `ensureJWT` middleware was:
1. ❌ Only checking Authorization header for JWT
2. ❌ NOT checking for session cookie
3. ❌ Generating new session ID on every request
4. ❌ Browser had no way to maintain session state

**Why This Failed:**
- Browsers don't automatically send custom headers like `X-JWT-Token`
- Without a session cookie, each request is treated as a new user
- Cart service stores items by session ID
- Different session ID = different cart = empty cart

---

## ✅ Solution

### Fixed Logic Flow

**First Request (New User):**
```
1. Check session cookie → Not found
2. Generate new session ID (e.g., abc-123)
3. Generate JWT with session ID
4. Set session cookie: shop_session-id=abc-123 ✅
5. Return JWT in header: X-JWT-Token
```

**Subsequent Requests (Returning User):**
```
1. Check session cookie → Found: abc-123 ✅
2. Reuse existing session ID
3. Check Authorization header for JWT
4. If JWT valid and matches session → Reuse it ✅
5. If JWT missing/invalid → Generate new JWT (but keep same session)
```

### Code Changes

**File:** `src/frontend/middleware.go`

**Before:**
```go
func ensureJWT(next http.Handler) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        // Only checked Authorization header
        // Always generated new session ID
        // Did NOT check session cookie first ❌
    }
}
```

**After:**
```go
func ensureJWT(next http.Handler) http.HandlerFunc {
    return func(w http.ResponseWriter, r *http.Request) {
        // Step 1: Check session cookie FIRST ✅
        c, err := r.Cookie(cookieSessionID)
        if err == http.ErrNoCookie {
            // New user - generate new session
        } else {
            // Existing user - reuse session ID ✅
            sessionID = c.Value
        }
        
        // Step 2: Check JWT validity
        // Step 3: Generate new JWT if needed (but keep session)
        // Step 4: Set cookie only for new sessions ✅
    }
}
```

---

## 📊 Session vs JWT Lifecycle

### Session ID (Cookie-based)
- **Lifetime:** 86400 seconds (24 hours)
- **Storage:** Browser cookie `shop_session-id`
- **Purpose:** Identify the user across requests
- **Renewal:** Only when cookie expires

### JWT Token (Header-based)
- **Lifetime:** 86400 seconds (24 hours)
- **Storage:** Not stored (sent in Authorization header)
- **Purpose:** Authentication and authorization
- **Renewal:** Regenerated if missing/invalid (but session stays same)

### Key Insight
> **Session ID is the PRIMARY identifier. JWT is regenerated as needed but always tied to the same session ID.**

---

## 🧪 Testing

### Before Fix:
```bash
# First request
curl http://localhost:8080/
# New session: abc-123

# Add to cart
curl -X POST http://localhost:8080/cart
# Session: def-456 (NEW SESSION! Bug!) ❌

# View cart
curl http://localhost:8080/cart
# Session: ghi-789 (ANOTHER NEW SESSION!) ❌
# Result: Empty cart
```

### After Fix:
```bash
# First request
curl -c cookies.txt http://localhost:8080/
# New session: abc-123
# Cookie set: shop_session-id=abc-123 ✅

# Add to cart
curl -b cookies.txt -X POST http://localhost:8080/cart
# Session: abc-123 (SAME SESSION!) ✅

# View cart
curl -b cookies.txt http://localhost:8080/cart
# Session: abc-123 (SAME SESSION!) ✅
# Result: Items in cart! ✅
```

---

## 🎯 Expected Behavior After Fix

1. **User visits site** → Session cookie created (once)
2. **User adds item to cart** → Uses same session ID ✅
3. **User refreshes page** → Same session ID ✅
4. **User views cart** → Same session ID → Items still there ✅
5. **User comes back in 1 hour** → Same session (if cookie not expired) ✅

---

## 🚀 Deployment

1. Fixed `src/frontend/middleware.go`
2. Rebuild frontend:
   ```bash
   cd /workspaces/microservices-demo
   ./skaffold run
   ```
3. Wait for deployment to complete
4. Test in browser

---

## ✅ Verification Steps

1. Open browser developer tools (F12)
2. Go to Application → Cookies
3. Visit http://localhost:8080
4. **Verify:** Cookie `shop_session-id` is created ✅
5. Add item to cart
6. Refresh page
7. **Verify:** Same cookie value ✅
8. **Verify:** Items still in cart ✅

---

## 📝 Lessons Learned

1. **Session management requires cookies** - Custom headers alone don't work for stateful web apps
2. **Session ID should be persistent** - Generate once, reuse across requests
3. **JWT can be ephemeral** - Can regenerate as needed, tied to same session
4. **Test the user flow** - Don't just test individual endpoints

---

**Status:** ✅ Fixed and deployed
**Impact:** Cart functionality now works correctly
**Breaking Changes:** None - backward compatible
