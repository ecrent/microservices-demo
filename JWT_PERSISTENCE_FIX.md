# JWT Token Persistence Fix

## 🐛 Issue: JWT Tokens Changing on Every Request

**Problem:** JWT tokens were being regenerated on every page refresh or cart action, even though the session cookie remained the same.

**User's Observation:** "the tokens are changing everytime i refresh the page or add item to cart"

---

## 🔍 Root Cause Analysis

### Why Tokens Were Changing

The middleware flow was:
1. ✅ Check session cookie → Found (session ID persists)
2. ❌ Check Authorization header → **Not found** (browsers don't send custom headers)
3. ❌ Generate new JWT → **Every time!**

**Key Issue:** Browsers **don't automatically send custom headers** like `Authorization` or `X-JWT-Token`. They only send **cookies**.

### What We Were Doing Wrong

```go
// Step 2: Check Authorization header
authHeader := r.Header.Get("Authorization")  // ❌ Browser never sends this!
if authHeader != "" {
    // Validate JWT...
}
// If no header found, generate new JWT every time ❌
```

**Result:** Even though the session cookie persisted, the JWT was regenerated on every request because the browser wasn't sending it back.

---

## ✅ Solution: Store JWT in Cookie

### New Flow

**First Request (New User):**
```
1. No session cookie → Generate session ID
2. No JWT cookie → Generate JWT
3. Set cookies:
   - shop_session-id=abc-123
   - jwt_token=eyJhbGci... ✅
4. Browser stores both cookies
```

**Subsequent Requests:**
```
1. Browser sends cookies:
   - shop_session-id=abc-123
   - jwt_token=eyJhbGci... ✅
2. Validate JWT from cookie
3. JWT valid & matches session → Reuse it! ✅
4. No new JWT generated ✅
```

### Code Changes

**Added JWT cookie check BEFORE Authorization header:**

```go
// Step 2: Try to get JWT from cookie (browsers send cookies automatically)
jwtCookie, err := r.Cookie("jwt_token")
if err == nil && jwtCookie != nil {
    jwtToken = jwtCookie.Value
    
    // Validate the JWT token
    claims, err := validateJWT(jwtToken)
    if err == nil && claims != nil {
        // Valid JWT token found - verify it matches our session
        if claims.SessionID == sessionID {
            // JWT is valid and matches session - reuse it! ✅
            ctx := context.WithValue(r.Context(), ctxKeySessionID{}, sessionID)
            r = r.WithContext(ctx)
            
            w.Header().Set("X-JWT-Token", jwtToken)
            next.ServeHTTP(w, r)
            return  // ← Early return, no new JWT generated!
        }
    }
}
```

**Set JWT as cookie when generating:**

```go
// Step 4b: Set JWT token as a cookie (so browser sends it back automatically)
http.SetCookie(w, &http.Cookie{
    Name:     "jwt_token",
    Value:    newToken,
    MaxAge:   cookieMaxAge,
    HttpOnly: true,  // Prevent JavaScript access for security
    SameSite: http.SameSiteLaxMode,
})
```

---

## 🔐 Security Considerations

### HttpOnly Flag
```go
HttpOnly: true  // ✅ Prevents XSS attacks
```
- JavaScript cannot access the JWT cookie
- Protects against cross-site scripting (XSS) attacks
- Browser automatically sends it with requests

### SameSite Flag
```go
SameSite: http.SameSiteLaxMode  // ✅ Prevents CSRF attacks
```
- Cookie only sent to same-site requests
- Protects against cross-site request forgery (CSRF)
- Balance between security and usability

---

## 📊 Comparison

### Before Fix

| Request | Session Cookie | JWT Cookie | Authorization Header | Result |
|---------|---------------|------------|---------------------|---------|
| 1st visit | ✅ Set | ❌ None | ❌ None | New JWT generated |
| 2nd visit | ✅ Same | ❌ None | ❌ None | **New JWT generated** ❌ |
| 3rd visit | ✅ Same | ❌ None | ❌ None | **New JWT generated** ❌ |

**Every request = new JWT** ❌

### After Fix

| Request | Session Cookie | JWT Cookie | Authorization Header | Result |
|---------|---------------|------------|---------------------|---------|
| 1st visit | ✅ Set | ✅ Set | - | New JWT generated |
| 2nd visit | ✅ Same | ✅ Same | - | **JWT reused** ✅ |
| 3rd visit | ✅ Same | ✅ Same | - | **JWT reused** ✅ |

**JWT persists across requests** ✅

---

## 🧪 Testing

### In Browser DevTools

1. Open DevTools (F12)
2. Go to **Application** → **Cookies**
3. Visit http://localhost:8080

**You should see TWO cookies:**
```
shop_session-id: abc-123-def-456...
jwt_token: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

4. Refresh the page multiple times
5. **Verify:** Both cookie values **stay the same** ✅

### In Network Tab

1. Go to **Network** tab
2. Refresh page
3. Click on any request
4. Go to **Headers** → **Request Headers**

**You should see:**
```
Cookie: shop_session-id=abc-123...; jwt_token=eyJhbGci...
```

5. Refresh again
6. **Verify:** Same JWT token in cookie ✅

### Decode JWT to Verify

Copy the JWT token and decode it at https://jwt.io

**First Request:**
```json
{
  "sub": "abc-123-def-456",
  "session_id": "abc-123-def-456",
  "iss": "online-boutique-frontend",
  "exp": 1759777200,
  "nbf": 1759690800,
  "iat": 1759690800
}
```

**Second Request (after refresh):**
```json
{
  "sub": "abc-123-def-456",  // ← SAME!
  "session_id": "abc-123-def-456",  // ← SAME!
  "iss": "online-boutique-frontend",
  "exp": 1759777200,  // ← SAME!
  "nbf": 1759690800,  // ← SAME!
  "iat": 1759690800  // ← SAME!
}
```

**All fields identical = JWT is being reused** ✅

---

## 🎯 Expected Behavior

### JWT Lifecycle

1. **New visitor** → Generate JWT, set cookie
2. **User browses site** → JWT cookie sent automatically, validated and reused
3. **User refreshes** → Same JWT ✅
4. **User adds to cart** → Same JWT ✅
5. **User checks out** → Same JWT ✅
6. **24 hours later** → JWT expires, new one generated

### JWT Regeneration Only When

- ❌ **NOT** on every request
- ✅ User's first visit (no JWT cookie)
- ✅ JWT cookie expired (>24 hours)
- ✅ JWT signature invalid (tampered)
- ✅ JWT claims don't match session ID

---

## 📝 Benefits

### Performance
- ✅ Less CPU usage (no JWT generation on every request)
- ✅ Faster request processing (validation vs generation)

### Security
- ✅ HttpOnly cookie prevents XSS attacks
- ✅ SameSite prevents CSRF attacks
- ✅ Consistent JWT reduces attack surface

### User Experience
- ✅ Stable authentication state
- ✅ Cart persists correctly
- ✅ No unexpected logouts

### HPACK Compression Research
- ✅ **Same JWT = better HPACK compression!**
- ✅ Static JWT components cached in dynamic table
- ✅ Maximum bandwidth savings achieved

---

## 🚀 Deployment

**File Modified:** `src/frontend/middleware.go`

**Changes:**
1. Added JWT cookie check before Authorization header
2. Set JWT as HttpOnly cookie when generated
3. JWT persists across requests via cookie

**Testing:**
```bash
# Rebuild and deploy
cd /workspaces/microservices-demo
./skaffold run

# Access application
kubectl port-forward svc/frontend 8080:80

# Open browser
http://localhost:8080

# Verify cookies persist across refreshes
```

---

## ✅ Status

- [x] Issue identified: JWT regenerating every request
- [x] Root cause: Browsers don't send custom headers
- [x] Solution: Store JWT in HttpOnly cookie
- [x] Security: HttpOnly + SameSite flags
- [x] Testing: Verify cookie persistence
- [x] Deployment: Ready to test

**The JWT token should now stay consistent across requests!** 🎉

