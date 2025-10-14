kubectl get deployment frontend -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_JWT_COMPRESSION")].value}' && echo

nohup kubectl port-forward service/frontend 8080:80 > /tmp/port-forward.log 2>&1 &