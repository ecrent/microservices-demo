import http from 'k6/http';

export default function () {
  const response = http.get('http://localhost:8080');
  
  console.log("All headers:");
  for (const [key, value] of Object.entries(response.headers)) {
    console.log(`  "${key}": ${typeof value === 'object' ? JSON.stringify(value) : value}`);
  }
  
  console.log("\nChecking Set-Cookie variations:");
  console.log(`  response.headers['Set-Cookie']: ${response.headers['Set-Cookie']}`);
  console.log(`  response.headers['set-cookie']: ${response.headers['set-cookie']}`);
}
