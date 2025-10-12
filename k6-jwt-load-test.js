// k6 Load Test for JWT Compression Measurement
// Purpose: Test 500 users over single HTTP/2 connection with JWT renewal
// Delay: 130 seconds after adding to cart to force JWT expiration (2 min = 120s)

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
      duration: '5m',               // Run for 5 minutes (TEST MODE)
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
  if (cookies && cookies.shop_jwt && cookies.shop_jwt.length > 0) {
    initialJwt = cookies.shop_jwt[0].value;
    jwtCreatedAt = Date.now();
    if (initialJwt) {
      console.log(`[VU ${__VU}][ITER ${__ITER}] JWT created at homepage (${initialJwt.substring(0, 30)}...)`);
    }
  } else {
    console.warn(`[VU ${__VU}][ITER ${__ITER}] No JWT cookie found after homepage!`);
  }
  
  sleep(1); // Brief pause after landing
  
  // ================================================================
  // STEP 2: Browse Product (Optional)
  // ================================================================
  const randomProduct = PRODUCTS[Math.floor(Math.random() * PRODUCTS.length)];
  
  // k6 automatically sends cookies from the jar - no need to manually set Cookie header
  res = http.get(`${baseUrl}/product/${randomProduct}`, {
    tags: { name: 'ProductPage' },
  });
  
  check(res, { 
    'product page loaded': (r) => r.status === 200,
  });
  
  sleep(2); // User reads product details
  
  // ================================================================
  // STEP 3: Add to Cart
  // ================================================================
  const quantity = Math.floor(Math.random() * 3) + 1;
  
  // k6 automatically sends cookies - sessionID and JWT included
  res = http.post(`${baseUrl}/cart`, 
    `product_id=${randomProduct}&quantity=${quantity}`,
    {
      tags: { name: 'AddToCart' },
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
      },
    }
  );
  
  const cartSuccess = check(res, { 
    'item added to cart': (r) => r.status === 302 || r.status === 200,
  });
  
  if (cartSuccess) {
    cartOperations.add(1);
    console.log(`[VU ${__VU}][ITER ${__ITER}] Added ${quantity}x ${randomProduct} to cart`);
  }
  
  // ================================================================
  // STEP 4: CRITICAL - 130 Second Delay
  // This forces JWT expiration (JWT expires at 120 seconds)
  // ================================================================
  console.log(`[VU ${__VU}][ITER ${__ITER}] ⏰ Starting 130-second delay (JWT will expire at 120s)...`);
  sleep(130);
  console.log(`[VU ${__VU}][ITER ${__ITER}] ⏰ 130-second delay complete. JWT should be expired.`);
  
  // ================================================================
  // STEP 5: View Cart (Should Trigger JWT Renewal)
  // ================================================================
  // k6 automatically sends the OLD (expired) JWT cookie
  res = http.get(`${baseUrl}/cart`, {
    tags: { name: 'ViewCart' },
  });
  
  check(res, { 
    'cart viewed': (r) => r.status === 200,
  });
  
  // Check if JWT was renewed by examining the cookie jar
  const updatedCookies = jar.cookiesForURL(baseUrl);
  let jwtWasRenewed = false;
  
  if (updatedCookies && updatedCookies.shop_jwt && updatedCookies.shop_jwt.length > 0) {
    const newJwt = updatedCookies.shop_jwt[0].value;
    
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
  
  sleep(3); // User reviews cart
  
  // ================================================================
  // STEP 6: Checkout (Every iteration)
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
  
  sleep(2); // Cooldown before next iteration
}

// Setup function - runs once per VU at the beginning
export function setup() {
  console.log('='.repeat(70));
  console.log('JWT Load Test Configuration:');
  console.log('  - Virtual Users: 500');
  console.log('  - Duration: 15 minutes');
  console.log('  - JWT Expiration: 2 minutes (120 seconds)');
  console.log('  - Delay After Add to Cart: 130 seconds');
  console.log('  - Expected Behavior: JWT should renew during cart view');
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
