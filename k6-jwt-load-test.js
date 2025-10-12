// k6 Load Test for JWT Compression Measurement
// Purpose: Test 500 users over single HTTP/2 connection with JWT renewal
// User Flow:
//   1. Visit frontpage (get initial JWT)
//   2. Add item to cart
//   3. Continue shopping (browse product)
//   4. Wait 125 seconds (JWT expires at 120s)
//   5. Add another item to cart
//   6. Hit frontpage (get new JWT)
//   7. View basket
//   8. Place order (checkout)
//   9. Continue shopping

import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend, Rate } from 'k6/metrics';

// Custom metrics for JWT behavior
const jwtRenewals = new Counter('jwt_renewals');
const jwtAge = new Trend('jwt_age_seconds');
const cartOperations = new Counter('cart_operations');
const checkouts = new Counter('checkouts');
const jwtRenewalRate = new Rate('jwt_renewal_rate');

// Test configuration
export let options = {
  // Scenario configuration for 5 concurrent users (test mode)
  // Change vus to 500 and duration to '15m' for production load test
  scenarios: {
    jwt_load_test: {
      executor: 'constant-vus',
      vus: 5,                      // 5 concurrent users (TEST MODE)
      duration: '3m',               // Run for 3 minutes (TEST MODE)
      gracefulStop: '30s',
    },
  },
  
  // HTTP/2 configuration - CRITICAL for single TCP connection
  insecureSkipTLSVerify: true,
  noConnectionReuse: false,        // IMPORTANT: Reuse connections (default)
  
  // Thresholds for success criteria
  thresholds: {
    http_req_duration: ['p(95)<2000'],      // 95% of requests under 2s
    http_req_failed: ['rate<0.05'],          // Less than 5% errors
    'jwt_renewals': ['count>0'],             // Ensure JWT renewals happen
    'jwt_renewal_rate': ['rate>0.8'],        // Expect >80% renewal after 130s delay
  },
};

// Product catalog (same as in locustfile.py)
const PRODUCTS = [
  '0PUK6V6EV0',
  '1YMWWN1N4O',
  '2ZYFJ3GM2N',
  '66VCHSJNUP',
  '6E92ZMYYFZ',
  '9SIQT8TOJO',
  'L9ECAV7KIM',
  'LS4PSXUNUM',
  'OLJCESPC7Z'
];

