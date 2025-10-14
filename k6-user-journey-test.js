import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

// Custom metrics
const jwtRenewals = new Counter('jwt_renewals');
const jwtRenewalSuccesses = new Counter('jwt_renewal_successes');
const jwtRenewalFailures = new Counter('jwt_renewal_failures');
const cartOperations = new Counter('cart_operations');
const requestSize = new Trend('request_size_bytes');
const responseSize = new Trend('response_size_bytes');

export const options = {
  stages: [
    { duration: '30s', target: 100 },  // Ramp up to 100 users over 30s
    { duration: '150s', target: 100 }, // Stay at 100 users for 150s (allows for 125s wait + operations)
  ],
  thresholds: {
    http_req_failed: ['rate<0.05'], // Less than 5% errors
    http_req_duration: ['p(95)<2000'], // 95% of requests under 2s
  },
};

const BASE_URL = 'http://localhost:8080';

// Available products from the catalog
const PRODUCT_IDS = [
  'OLJCESPC7Z', // Sunglasses
  '66VCHSJNUP', // Tank Top
  '1YMWWN1N4O', // Watch
  'L9ECAV7KIM', // Loafers
  '2ZYFJ3GM2N', // Candle Holder
  '0PUK6V6EV0', // Hairdryer
  'LS4PSXUNUM', // Metal Camping Mug
  '9SIQT8TOJO', // City Bike
  '6E92ZMYYFZ', // Air Plant
];

function getRandomProduct() {
  return PRODUCT_IDS[Math.floor(Math.random() * PRODUCT_IDS.length)];
}

function extractCookies(response) {
  const cookies = {};
  const setCookieHeaders = response.headers['Set-Cookie'];
  
  if (!setCookieHeaders) return cookies;
  
  const cookieArray = Array.isArray(setCookieHeaders) ? setCookieHeaders : [setCookieHeaders];
  
  cookieArray.forEach(cookie => {
    const parts = cookie.split(';')[0].split('=');
    if (parts.length === 2) {
      cookies[parts[0]] = parts[1];
    }
  });
  
  return cookies;
}

function buildCookieHeader(cookies) {
  return Object.entries(cookies)
    .map(([key, value]) => `${key}=${value}`)
    .join('; ');
}

