import os
import re
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker

# Railway nos dará DATABASE_URL. Si no existe o es inválida, usa SQLite local como fallback.
raw_db_url = os.getenv("DATABASE_URL", "sqlite:///./gearshield.db").strip()

# Ajuste necesario para URLs de PostgreSQL en Railway (convertir postgres:// a postgresql://)
if raw_db_url.startswith("postgres://"):
    raw_db_url = raw_db_url.replace("postgres://", "postgresql://", 1)

# Corregir puerto vacío si la URL termina en dos puntos o tiene puerto incompleto (ej. host:/db).
# Se aplica solo despues del separador "://" para no borrar ese mismo ":" en URLs validas
# (postgresql://user:pass@host:5432/db nunca debe perder el ":" del esquema).
if "://" in raw_db_url:
    _scheme, _rest = raw_db_url.split("://", 1)
    _rest = re.sub(r':(?=/|$)', '', _rest)
    raw_db_url = f"{_scheme}://{_rest}"

try:
    engine = create_engine(
        raw_db_url, 
        connect_args={"check_same_thread": False} if "sqlite" in raw_db_url else {}
    )
except Exception as e:
    print(f"[WARNING] Error inicializando DATABASE_URL ({e}). Usando SQLite local como respaldo.")
    raw_db_url = "sqlite:///./gearshield.db"
    engine = create_engine(raw_db_url, connect_args={"check_same_thread": False})

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
