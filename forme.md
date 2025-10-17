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