export default function() {
  const baseUrl = __ENV.BASE_URL || 'http://localhost:8080';
  
  // Get the VU-specific cookie jar (each VU has its own jar = unique session)
  const jar = http.cookieJar();
  
  // CRITICAL: Set a unique session ID for this VU to ensure each user gets unique JWT
  // Format matches UUID v4: xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx
  // This prevents all VUs from sharing the same session if ENABLE_SINGLE_SHARED_SESSION=true
  const uniqueSessionId = `vu${String(__VU).padStart(6, '0')}-${String(__ITER).padStart(4, '0')}-4000-8000-${Date.now().toString().substring(3, 15)}`;
  jar.set(baseUrl, 'shop_session-id', uniqueSessionId, {
    path: '/',
    max_age: 86400, // 24 hours
  });
  
  console.log(`[VU ${__VU}][ITER ${__ITER}] Session ID: ${uniqueSessionId}`);
  
  // Track JWT for this user session
  let initialJwt = null;
  let jwtCreatedAt = null;
  
  // ================================================================
  // STEP 1: Landing Page (JWT Generated)
  // ================================================================
  let res = http.get(`${baseUrl}/`, {
    tags: { name: 'HomePage' },
  });
  
  const homePageSuccess = check(res, { 
    'homepage status 200': (r) => r.status === 200,
  });
  
  if (!homePageSuccess) {
    console.error(`[VU ${__VU}] Homepage failed with status: ${res.status}`);
    return; // Skip this iteration if homepage fails
  }
  
  // Extract JWT from cookie jar (k6 automatically stores Set-Cookie responses)
  const cookies = jar.cookiesForURL(baseUrl);
  
  if (cookies && cookies.shop_jwt) {
    // k6 cookies are stored as arrays - first element is the cookie value
    if (Array.isArray(cookies.shop_jwt) && cookies.shop_jwt.length > 0) {
      initialJwt = cookies.shop_jwt[0];  // Direct string value, not an object
      jwtCreatedAt = Date.now();
      console.log(`[VU ${__VU}][ITER ${__ITER}] ✅ JWT created at homepage (${initialJwt.substring(0, 50)}...)`);
    }
  } else {
    console.warn(`[VU ${__VU}][ITER ${__ITER}] ⚠️  No JWT cookie found after homepage!`);
  }
  
  sleep(1); // Brief pause after landing
  
  // ================================================================
  // STEP 2: Add First Item to Cart
  // ================================================================
  const firstProduct = PRODUCTS[Math.floor(Math.random() * PRODUCTS.length)];
  const quantity1 = Math.floor(Math.random() * 3) + 1;
  
  // k6 automatically sends cookies - sessionID and JWT included
  res = http.post(`${baseUrl}/cart`, 
    `product_id=${firstProduct}&quantity=${quantity1}`,
    {
      tags: { name: 'AddToCart_First' },
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    }
  );
  
  const cart1Success = check(res, { 
    'first item added to cart': (r) => r.status === 302 || r.status === 200,
  });
  
  if (cart1Success) {
    cartOperations.add(1);
    console.log(`[VU ${__VU}][ITER ${__ITER}] Added ${quantity1}x ${firstProduct} to cart`);
  }
  
  sleep(1);
  
  // ================================================================
  // STEP 3: Continue Shopping (Browse Products)
  // ================================================================
  const browseProduct = PRODUCTS[Math.floor(Math.random() * PRODUCTS.length)];
  
  res = http.get(`${baseUrl}/product/${browseProduct}`, {
    tags: { name: 'ContinueShopping' },
  });
  
  check(res, { 
    'product page loaded': (r) => r.status === 200,
  });
  
  sleep(2); // User reads product details
  
  // ================================================================
  // STEP 4: CRITICAL - 125 Second Wait
  // This forces JWT expiration (JWT expires at 120 seconds)
  // ================================================================
  console.log(`[VU ${__VU}][ITER ${__ITER}] ⏰ Starting 125-second delay (JWT will expire at 120s)...`);
  sleep(125);
  console.log(`[VU ${__VU}][ITER ${__ITER}] ⏰ 125-second delay complete. JWT should be expired.`);
  
  // ================================================================
  // STEP 5: Add Another Item to Cart (with expired JWT)
  // ================================================================
  const secondProduct = PRODUCTS[Math.floor(Math.random() * PRODUCTS.length)];
  const quantity2 = Math.floor(Math.random() * 3) + 1;
  
  res = http.post(`${baseUrl}/cart`, 
    `product_id=${secondProduct}&quantity=${quantity2}`,
    {
      tags: { name: 'AddToCart_Second' },
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    }
  );
  
  const cart2Success = check(res, { 
    'second item added to cart': (r) => r.status === 302 || r.status === 200,
  });
  
  if (cart2Success) {
    cartOperations.add(1);
    console.log(`[VU ${__VU}][ITER ${__ITER}] Added ${quantity2}x ${secondProduct} to cart (after 125s)`);
  }
  
  sleep(1);
  sleep(1);
  
  // ================================================================
  // STEP 6: Return to Homepage (Get New JWT)
  // ================================================================
  console.log(`[VU ${__VU}][ITER ${__ITER}] 🏠 Returning to homepage to get new JWT...`);
  
  res = http.get(`${baseUrl}/`, {
    tags: { name: 'HomePageRevisit' },
  });
  
  check(res, { 
    'homepage revisit success': (r) => r.status === 200,
  });
  
  // Check if new JWT was issued
  const updatedCookies = jar.cookiesForURL(baseUrl);
  let jwtWasRenewed = false;
  
  if (updatedCookies && updatedCookies.shop_jwt && Array.isArray(updatedCookies.shop_jwt) && updatedCookies.shop_jwt.length > 0) {
    const newJwt = updatedCookies.shop_jwt[0];  // Direct string value, not .value property
    
    console.log(`[VU ${__VU}][ITER ${__ITER}] DEBUG: Initial JWT: ${initialJwt ? initialJwt.substring(0, 50) : 'NULL'}...`);
    console.log(`[VU ${__VU}][ITER ${__ITER}] DEBUG: Current JWT: ${newJwt ? newJwt.substring(0, 50) : 'NULL'}...`);
    console.log(`[VU ${__VU}][ITER ${__ITER}] DEBUG: Are they equal? ${newJwt === initialJwt}`);
    
    if (newJwt !== initialJwt) {
      const jwtAgeInSeconds = (Date.now() - jwtCreatedAt) / 1000;
      
      console.log(`[VU ${__VU}][ITER ${__ITER}] 🔄 JWT RENEWED after ${jwtAgeInSeconds.toFixed(1)}s`);
      if (initialJwt && newJwt) {
        console.log(`[VU ${__VU}][ITER ${__ITER}]    Old: ${initialJwt.substring(0, 30)}...`);
        console.log(`[VU ${__VU}][ITER ${__ITER}]    New: ${newJwt.substring(0, 30)}...`);
      }
      
      jwtRenewals.add(1);
      jwtAge.add(jwtAgeInSeconds);
      jwtRenewalRate.add(1);
      jwtWasRenewed = true;
      
      // Update JWT for logging
      initialJwt = newJwt;
    }
  }
  
  if (!jwtWasRenewed) {
    console.warn(`[VU ${__VU}][ITER ${__ITER}] ⚠️  JWT was NOT renewed (unexpected!)`);
    jwtRenewalRate.add(0);
  }
  
  sleep(1); // Brief pause after getting new JWT
  
  // ================================================================
  // STEP 7: View Basket
  // ================================================================
  res = http.get(`${baseUrl}/cart`, {
    tags: { name: 'ViewBasket' },
  });
  
  check(res, { 
    'basket viewed': (r) => r.status === 200,
  });
  
  sleep(2); // User reviews basket
  
  // ================================================================
  // STEP 8: Place the Order (Checkout)
  // ================================================================
  const currentYear = new Date().getFullYear();
  
  const checkoutData = [
    `email=loadtest-vu${__VU}-iter${__ITER}@example.com`,
    `street_address=123+Load+Test+Street`,
    `zip_code=12345`,
    `city=TestCity`,
    `state=CA`,
    `country=USA`,
    `credit_card_number=4111111111111111`,
    `credit_card_expiration_month=12`,
    `credit_card_expiration_year=${currentYear + 1}`,
    `credit_card_cvv=123`
  ].join('&');
  
  // k6 automatically sends the renewed JWT cookie
  res = http.post(`${baseUrl}/cart/checkout`, checkoutData, {
    tags: { name: 'Checkout' },
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
  });
  
  const checkoutSuccess = check(res, { 
    'checkout successful': (r) => r.status === 200 || r.status === 302,
  });
  
  if (checkoutSuccess) {
    checkouts.add(1);
    console.log(`[VU ${__VU}][ITER ${__ITER}] ✅ Checkout completed successfully`);
  } else {
    console.error(`[VU ${__VU}][ITER ${__ITER}] ❌ Checkout failed with status: ${res.status}`);
  }
  
  sleep(1);
  
  // ================================================================
  // STEP 9: Continue Shopping (Browse More Products)
  // ================================================================
  const continueProduct = PRODUCTS[Math.floor(Math.random() * PRODUCTS.length)];
  
  res = http.get(`${baseUrl}/product/${continueProduct}`, {
    tags: { name: 'ContinueShoppingAfterCheckout' },
  });
  
  check(res, { 
    'continue shopping page loaded': (r) => r.status === 200,
  });
  
  console.log(`[VU ${__VU}][ITER ${__ITER}] 🛍️  Continuing shopping after checkout`);
  
  sleep(2); // Cooldown before next iteration
}

