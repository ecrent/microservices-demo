kubectl get deployment frontend -o jsonpath='{.spec.template.spec.containers[0].env[?(@.name=="ENABLE_JWT_COMPRESSION")].value}' && echo