export default function () {
  const userCookies = {};
  let firstSessionId = null;
  let secondSessionId = null;
  
  // ========================================
  // PHASE 1: Initial visit - Get first JWT
  // ========================================
  console.log(`[VU ${__VU}] Phase 1: Initial frontpage visit`);
  
  let response = http.get(BASE_URL, {
    tags: { phase: 'initial_visit', jwt_state: 'new' }
  });
  
  check(response, {
    'initial visit successful': (r) => r.status === 200,
  });
  
  // Extract cookies (including JWT and session ID)
  Object.assign(userCookies, extractCookies(response));
  
  if (Object.keys(userCookies).length > 0) {
    firstSessionId = userCookies['shop_session-id'];
    const firstJWT = userCookies['shop_jwt'];
    console.log(`[VU ${__VU}] Phase 1: Received first JWT cookie`);
    console.log(`[VU ${__VU}]   JWT: ${firstJWT ? firstJWT.substring(0, 20) + '...' : 'not found'}`);
    console.log(`[VU ${__VU}]   Session: ${firstSessionId ? firstSessionId.substring(0, 8) + '...' : 'not found'}`);
    jwtRenewals.add(1);
  }
  
  requestSize.add(response.request.body ? response.request.body.length : 0);
  responseSize.add(response.body ? response.body.length : 0);
  
  sleep(2);
  
  // ========================================
  // PHASE 2: Add items to cart (with first JWT)
  // ========================================
  console.log(`[VU ${__VU}] Phase 2: Adding items to cart (JWT #1)`);
  
  const product1 = getRandomProduct();
  const product2 = getRandomProduct();
  
  // Add first item
  response = http.post(
    `${BASE_URL}/cart`,
    {
      product_id: product1,
      quantity: '1',
    },
    {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cookie': buildCookieHeader(userCookies),
      },
      tags: { phase: 'add_to_cart', jwt_state: 'first_jwt', item: '1' }
    }
  );
  
  check(response, {
    'add item 1 successful': (r) => r.status === 303 || r.status === 200,
  });
  cartOperations.add(1);
  
  sleep(1);
  
  // Add second item
  response = http.post(
    `${BASE_URL}/cart`,
    {
      product_id: product2,
      quantity: '2',
    },
    {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cookie': buildCookieHeader(userCookies),
      },
      tags: { phase: 'add_to_cart', jwt_state: 'first_jwt', item: '2' }
    }
  );
  
  check(response, {
    'add item 2 successful': (r) => r.status === 303 || r.status === 200,
  });
  cartOperations.add(1);
  
  sleep(2);
  
  // View cart
  response = http.get(`${BASE_URL}/cart`, {
    headers: {
      'Cookie': buildCookieHeader(userCookies),
    },
    tags: { phase: 'view_cart', jwt_state: 'first_jwt' }
  });
  
  check(response, {
    'view cart successful': (r) => r.status === 200,
  });
  
  // ========================================
  // PHASE 3: Wait for JWT expiration (125 seconds)
  // ========================================
  console.log(`[VU ${__VU}] Phase 3: Waiting 125 seconds for JWT expiration...`);
  sleep(125);
  
  // ========================================
  // PHASE 4: Return to shopping - Get new JWT
  // ========================================
  console.log(`[VU ${__VU}] Phase 4: Return to frontpage (JWT should be expired, expecting new JWT)`);
  
  response = http.get(BASE_URL, {
    headers: {
      'Cookie': buildCookieHeader(userCookies),
    },
    tags: { phase: 'return_shopping', jwt_state: 'renewed' }
  });
  
  check(response, {
    'return to shopping successful': (r) => r.status === 200,
  });
  
  // Check if we got a new JWT by looking for shop_jwt cookie (not session-id)
  const newCookies = extractCookies(response);
  if (Object.keys(newCookies).length > 0) {
    // Check for JWT cookie renewal (shop_jwt cookie)
    const gotNewJWT = newCookies['shop_jwt'] !== undefined;
    
    // Also track session IDs for logging (session ID stays the same, JWT changes)
    secondSessionId = newCookies['shop_session-id'] || userCookies['shop_session-id'];
    
    if (gotNewJWT) {
      const firstJWT = userCookies['shop_jwt'];
      const secondJWT = newCookies['shop_jwt'];
      
      console.log(`[VU ${__VU}] Phase 4: ✓ JWT RENEWED - New JWT cookie received`);
      console.log(`[VU ${__VU}]   First JWT:  ${firstJWT ? firstJWT.substring(0, 20) + '...' : 'unknown'}`);
      console.log(`[VU ${__VU}]   Second JWT: ${secondJWT ? secondJWT.substring(0, 20) + '...' : 'unknown'}`);
      console.log(`[VU ${__VU}]   Session ID: ${secondSessionId ? secondSessionId.substring(0, 8) + '... (unchanged)' : 'unknown'}`);
      jwtRenewals.add(1);
      
      // Verify the JWTs are different
      const jwtRenewedCorrectly = firstJWT !== secondJWT;
      check(null, {
        'JWT renewed with different token': () => jwtRenewedCorrectly,
      });
      
      if (jwtRenewedCorrectly) {
        jwtRenewalSuccesses.add(1);
      } else {
        console.log(`[VU ${__VU}] ⚠️  WARNING: JWT did not change after expiration!`);
        jwtRenewalFailures.add(1);
      }
    } else {
      console.log(`[VU ${__VU}] Phase 4: No new JWT cookie received (still using old JWT or JWT not expired yet)`);
    }
    
    // Update cookies for next requests
    Object.assign(userCookies, newCookies);
  } else {
    console.log(`[VU ${__VU}] Phase 4: ⚠️  No cookies received after JWT expiration`);
  }
  
  sleep(2);
  
  // ========================================
  // PHASE 5: Add another item (with new JWT)
  // ========================================
  console.log(`[VU ${__VU}] Phase 5: Adding item with new JWT`);
  
  const product3 = getRandomProduct();
  
  response = http.post(
    `${BASE_URL}/cart`,
    {
      product_id: product3,
      quantity: '1',
    },
    {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cookie': buildCookieHeader(userCookies),
      },
      tags: { phase: 'add_to_cart', jwt_state: 'second_jwt', item: '3' }
    }
  );
  
  check(response, {
    'add item 3 with new JWT successful': (r) => r.status === 303 || r.status === 200,
  });
  cartOperations.add(1);
  
  sleep(2);
  
  // ========================================
  // PHASE 6: Place order
  // ========================================
  console.log(`[VU ${__VU}] Phase 6: Placing order`);
  
  response = http.post(
    `${BASE_URL}/cart/checkout`,
    {
      email: `user${__VU}@example.com`,
      street_address: '123 Main St',
      zip_code: '12345',
      city: 'San Francisco',
      state: 'CA',
      country: 'United States',
      credit_card_number: '4432-8015-6152-0454',
      credit_card_expiration_month: '12',
      credit_card_expiration_year: '2025',
      credit_card_cvv: '123',
    },
    {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cookie': buildCookieHeader(userCookies),
      },
      tags: { phase: 'checkout', jwt_state: 'second_jwt' }
    }
  );
  
  check(response, {
    'checkout successful': (r) => r.status === 200 || r.status === 303,
  });
  
  sleep(2);
  
  // ========================================
  // PHASE 7: Continue shopping
  // ========================================
  console.log(`[VU ${__VU}] Phase 7: Continue shopping`);
  
  response = http.get(BASE_URL, {
    headers: {
      'Cookie': buildCookieHeader(userCookies),
    },
    tags: { phase: 'continue_shopping', jwt_state: 'second_jwt' }
  });
  
  check(response, {
    'continue shopping successful': (r) => r.status === 200,
  });
  
  // ========================================
  // PHASE 8: Summary
  // ========================================
  const finalJWT = userCookies['shop_jwt'];
  if (finalJWT) {
    console.log(`[VU ${__VU}] Journey complete: Using JWT ${finalJWT.substring(0, 20)}...`);
    console.log(`[VU ${__VU}]   Session ID remained: ${secondSessionId ? secondSessionId.substring(0, 8) + '...' : 'unknown'}`);
  } else {
    console.log(`[VU ${__VU}] Journey complete (JWT check: ${userCookies['shop_jwt'] ? 'success' : 'no JWT found'})`);
  }
}
