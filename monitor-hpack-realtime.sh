#!/bin/bash

echo "========================================="
echo "Real-Time HPACK Dynamic Table Monitor"
echo "JWT Header Splitting Live Analysis"
echo "========================================="
echo ""
echo "This will monitor JWT splitting metrics in real-time."
echo "Watch for compression patterns as requests are processed."
echo ""
echo "Press Ctrl+C to stop monitoring"
echo ""
echo "Timestamp                    | Full JWT | Split Uncompressed | HPACK Compressed | Savings"
echo "-----------------------------------------------------------------------------------------"

# Get frontend pod
POD=$(kubectl get pods -l app=frontend -o jsonpath='{.items[0].metadata.name}')

# Monitor logs in real-time, parse JWT splitting metrics
kubectl logs -f $POD 2>/dev/null | grep --line-buffered "JWT header splitting metrics" | while read -r line; do
    # Parse JSON
    TIMESTAMP=$(echo "$line" | jq -r '.timestamp // empty')
    FULL_JWT=$(echo "$line" | jq -r '.full_jwt_bytes // empty')
    SPLIT_UNCOMPRESSED=$(echo "$line" | jq -r '.split_uncompressed // empty')
    HPACK_ESTIMATED=$(echo "$line" | jq -r '.split_hpack_estimated // empty')
    SAVINGS_BYTES=$(echo "$line" | jq -r '.savings_bytes // empty')
    SAVINGS_PERCENT=$(echo "$line" | jq -r '.savings_percent // empty')
    
    if [ -n "$TIMESTAMP" ]; then
        # Format timestamp (take just time part)
        TIME=$(echo "$TIMESTAMP" | cut -d'T' -f2 | cut -d'.' -f1)
        
        # Print formatted line
        printf "%-28s | %8s | %18s | %16s | %3s%% (%s bytes)\n" \
            "$TIME" \
            "${FULL_JWT}B" \
            "${SPLIT_UNCOMPRESSED}B" \
            "${HPACK_ESTIMATED}B" \
            "$SAVINGS_PERCENT" \
            "$SAVINGS_BYTES"
    fi
done
