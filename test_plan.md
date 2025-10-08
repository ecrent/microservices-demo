HPACK Dynamic Table Analysis - Phase 2.2 (Compressed Sustained)

Request 1 (Frame 42):
  :method: GET
  :path: /hipstershop.CartService/AddItem
  x-jwt-static: eyJhbGciOi... (112 bytes, literal with indexing)
    → Added to table at index 62
  x-jwt-session: eyJzdWIiOi... (168 bytes, literal with indexing)
    → Added to table at index 63
  x-jwt-dynamic: eyJleHAiOj... (80 bytes, literal without indexing)
  x-jwt-sig: abc123... (342 bytes, literal without indexing)

Request 5 (Frame 158):
  :method: GET (indexed #2)
  :path: /hipstershop.CartService/AddItem (indexed #51)
  x-jwt-static: (indexed #62, 3 bytes)
  x-jwt-session: (indexed #63, 3 bytes)
  x-jwt-dynamic: eyJleHAiOj... (80 bytes, literal)
  x-jwt-sig: def456... (342 bytes, literal)

Compression Achieved: 280 bytes → 6 bytes (97.9% for cached headers)