// Setup function - runs once per VU at the beginning
export function setup() {
  console.log('='.repeat(70));
  console.log('JWT Load Test Configuration:');
  console.log('  - Virtual Users: 5 (TEST MODE)');
  console.log('  - Duration: 3 minutes (TEST MODE)');
  console.log('  - JWT Expiration: 2 minutes (120 seconds)');
  console.log('  - User Flow:');
  console.log('    1. Visit frontpage (get JWT)');
  console.log('    2. Add item to cart');
  console.log('    3. Continue shopping');
  console.log('    4. Wait 125s (JWT expires)');
  console.log('    5. Add another item');
  console.log('    6. Visit frontpage (get NEW JWT)');
  console.log('    7. View basket');
  console.log('    8. Checkout');
  console.log('    9. Continue shopping');
  console.log('  - HTTP/2: Enabled (single TCP connection multiplexing)');
  console.log('='.repeat(70));
  return {};
}

// Teardown function - runs once at the end
export function teardown(data) {
  console.log('='.repeat(70));
  console.log('Load Test Complete');
  console.log('Check metrics for:');
  console.log('  - jwt_renewals: Total number of JWT renewals');
  console.log('  - jwt_age_seconds: Age of JWT when renewed');
  console.log('  - http_req_duration: Request latency');
  console.log('='.repeat(70));
}
