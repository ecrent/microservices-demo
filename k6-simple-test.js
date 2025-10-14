import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  vus: 1, // Only 1 virtual user
  iterations: 1, // Run exactly once
  thresholds: {
    http_req_failed: ['rate<0.05'],
  },
};

const BASE_URL = 'http://localhost:8080';

// One product to add to cart
const PRODUCT_ID = 'OLJCESPC7Z'; // Sunglasses

function extractCookies(response) {
  const cookies = {};
  const setCookieHeaders = response.headers['Set-Cookie'];
  
  if (!setCookieHeaders) return cookies;
  
  // Handle both array and string formats
  const cookieArray = Array.isArray(setCookieHeaders) ? setCookieHeaders : [setCookieHeaders];
  
  cookieArray.forEach(cookieHeader => {
    // Split by comma to handle multiple cookies in one header
    // But be careful - cookie values can contain commas too
    // The pattern is: name=value; attributes, name=value; attributes
    const cookieParts = cookieHeader.split(/,\s*(?=[a-zA-Z_\-]+=)/);
    
    cookieParts.forEach(cookie => {
      const parts = cookie.split(';')[0].split('=');
      if (parts.length === 2) {
        cookies[parts[0].trim()] = parts[1].trim();
      }
    });
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
  
  // ========================================
  // STEP 1: Visit frontpage - Get JWT
  // ========================================
  console.log('Step 1: Visiting frontpage...');
  
  let response = http.get(BASE_URL);
  
  check(response, {
    'frontpage visit successful': (r) => r.status === 200,
  });
  
  // Debug: Show all Set-Cookie headers
  console.log(`Step 1: Response status: ${response.status}`);
  console.log(`Step 1: Set-Cookie headers: ${JSON.stringify(response.headers['Set-Cookie'])}`);
  
  // Extract cookies (including JWT and session ID)
  Object.assign(userCookies, extractCookies(response));
  
  console.log(`Step 1: Extracted cookies: ${JSON.stringify(Object.keys(userCookies))}`);
  
  if (userCookies['shop_jwt']) {
    const jwt = userCookies['shop_jwt'];
    const sessionId = userCookies['shop_session-id'];
    console.log(`Step 1: ✓ Received JWT cookie`);
    console.log(`  JWT: ${jwt.substring(0, 30)}...`);
    console.log(`  Session ID: ${sessionId ? sessionId.substring(0, 8) + '...' : 'not found'}`);
  } else {
    console.log('Step 1: ⚠️  No JWT cookie received');
    console.log(`Step 1: Available cookies: ${JSON.stringify(userCookies)}`);
  }
  
  sleep(1);
  
  // ========================================
  // STEP 2: Add item to cart
  // ========================================
  console.log('Step 2: Adding item to cart...');
  
  response = http.post(
    `${BASE_URL}/cart`,
    {
      product_id: PRODUCT_ID,
      quantity: '1',
    },
    {
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Cookie': buildCookieHeader(userCookies),
      },
    }
  );
  
  check(response, {
    'add to cart successful': (r) => r.status === 303 || r.status === 200,
  });
  
  console.log('Step 2: ✓ Item added to cart');
  
  sleep(1);
  
  console.log('Test complete!');
}
