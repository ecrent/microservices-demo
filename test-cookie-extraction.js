import http from 'k6/http';

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

export default function () {
  const response = http.get('http://localhost:8080');
  
  console.log("Raw Set-Cookie header:");
  console.log(`  Type: ${Array.isArray(response.headers['Set-Cookie']) ? 'Array' : 'String'}`);
  console.log(`  Value: ${JSON.stringify(response.headers['Set-Cookie']).substring(0, 200)}...`);
  
  const cookies = extractCookies(response);
  
  console.log("\nExtracted cookies:");
  for (const [key, value] of Object.entries(cookies)) {
    console.log(`  ${key}: ${value.substring(0, 50)}...`);
  }
  
  console.log(`\nTotal cookies extracted: ${Object.keys(cookies).length}`);
}
