# Dockerfile - Despliegue de API GearShield en Railway / Cloud
FROM python:3.11-slim

# Instalar dependencias del sistema requeridas para librosa, soundfile y ffmpeg
RUN apt-get update && apt-get install -y \
    libsndfile1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copiar requerimientos e instalar dependencias
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copiar el código del proyecto y los modelos (excluyendo data/ masivo vía .dockerignore)
COPY . .

# Puerto expuesto para Railway o servidores Cloud
EXPOSE 8000

# Comando de inicio usando $PORT dinámico de Railway o fallback a 8000
CMD ["sh", "-c", "uvicorn main:app --host 0.0.0.0 --port ${PORT:-8000}"]
