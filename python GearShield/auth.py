import os
import hashlib
import hmac
import base64
import json
from datetime import datetime, timedelta

SECRET_KEY = os.getenv("JWT_SECRET", "gearshield_secret_key_hackmty_2026")
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 24  # 24 horas

def hash_password(password: str) -> str:
    """
    Hashea la contraseña usando PBKDF2 HMAC SHA256 (estándar nativo de Python).
    """
    salt = os.urandom(16)
    pwd_hash = hashlib.pbkdf2_hmac('sha256', password.encode('utf-8'), salt, 100000)
    return f"{salt.hex()}:{pwd_hash.hex()}"

def verify_password(plain_password: str, hashed_password: str) -> bool:
    """
    Verifica una contraseña en texto plano contra el hash almacenado.
    """
    try:
        if ":" not in hashed_password:
            return False
        salt_hex, pwd_hash_hex = hashed_password.split(":", 1)
        salt = bytes.fromhex(salt_hex)
        expected_hash = hashlib.pbkdf2_hmac('sha256', plain_password.encode('utf-8'), salt, 100000)
        return hmac.compare_digest(expected_hash.hex(), pwd_hash_hex)
    except Exception:
        return False

def create_access_token(data: dict, expires_delta: timedelta = None) -> str:
    """
    Genera un Token JWT compacto (HS256) sin dependencias complejas de C/DLLs.
    """
    to_encode = data.copy()
    expire = datetime.utcnow() + (expires_delta or timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES))
    to_encode.update({"exp": int(expire.timestamp())})
    
    header = {"alg": "HS256", "typ": "JWT"}
    header_b64 = base64.urlsafe_b64encode(json.dumps(header).encode()).decode().rstrip("=")
    payload_b64 = base64.urlsafe_b64encode(json.dumps(to_encode, default=str).encode()).decode().rstrip("=")
    
    signature_input = f"{header_b64}.{payload_b64}".encode()
    signature = hmac.new(SECRET_KEY.encode(), signature_input, hashlib.sha256).digest()
    signature_b64 = base64.urlsafe_b64encode(signature).decode().rstrip("=")
    
    return f"{header_b64}.{payload_b64}.{signature_b64}"
