kubectl get deployment frontend -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_JWT_COMPRESSION")].value}' && echo

nohup kubectl port-forward service/frontend 8080:80 > /tmp/port-forward.log 2>&1 &


Frontend Service (main.go)

Updated grpc.WithMaxHeaderListSize from 262144 to 65536
Checkout Service (main.go)

Updated server configuration grpc.MaxHeaderListSize from 262144 to 65536
Updated client configuration grpc.WithMaxHeaderListSize from 262144 to 65536
Cart Service (Startup.cs)

Updated MaxRequestHeadersTotalSize from 262144 to 65536
Updated comment to reflect 64KB total
Email Service (email_server.py)

Updated grpc.max_metadata_size from 262144 to 65536
Shipping Service (main.go)

Updated both server configurations (with and without stats) from 262144 to 65536
Payment Service (server.js)

Updated grpc.max_metadata_size from 262144 to 65536

cd /workspaces/microservices-demo && python3 analyze_jwt_header_indexing.py jwt-compression-results-512kb-on-20251023_062624/frontend-cart-traffic.pcap


// Decode base64 x2 (two times)
headerJSON, err := base64.RawURLEncoding.DecodeString(parts[0])   // 1st decode
payloadJSON, err := base64.RawURLEncoding.DecodeString(parts[1])  // 2nd decode

// Parse JSON x2 (two times)
json.Unmarshal(headerJSON, &header)   // 1st parse
json.Unmarshal(payloadJSON, &payload) // 2nd parse

// Serialize JSON x3 (three times)
staticJSON, _ := json.Marshal(static)   // 1st serialize
sessionJSON, _ := json.Marshal(session) // 2nd serialize
dynamicJSON, _ := json.Marshal(dynamic) // 3rd serialize

// Parse JSON x3 (three times)
json.Unmarshal([]byte(components.Static), &staticMap)   // 1st parse
json.Unmarshal([]byte(components.Session), &sessionMap) // 2nd parse
json.Unmarshal([]byte(components.Dynamic), &dynamicMap) // 3rd parse

// Serialize JSON x2 (two times)
headerJSON, err := json.Marshal(header)   // 1st serialize
payloadJSON, err := json.Marshal(payload) // 2nd serialize

// Encode base64 x2 (two times)
headerB64 := base64.RawURLEncoding.EncodeToString(headerJSON)  // 1st encode
payloadB64 := base64.RawURLEncoding.EncodeToString(payloadJSON) // 2nd encode

Operation	Decompose	Reassemble	Total
Base64 decode	2	0	2
JSON parse	2	3	5
JSON serialize	3	2	5
Base64 encode	0	2	2


SENDER (1 operation):
━━━━━━━━━━━━━━━━━━━━━
1. Split JWT on "."
2. Base64 decode parts[1]    ← ONLY OPERATION
3. Send raw JSON + signature

RECEIVER (1 operation):
━━━━━━━━━━━━━━━━━━━━━━
1. Read x-jwt-payload (raw JSON)
2. Base64 encode payload     ← ONLY OPERATION
3. Concatenate: HEADER64 + "." + payload64 + "." + sig



Service	Receives	Does	Forwards
Frontend	Full JWT (from user)	1 decompose	x-jwt-payload + x-jwt-sig
Checkoutservice	x-jwt-payload + x-jwt-sig	0 (pass-through!)	x-jwt-payload + x-jwt-sig
Cartservice	x-jwt-payload + x-jwt-sig	1 reassemble	(leaf - no forward)
Paymentservice	x-jwt-payload + x-jwt-sig	1 reassemble	(leaf - no forward)
Shippingservice	x-jwt-payload + x-jwt-sig	1 reassemble	(leaf - no forward)
Emailservice	x-jwt-payload + x-jwt-sig	1 reassemble	(leaf - no forward)


ervice	File	Setting	New Value
Frontend	main.go	grpc.WithMaxHeaderListSize	65536
Checkout Service	main.go	grpc.MaxHeaderListSize (server)	65536
Checkout Service	main.go	grpc.WithMaxHeaderListSize (client)	65536
Cart Service	Startup.cs	MaxRequestHeadersTotalSize	65536
Email Service	email_server.py	grpc.max_metadata_size	65536
Shipping Service	main.go	grpc.MaxHeaderListSize (both branches)	65536
Payment Service	server.js	grpc.max_metadata_size	65536