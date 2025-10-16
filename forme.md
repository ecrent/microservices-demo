kubectl get deployment frontend -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_JWT_COMPRESSION")].value}' && echo

nohup kubectl port-forward service/frontend 8080:80 > /tmp/port-forward.log 2>&1 &


grep -n "262144" src/frontend/main.go src/checkoutservice/main.go src/shippingservice/main.go src/paymentservice/server.js src/emailservice/email_server.py src/cartservice/src/Startup.cs