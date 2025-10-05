// Copyright 2018 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package main

import (
	"context"
	"net/http"
	"strings"
	"time"
	"os"

	"github.com/google/uuid"
	"github.com/sirupsen/logrus"
)

type ctxKeyLog struct{}
type ctxKeyRequestID struct{}

type logHandler struct {
	log  *logrus.Logger
	next http.Handler
}

type responseRecorder struct {
	b      int
	status int
	w      http.ResponseWriter
}

func (r *responseRecorder) Header() http.Header { return r.w.Header() }

func (r *responseRecorder) Write(p []byte) (int, error) {
	if r.status == 0 {
		r.status = http.StatusOK
	}
	n, err := r.w.Write(p)
	r.b += n
	return n, err
}

func (r *responseRecorder) WriteHeader(statusCode int) {
	r.status = statusCode
	r.w.WriteHeader(statusCode)
}

func (lh *logHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	requestID, _ := uuid.NewRandom()
	ctx = context.WithValue(ctx, ctxKeyRequestID{}, requestID.String())

	start := time.Now()
	rr := &responseRecorder{w: w}
	log := lh.log.WithFields(logrus.Fields{
		"http.req.path":   r.URL.Path,
		"http.req.method": r.Method,
		"http.req.id":     requestID.String(),
	})
	if v, ok := r.Context().Value(ctxKeySessionID{}).(string); ok {
		log = log.WithField("session", v)
	}
	log.Debug("request started")
	defer func() {
		log.WithFields(logrus.Fields{
			"http.resp.took_ms": int64(time.Since(start) / time.Millisecond),
			"http.resp.status":  rr.status,
			"http.resp.bytes":   rr.b}).Debugf("request complete")
	}()

	ctx = context.WithValue(ctx, ctxKeyLog{}, log)
	r = r.WithContext(ctx)
	lh.next.ServeHTTP(rr, r)
}

func ensureSessionID(next http.Handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var sessionID string
		c, err := r.Cookie(cookieSessionID)
		if err == http.ErrNoCookie {
			if os.Getenv("ENABLE_SINGLE_SHARED_SESSION") == "true" {
				// Hard coded user id, shared across sessions
				sessionID = "12345678-1234-1234-1234-123456789123"
			} else {
				u, _ := uuid.NewRandom()
				sessionID = u.String()
			}
			http.SetCookie(w, &http.Cookie{
				Name:   cookieSessionID,
				Value:  sessionID,
				MaxAge: cookieMaxAge,
			})
		} else if err != nil {
			return
		} else {
			sessionID = c.Value
		}
		ctx := context.WithValue(r.Context(), ctxKeySessionID{}, sessionID)
		r = r.WithContext(ctx)
		next.ServeHTTP(w, r)
	}
}

// ensureJWT middleware validates JWT token or creates a new one
// It checks for existing session cookie first, then validates/generates JWT
func ensureJWT(next http.Handler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		var sessionID string
		var jwtToken string
		sessionExists := false
		
		// Step 1: Check for existing session cookie (primary session identifier)
		c, err := r.Cookie(cookieSessionID)
		if err == http.ErrNoCookie {
			// No session cookie - this is a new user
			if os.Getenv("ENABLE_SINGLE_SHARED_SESSION") == "true" {
				sessionID = "12345678-1234-1234-1234-123456789123"
			} else {
				u, _ := uuid.NewRandom()
				sessionID = u.String()
			}
		} else if err != nil {
			// Cookie error
			http.Error(w, "Invalid cookie", http.StatusBadRequest)
			return
		} else {
			// Session cookie exists - reuse this session
			sessionID = c.Value
			sessionExists = true
		}
		
		// Step 2: Try to get JWT from cookie (browsers send cookies automatically)
		jwtCookie, err := r.Cookie("jwt_token")
		if err == nil && jwtCookie != nil {
			jwtToken = jwtCookie.Value
			
			// Validate the JWT token
			claims, err := validateJWT(jwtToken)
			if err == nil && claims != nil {
				// Valid JWT token found - verify it matches our session
				if claims.SessionID == sessionID {
					// JWT is valid and matches session - reuse it!
					ctx := context.WithValue(r.Context(), ctxKeySessionID{}, sessionID)
					r = r.WithContext(ctx)
					
					// Return the same JWT in response header (for debugging)
					w.Header().Set("X-JWT-Token", jwtToken)
					next.ServeHTTP(w, r)
					return
				}
			}
			// Invalid or mismatched token, will regenerate below
		}
		
		// Step 2b: Also check Authorization header (for API clients)
		authHeader := r.Header.Get("Authorization")
		if authHeader != "" && strings.HasPrefix(authHeader, "Bearer ") {
			jwtToken = strings.TrimPrefix(authHeader, "Bearer ")
			
			// Validate the JWT token
			claims, err := validateJWT(jwtToken)
			if err == nil && claims != nil {
				// Valid JWT token found - verify it matches our session
				if claims.SessionID == sessionID {
					// JWT is valid and matches session
					ctx := context.WithValue(r.Context(), ctxKeySessionID{}, sessionID)
					r = r.WithContext(ctx)
					
					// Return the same JWT in response header
					w.Header().Set("X-JWT-Token", jwtToken)
					next.ServeHTTP(w, r)
					return
				}
			}
			// Invalid or mismatched token, will regenerate below
		}
		
		// Step 3: Generate new JWT token (either new session or expired/invalid JWT)
		newToken, err := generateJWT(sessionID)
		if err != nil {
			log := r.Context().Value(ctxKeyLog{})
			if log != nil {
				log.(logrus.FieldLogger).WithError(err).Error("failed to generate JWT token")
			}
			http.Error(w, "Internal server error", http.StatusInternalServerError)
			return
		}
		
		// Step 4: Set session cookie (only if new session)
		if !sessionExists {
			http.SetCookie(w, &http.Cookie{
				Name:   cookieSessionID,
				Value:  sessionID,
				MaxAge: cookieMaxAge,
			})
		}
		
		// Step 4b: Set JWT token as a cookie (so browser sends it back automatically)
		http.SetCookie(w, &http.Cookie{
			Name:     "jwt_token",
			Value:    newToken,
			MaxAge:   cookieMaxAge,
			HttpOnly: true,  // Prevent JavaScript access for security
			SameSite: http.SameSiteLaxMode,
		})
		
		// Step 5: Set session ID in context
		ctx := context.WithValue(r.Context(), ctxKeySessionID{}, sessionID)
		r = r.WithContext(ctx)
		
		// Step 6: Return JWT token in response header
		w.Header().Set("X-JWT-Token", newToken)
		w.Header().Set("Authorization", "Bearer "+newToken)
		
		next.ServeHTTP(w, r)
	}
}
