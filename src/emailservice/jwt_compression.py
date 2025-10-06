"""JWT Compression Library for Python
Decomposes JWT into HPACK-optimized components
"""

import json
import base64
import os
import logging

logger = logging.getLogger(__name__)


def is_jwt_compression_enabled():
    """Check if JWT compression is enabled via environment variable"""
    return os.environ.get('ENABLE_JWT_COMPRESSION', 'false').lower() == 'true'


def base64url_decode(data):
    """Decode base64url string"""
    # Add padding if needed
    padding = 4 - len(data) % 4
    if padding != 4:
        data += '=' * padding
    return base64.urlsafe_b64decode(data)


def base64url_encode(data):
    """Encode to base64url string (no padding)"""
    if isinstance(data, str):
        data = data.encode('utf-8')
    return base64.urlsafe_b64encode(data).decode('utf-8').rstrip('=')


def decompose_jwt(jwt):
    """Decompose JWT into HPACK-optimized components
    
    Args:
        jwt (str): Full JWT token
        
    Returns:
        dict: Dictionary with static, session, dynamic, and signature components
    """
    if not jwt:
        return None
    
    parts = jwt.split('.')
    if len(parts) != 3:
        logger.warning('Invalid JWT format')
        return None
    
    header_b64, payload_b64, signature_b64 = parts
    
    try:
        # Decode header and payload
        header = json.loads(base64url_decode(header_b64))
        payload = json.loads(base64url_decode(payload_b64))
        
        # Static claims (never change per user session)
        static_claims = {
            'alg': header.get('alg'),
            'typ': header.get('typ'),
            'iss': payload.get('iss'),
            'aud': payload.get('aud'),
            'name': payload.get('name')
        }
        
        # Session claims (stable during user session)
        session_claims = {
            'sub': payload.get('sub'),
            'session_id': payload.get('session_id'),
            'market_id': payload.get('market_id'),
            'currency': payload.get('currency'),
            'cart_id': payload.get('cart_id')
        }
        
        # Dynamic claims (change frequently)
        dynamic_claims = {
            'exp': payload.get('exp'),
            'iat': payload.get('iat'),
            'jti': payload.get('jti')
        }
        
        # Encode components
        static_header = base64url_encode(json.dumps(static_claims))
        session_header = base64url_encode(json.dumps(session_claims))
        dynamic_header = base64url_encode(json.dumps(dynamic_claims))
        
        result = {
            'static': static_header,
            'session': session_header,
            'dynamic': dynamic_header,
            'signature': signature_b64
        }
        
        logger.debug(
            f'JWT decomposed: static={len(static_header)}b, '
            f'session={len(session_header)}b, dynamic={len(dynamic_header)}b, '
            f'sig={len(signature_b64)}b'
        )
        
        return result
        
    except Exception as err:
        logger.warning(f'Failed to decompose JWT: {err}')
        return None


def reassemble_jwt(metadata):
    """Reassemble JWT from compressed components
    
    Args:
        metadata: gRPC metadata tuple list
        
    Returns:
        str|None: Reassembled JWT or None
    """
    # Convert metadata to dict
    metadata_dict = {}
    for key, value in metadata:
        if isinstance(value, bytes):
            value = value.decode('utf-8')
        metadata_dict[key] = value
    
    # Check for compressed JWT components
    static_header = metadata_dict.get('x-jwt-static')
    session_header = metadata_dict.get('x-jwt-session')
    dynamic_header = metadata_dict.get('x-jwt-dynamic')
    signature = metadata_dict.get('x-jwt-sig')
    
    if static_header and session_header and dynamic_header and signature:
        try:
            # Decode each component
            static_claims = json.loads(base64url_decode(static_header))
            session_claims = json.loads(base64url_decode(session_header))
            dynamic_claims = json.loads(base64url_decode(dynamic_header))
            
            # Separate header from static claims
            header = {
                'alg': static_claims.get('alg'),
                'typ': static_claims.get('typ')
            }
            
            # Merge all payload claims
            payload = {
                **static_claims,
                **session_claims,
                **dynamic_claims
            }
            
            # Remove header fields from payload
            payload.pop('alg', None)
            payload.pop('typ', None)
            
            # Encode header and payload
            header_b64 = base64url_encode(json.dumps(header, separators=(',', ':')))
            payload_b64 = base64url_encode(json.dumps(payload, separators=(',', ':')))
            
            # Reassemble JWT
            jwt = f'{header_b64}.{payload_b64}.{signature}'
            
            logger.debug(f'JWT reassembled from compressed headers ({len(jwt)} bytes)')
            logger.debug(
                f'  Static: {len(static_header)}b, Session: {len(session_header)}b, '
                f'Dynamic: {len(dynamic_header)}b, Sig: {len(signature)}b'
            )
            
            return jwt
            
        except Exception as err:
            logger.warning(f'Failed to reassemble JWT: {err}')
            return None
    
    # Fall back to standard authorization header
    auth_header = metadata_dict.get('authorization')
    if auth_header and auth_header.startswith('Bearer '):
        jwt = auth_header[7:]
        logger.debug(f'JWT extracted from authorization header ({len(jwt)} bytes)')
        return jwt
    
    return None


def add_compressed_jwt(metadata, jwt):
    """Add compressed JWT to metadata
    
    Args:
        metadata: gRPC metadata tuple list
        jwt (str): Full JWT token
    """
    if not jwt or not is_jwt_compression_enabled():
        # Fallback to standard authorization header
        metadata.append(('authorization', f'Bearer {jwt}'))
        return
    
    components = decompose_jwt(jwt)
    if not components:
        # Failed to decompose, use standard header
        metadata.append(('authorization', f'Bearer {jwt}'))
        return
    
    # Add compressed components
    metadata.append(('x-jwt-static', components['static']))
    metadata.append(('x-jwt-session', components['session']))
    metadata.append(('x-jwt-dynamic', components['dynamic']))
    metadata.append(('x-jwt-sig', components['signature']))
    
    total_size = (len(components['static']) + len(components['session']) + 
                  len(components['dynamic']) + len(components['signature']))
    logger.debug(f'Forwarding compressed JWT: total={total_size}b')
