// JWT Compression Library for Node.js
// Decomposes JWT into HPACK-optimized components

const logger = require('./logger');

/**
 * Check if JWT compression is enabled via environment variable
 */
function isJWTCompressionEnabled() {
  return process.env.ENABLE_JWT_COMPRESSION === 'true';
}

/**
 * Decompose JWT into HPACK-optimized components
 * @param {string} jwt - Full JWT token
 * @returns {Object} Object with static, session, dynamic, and signature components
 */
function decomposeJWT(jwt) {
  if (!jwt) {
    return null;
  }

  const parts = jwt.split('.');
  if (parts.length !== 3) {
    logger.warn('Invalid JWT format');
    return null;
  }

  const [headerB64, payloadB64, signatureB64] = parts;

  try {
    // Decode header and payload
    const header = JSON.parse(Buffer.from(headerB64, 'base64').toString('utf8'));
    const payload = JSON.parse(Buffer.from(payloadB64, 'base64').toString('utf8'));

    // Static claims (never change per user session)
    const staticClaims = {
      alg: header.alg,
      typ: header.typ,
      iss: payload.iss,
      aud: payload.aud,
      name: payload.name
    };

    // Session claims (stable during user session)
    const sessionClaims = {
      sub: payload.sub,
      session_id: payload.session_id,
      market_id: payload.market_id,
      currency: payload.currency,
      cart_id: payload.cart_id
    };

    // Dynamic claims (change frequently)
    const dynamicClaims = {
      exp: payload.exp,
      iat: payload.iat,
      jti: payload.jti
    };

    // Encode components
    const staticHeader = Buffer.from(JSON.stringify(staticClaims)).toString('base64url');
    const sessionHeader = Buffer.from(JSON.stringify(sessionClaims)).toString('base64url');
    const dynamicHeader = Buffer.from(JSON.stringify(dynamicClaims)).toString('base64url');

    const result = {
      static: staticHeader,
      session: sessionHeader,
      dynamic: dynamicHeader,
      signature: signatureB64
    };

    logger.debug(`JWT decomposed: static=${staticHeader.length}b, session=${sessionHeader.length}b, dynamic=${dynamicHeader.length}b, sig=${signatureB64.length}b`);

    return result;
  } catch (err) {
    logger.warn(`Failed to decompose JWT: ${err.message}`);
    return null;
  }
}

/**
 * Reassemble JWT from compressed components
 * @param {Object} metadata - gRPC metadata object containing x-jwt-* headers
 * @returns {string|null} Reassembled JWT or null
 */
function reassembleJWT(metadata) {
  // Check for compressed JWT components
  const staticHeader = getMetadataValue(metadata, 'x-jwt-static');
  const sessionHeader = getMetadataValue(metadata, 'x-jwt-session');
  
  // Try -bin headers first (gRPC auto-decodes them), fallback to regular headers
  let dynamicHeader = getMetadataValue(metadata, 'x-jwt-dynamic-bin');
  let signature = getMetadataValue(metadata, 'x-jwt-sig-bin');
  
  if (dynamicHeader && signature) {
    // gRPC automatically base64-decodes -bin headers, use directly
    console.log('[JWT-DEBUG] Using -bin headers (auto-decoded by gRPC)');
  } else {
    // Fallback to non-bin headers for backward compatibility
    dynamicHeader = getMetadataValue(metadata, 'x-jwt-dynamic');
    signature = getMetadataValue(metadata, 'x-jwt-sig');
    console.log('[JWT-DEBUG] Using legacy non-bin headers');
  }

  if (staticHeader && sessionHeader && dynamicHeader && signature) {
    try {
      // The headers are already JSON strings from Go service
      const staticClaims = JSON.parse(staticHeader);
      const sessionClaims = JSON.parse(sessionHeader);
      const dynamicClaims = JSON.parse(dynamicHeader);

      // Separate header from static claims
      const header = {
        alg: staticClaims.alg,
        typ: staticClaims.typ
      };

      // Merge all payload claims
      const payload = {
        ...staticClaims,
        ...sessionClaims,
        ...dynamicClaims
      };
      
      // Remove header fields from payload
      delete payload.alg;
      delete payload.typ;

      // Encode header and payload
      const headerB64 = Buffer.from(JSON.stringify(header)).toString('base64url');
      const payloadB64 = Buffer.from(JSON.stringify(payload)).toString('base64url');

      // Reassemble JWT
      const jwt = `${headerB64}.${payloadB64}.${signature}`;

      logger.info(`[JWT-COMPRESSION] JWT reassembled from compressed headers (${jwt.length} bytes)`);
      logger.info(`[JWT-COMPRESSION] Component sizes - Static: ${staticHeader.length}b, Session: ${sessionHeader.length}b, Dynamic: ${dynamicHeader.length}b, Sig: ${signature.length}b`);

      return jwt;
    } catch (err) {
      logger.warn(`[JWT-COMPRESSION] Failed to reassemble JWT: ${err.message}`);
      logger.warn(`[JWT-COMPRESSION] staticHeader type: ${typeof staticHeader}, isBuffer: ${Buffer.isBuffer(staticHeader)}`);
      if (staticHeader) {
        const sample = staticHeader.slice ? staticHeader.slice(0, 20) : staticHeader.substring(0, 20);
        logger.warn(`[JWT-COMPRESSION] staticHeader sample: ${sample}`);
      }
      return null;
    }
  }

  // Fall back to standard authorization header
  const authHeader = getMetadataValue(metadata, 'authorization');
  if (authHeader && authHeader.startsWith('Bearer ')) {
    const jwt = authHeader.substring(7);
    logger.debug(`JWT extracted from authorization header (${jwt.length} bytes)`);
    return jwt;
  }

  return null;
}

/**
 * Get metadata value (handles gRPC metadata format)
 * @param {Object} metadata - gRPC metadata object
 * @param {string} key - Metadata key
 * @returns {string|null} Metadata value or null
 */
function getMetadataValue(metadata, key) {
  try {
    const value = metadata.get(key);
    
    if (value && value.length > 0) {
      // Handle both string and Buffer values
      const val = value[0];
      if (Buffer.isBuffer(val)) {
        return val.toString('utf8');
      }
      return val;
    }
  } catch (err) {
    logger.warn(`Error getting metadata '${key}': ${err.message}`);
  }
  return null;
}

/**
 * Add compressed JWT to metadata
 * @param {Object} metadata - gRPC metadata object
 * @param {string} jwt - Full JWT token
 */
function addCompressedJWT(metadata, jwt) {
  if (!jwt || !isJWTCompressionEnabled()) {
    // Fallback to standard authorization header
    metadata.set('authorization', `Bearer ${jwt}`);
    return;
  }

  const components = decomposeJWT(jwt);
  if (!components) {
    // Failed to decompose, use standard header
    metadata.set('authorization', `Bearer ${jwt}`);
    return;
  }

  // Add compressed components
  metadata.set('x-jwt-static', components.static);
  metadata.set('x-jwt-session', components.session);
  metadata.set('x-jwt-dynamic', components.dynamic);
  metadata.set('x-jwt-sig', components.signature);

  const totalSize = components.static.length + components.session.length + 
                    components.dynamic.length + components.signature.length;
  logger.debug(`Forwarding compressed JWT: total=${totalSize}b`);
}

module.exports = {
  isJWTCompressionEnabled,
  decomposeJWT,
  reassembleJWT,
  addCompressedJWT,
  getMetadataValue
};
