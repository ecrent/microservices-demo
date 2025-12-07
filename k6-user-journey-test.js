import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter } from 'k6/metrics';

// ============================================================================
// Custom Metrics - Counters only (latency measured via PCAP analysis)
// ============================================================================
const jwtRenewals = new Counter('jwt_renewals');
const jwtRenewalSuccesses = new Counter('jwt_renewal_successes');
const jwtRenewalFailures = new Counter('jwt_renewal_failures');
const cartOperations = new Counter('cart_operations');

// ============================================================================
// Test Configuration
// ============================================================================
export const options = {
  scenarios: {
    // Warmup scenario - prime connections and HPACK tables (20s, with logging)
    warmup: {
      executor: 'constant-vus',
      vus: 20,
      duration: '20s',
      startTime: '0s',
      tags: { scenario: 'warmup' },
      exec: 'warmupTest',
    },
    // Main test scenario - starts after warmup completes
    main_test: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '60s', target: 150 },  // Ramp up to 250 users over 60s
        { duration: '300s', target: 150 }, // Stay at 250 users for 300s
      ],
      startTime: '20s', // Start after warmup completes
      exec: 'mainTest',
    },
  },
  thresholds: {
    // Thresholds apply to main test only (exclude warmup)
    'http_req_failed{scenario:main_test}': ['rate<0.01'],
    'http_req_duration{scenario:main_test}': ['p(95)<2000'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:8080';

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

// Use fixed products for consistent, reproducible test results
const PRODUCT_1 = PRODUCT_IDS[0]; // Sunglasses
const PRODUCT_2 = PRODUCT_IDS[1]; // Tank Top
const PRODUCT_3 = PRODUCT_IDS[2]; // Watch

function extractCookies(response) {
  const cookies = {};
  const setCookieHeaders = response.headers['Set-Cookie'];
  
  if (!setCookieHeaders) return cookies;
  
  // Set-Cookie can be:
  // 1. An array of strings (multiple Set-Cookie headers)
  // 2. A single string with cookies separated by ", " (Go HTTP combines them)
  let cookieArray;
  if (Array.isArray(setCookieHeaders)) {
    cookieArray = setCookieHeaders;
  } else {
    // Split on ", " but be careful not to split on "; " within cookie attributes
    // Look for pattern: "name=value; attributes, name=value; attributes"
    // Split on comma followed by space and a word character (start of cookie name)
    cookieArray = setCookieHeaders.split(/,\s*(?=[a-zA-Z_]+=)/);
  }
  
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

// ============================================================================
// WARMUP SCENARIO - Prime connections and HPACK tables (with logging)
// ============================================================================
export function warmupTest() {
  const userCookies = {};
  
  console.log(`[WARMUP VU ${__VU}] Starting warmup iteration`);
  
  // Homepage visit
  let response = http.get(BASE_URL, { tags: { scenario: 'warmup' } });
  Object.assign(userCookies, extractCookies(response));
  
  if (Object.keys(userCookies).length > 0) {
    const jwt = userCookies['shop_jwt'];
    console.log(`[WARMUP VU ${__VU}] Got JWT: ${jwt ? jwt.substring(0, 20) + '...' : 'not found'}`);
  }
  
  sleep(1);
  
  // Cart add to prime cart service connection
  if (Object.keys(userCookies).length > 0) {
    response = http.post(`${BASE_URL}/cart`, {
      product_id: PRODUCT_1,
      quantity: '1',
    }, {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cookie': buildCookieHeader(userCookies),
      },
      tags: { scenario: 'warmup' }
    });
    
    console.log(`[WARMUP VU ${__VU}] Cart add status: ${response.status}`);
  }
  
  sleep(2);
}

// ============================================================================
// MAIN TEST SCENARIO - Full user journey with JWT renewal (no logging)
// ============================================================================
export function mainTest() {
  const userCookies = {};
  
  // ========================================
  // PHASE 1: Initial visit - Get first JWT
  // ========================================
  let response = http.get(BASE_URL, {
    tags: { phase: 'initial_visit', jwt_state: 'new' }
  });
  
  check(response, {
    'initial visit successful': (r) => r.status === 200,
  });
  
  Object.assign(userCookies, extractCookies(response));
  
  if (Object.keys(userCookies).length > 0) {
    jwtRenewals.add(1);
  }
  
  sleep(2);
  
  // ========================================
  // PHASE 2: Add items to cart (with first JWT)
  // ========================================
  
  // Add first item (Sunglasses)
  response = http.post(
    `${BASE_URL}/cart`,
    {
      product_id: PRODUCT_1,
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
  
  // Add second item (Tank Top)
  response = http.post(
    `${BASE_URL}/cart`,
    {
      product_id: PRODUCT_2,
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
  sleep(125);
  
  // ========================================
  // PHASE 4: Return to shopping - Get new JWT
  // ========================================
  response = http.get(BASE_URL, {
    headers: {
      'Cookie': buildCookieHeader(userCookies),
    },
    tags: { phase: 'return_shopping', jwt_state: 'renewed' }
  });
  
  check(response, {
    'return to shopping successful': (r) => r.status === 200,
  });
  
  const newCookies = extractCookies(response);
  if (Object.keys(newCookies).length > 0) {
    const gotNewJWT = newCookies['shop_jwt'] !== undefined;
    
    if (gotNewJWT) {
      const firstJWT = userCookies['shop_jwt'];
      const secondJWT = newCookies['shop_jwt'];
      
      jwtRenewals.add(1);
      
      const jwtRenewedCorrectly = firstJWT !== secondJWT;
      check(null, {
        'JWT renewed with different token': () => jwtRenewedCorrectly,
      });
      
      if (jwtRenewedCorrectly) {
        jwtRenewalSuccesses.add(1);
      } else {
        jwtRenewalFailures.add(1);
      }
    }
    
    Object.assign(userCookies, newCookies);
  }
  
  sleep(2);
  
  // ========================================
  // PHASE 5: Add another item (with new JWT)
  // ========================================
  response = http.post(
    `${BASE_URL}/cart`,
    {
      product_id: PRODUCT_3,
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
  response = http.post(
    `${BASE_URL}/cart/checkout`,
    {
      email: `user${__VU}@example.com`,
      street_address: '123 Main St',
      zip_code: '12345',
      city: 'San Francisco',
      state: 'CA',
      country: 'United States',
      credit_card_number: '4432801561520454',
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
  response = http.get(BASE_URL, {
    headers: {
      'Cookie': buildCookieHeader(userCookies),
    },
    tags: { phase: 'continue_shopping', jwt_state: 'second_jwt' }
  });
  
  check(response, {
    'continue shopping successful': (r) => r.status === 200,
  });
}
