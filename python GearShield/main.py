"""
main.py - API REST de Servidor GearShield (FastAPI).
Proporciona endpoints de analisis de audio, servicio de reconfirmacion (5% audit)
y generacion automatica de reportes forenses en PDF.
"""

import os
import shutil
import uuid
from datetime import datetime
from typing import Optional

import base64
import io
import httpx
import soundfile as sf
from dotenv import load_dotenv

load_dotenv()
from fastapi import FastAPI, File, UploadFile, Form, HTTPException, BackgroundTasks, Request, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, JSONResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session

from Gearshield1 import analyze_audio, load_gearshield_engine
from pdf_generator import generate_forensic_pdf
import database
import models
import auth

def seed_demo_user():
    try:
        db = database.SessionLocal()
        user = db.query(models.User).filter(models.User.email == "juanperez@gmail.com").first()
        if not user:
            new_user = models.User(
                username="juanperez",
                email="juanperez@gmail.com",
                hashed_password=auth.hash_password("12345"),
                full_name="Juan Pérez",
                role="user"
            )
            db.add(new_user)
            db.commit()
            print("[OK] Usuario de prueba sembrado: juanperez@gmail.com / 12345")
        db.close()
    except Exception as e:
        print(f"[WARNING] No se pudo crear usuario semilla: {e}")

# Inicializar tablas de la Base de Datos con manejo de errores seguro
try:
    models.Base.metadata.create_all(bind=database.engine)
    print("[OK] Tablas de la Base de Datos verificadas/creadas correctamente.")
    seed_demo_user()
except Exception as e:
    print(f"[WARNING] No se pudo conectar a la base de datos inmediatamente: {e}")

app = FastAPI(
    title="GearShield Security Engine API",
    description="API REST de Detección de Sintetizadores de Voz, Deepfakes y Reconfirmación de Incidentes.",
    version="1.0.0"
)

# Configuración de CORS para permitir conexiones desde Flutter (Móvil, Web, Desktop)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Directorios de trabajo
UPLOAD_DIR = "uploads"
RECONFIRM_DIR = "reconfirmations"
REPORTS_DIR = "reports"

for folder in [UPLOAD_DIR, RECONFIRM_DIR, REPORTS_DIR]:
    os.makedirs(folder, exist_ok=True)

import json

LOGS_FILE = os.path.join(REPORTS_DIR, "logs_db.json")

def load_logs():
    if not os.path.exists(LOGS_FILE):
        seed_logs = [
            {
                "id": "log-1001",
                "timestamp": datetime.now().isoformat(),
                "filename": "call_agent_001.wav",
                "label": "Voz Orgánica Humana",
                "overall_risk_ai": 12.5,
                "max_ai_prob": 15.2,
                "avg_ai_prob": 10.1,
                "is_synthetic": False,
                "is_false_positive": False,
                "false_positive_reason": None,
                "location": "Ciudad de México, MX",
                "channel": "Llamada Entrante #101"
            },
            {
                "id": "log-1002",
                "timestamp": datetime.now().isoformat(),
                "filename": "deepfake_clone_v2.wav",
                "label": "Voz Sintética Detectada (IA)",
                "overall_risk_ai": 89.4,
                "max_ai_prob": 95.8,
                "avg_ai_prob": 88.0,
                "is_synthetic": True,
                "is_false_positive": False,
                "false_positive_reason": None,
                "location": "Monterrey, MX",
                "channel": "Llamada Entrante #102"
            },
            {
                "id": "log-1003",
                "timestamp": datetime.now().isoformat(),
                "filename": "robot_voice_test.wav",
                "label": "Voz Sintética Detectada (IA)",
                "overall_risk_ai": 92.1,
                "max_ai_prob": 98.4,
                "avg_ai_prob": 91.5,
                "is_synthetic": True,
                "is_false_positive": False,
                "false_positive_reason": None,
                "location": "Guadalajara, MX",
                "channel": "SIP Trunk #3"
            },
            {
                "id": "log-1004",
                "timestamp": datetime.now().isoformat(),
                "filename": "customer_support_sample.wav",
                "label": "Voz Sintética Detectada (IA)",
                "overall_risk_ai": 54.0,
                "max_ai_prob": 62.0,
                "avg_ai_prob": 51.0,
                "is_synthetic": True,
                "is_false_positive": True,
                "false_positive_reason": "Voz ronca confundida por artefacto sintético",
                "location": "Puebla, MX",
                "channel": "Atención a Clientes"
            }
        ]
        save_logs(seed_logs)
        return seed_logs
    try:
        with open(LOGS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return []

def save_logs(logs):
    with open(LOGS_FILE, "w", encoding="utf-8") as f:
        json.dump(logs, f, ensure_ascii=False, indent=2)

def record_log_entry(analysis_result: dict, filename: str = "audio_clip.wav") -> dict:
    logs = load_logs()
    log_id = f"log-{uuid.uuid4().hex[:6]}"
    overall_risk = analysis_result.get("overall_risk_ai", 0.0)
    is_synth = overall_risk >= 50.0 or analysis_result.get("max_ai_prob", 0.0) >= 60.0
    
    new_entry = {
        "id": log_id,
        "timestamp": datetime.now().isoformat(),
        "filename": filename,
        "label": analysis_result.get("label", "Voz Analizada"),
        "overall_risk_ai": overall_risk,
        "max_ai_prob": analysis_result.get("max_ai_prob", 0.0),
        "avg_ai_prob": analysis_result.get("avg_ai_prob", 0.0),
        "is_synthetic": is_synth,
        "is_false_positive": False,
        "false_positive_reason": None,
        "location": "Latam Node #1",
        "channel": "Agente / Cliente Móvil"
    }
    logs.insert(0, new_entry)
    save_logs(logs)
    return new_entry

# Cargar el motor analítico al iniciar
model, scaler = load_gearshield_engine()

class TimelineItem(BaseModel):
    model_config = {"extra": "allow"}

    start_sec: float
    end_sec: float
    prob_human: float
    prob_ai: float
    is_ai: bool

class AnalysisResponse(BaseModel):
    # `extra="allow"` conserva campos informativos del motor (latency_ms,
    # sentences_analyzed, persistence_metrics, ...) en vez de descartarlos.
    model_config = {"extra": "allow"}

    audio_path: str
    label: str
    risk_zone: str = "ZONA_VERDE"
    action_required: str = "APROBADO_ACCESO_CONCEDIDO"
    overall_risk_ai: float
    max_ai_prob: float
    avg_ai_prob: float
    ai_detected_intervals: list
    timeline: list[TimelineItem]

class RegisterRequest(BaseModel):
    email: str
    password: str
    full_name: Optional[str] = "Usuario GearShield"
    username: Optional[str] = None

class LoginRequest(BaseModel):
    email: str
    password: str

@app.post("/auth/register", summary="Registro de Usuarios")
def register_user(payload: RegisterRequest, db: Session = Depends(database.get_db)):
    username = payload.username or payload.email.split("@")[0]
    existing_user = db.query(models.User).filter(
        (models.User.email == payload.email) | (models.User.username == username)
    ).first()
    
    if existing_user:
        raise HTTPException(status_code=400, detail="El correo o nombre de usuario ya está registrado.")
    
    hashed_pwd = auth.hash_password(payload.password)
    new_user = models.User(
        username=username,
        email=payload.email,
        hashed_password=hashed_pwd,
        full_name=payload.full_name,
        role="user"
    )
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    
    token = auth.create_access_token({"sub": new_user.email, "user_id": new_user.id, "role": new_user.role})
    return {
        "status": "success",
        "message": "Usuario registrado exitosamente.",
        "access_token": token,
        "token_type": "bearer",
        "user": {
            "id": new_user.id,
            "email": new_user.email,
            "username": new_user.username,
            "full_name": new_user.full_name
        }
    }

@app.post("/auth/login", summary="Inicio de Sesión (Login)")
def login_user(payload: LoginRequest, db: Session = Depends(database.get_db)):
    user = db.query(models.User).filter(models.User.email == payload.email).first()
    
    if not user or not auth.verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=401, detail="Credenciales incorrectas. Verifique correo y contraseña.")
    
    token = auth.create_access_token({"sub": user.email, "user_id": user.id, "role": user.role})
    return {
        "status": "success",
        "message": "Inicio de sesión exitoso.",
        "access_token": token,
        "token_type": "bearer",
        "user": {
            "id": user.id,
            "email": user.email,
            "username": user.username,
            "full_name": user.full_name
        }
    }

class DeleteAccountRequest(BaseModel):
    email: str

@app.post("/auth/delete-account", summary="Eliminar Cuenta de Usuario")
@app.delete("/auth/delete-account", summary="Eliminar Cuenta de Usuario")
def delete_user_account(payload: DeleteAccountRequest, db: Session = Depends(database.get_db)):
    user = db.query(models.User).filter(
        (models.User.email == payload.email) | (models.User.username == payload.email)
    ).first()
    
    if not user:
        raise HTTPException(status_code=404, detail="El usuario no fue encontrado en la base de datos.")
    
    # Eliminar reportes asignados a este usuario
    try:
        db.query(models.PdfExport).filter(models.PdfExport.user_id == user.id).delete()
    except Exception:
        pass

    db.delete(user)
    db.commit()
    
    return {
        "status": "success",
        "message": f"Cuenta del usuario '{payload.email}' eliminada permanentemente de la base de datos."
    }

class DetectResponse(BaseModel):
    is_synthetic: bool
    confidence: float

# ============================================================
# GEMINI AI - Explicabilidad Forense & Orquestador GenUI
# ============================================================
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.6-flash")
GEMINI_API_URL = f"https://generativelanguage.googleapis.com/v1beta/models/{GEMINI_MODEL}:generateContent"

class GeminiExplainRequest(BaseModel):
    overall_risk_ai: float
    max_ai_prob: float
    avg_ai_prob: float = 0.0
    label: str = ""

class GeminiGenUiRequest(BaseModel):
    query: str
    overall_risk_ai: float = 0.0
    max_ai_prob: float = 0.0
    label: str = ""

async def _call_gemini(prompt: str, schema: dict) -> dict:
    """Llama a la API de Gemini pidiendo salida JSON estructurada según `schema`."""
    if not GEMINI_API_KEY:
        raise HTTPException(status_code=503, detail="GEMINI_API_KEY no configurada en el servidor.")

    payload = {
        "contents": [{"parts": [{"text": prompt}]}],
        "generationConfig": {
            "responseMimeType": "application/json",
            "responseSchema": schema,
            "temperature": 0.4,
        },
    }
    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            resp = await client.post(GEMINI_API_URL, params={"key": GEMINI_API_KEY}, json=payload)
    except httpx.TimeoutException:
        raise HTTPException(status_code=504, detail="Tiempo de espera agotado llamando a Gemini API.")

    if resp.status_code != 200:
        raise HTTPException(status_code=502, detail=f"Error de Gemini API ({resp.status_code}): {resp.text[:300]}")

    data = resp.json()
    try:
        text = data["candidates"][0]["content"]["parts"][0]["text"]
        return json.loads(text)
    except (KeyError, IndexError, json.JSONDecodeError) as e:
        raise HTTPException(status_code=502, detail=f"Respuesta inesperada de Gemini: {e}")

@app.post("/gemini/forensic-explanation", summary="Explicación Forense Generada por Gemini AI")
async def gemini_forensic_explanation(payload: GeminiExplainRequest):
    """
    Genera (con Gemini real, no simulado) el dictamen forense de 2do nivel
    que antes estaba hardcodeado en el cliente Flutter.
    """
    schema = {
        "type": "OBJECT",
        "properties": {
            "status": {"type": "STRING"},
            "badge": {"type": "STRING"},
            "title": {"type": "STRING"},
            "summary": {"type": "STRING"},
            "findings": {"type": "ARRAY", "items": {"type": "STRING"}},
            "action_recommendation": {"type": "STRING"},
            "confidence_score": {"type": "STRING"},
        },
        "required": ["status", "badge", "title", "summary", "findings", "action_recommendation", "confidence_score"],
    }
    prompt = (
        "Eres el motor forense de segundo nivel de GearShield, un sistema de deteccion de voz "
        "sintetica/deepfake en llamadas telefonicas.\n\n"
        f"Metricas del motor biometrico ONNX para este clip:\n"
        f"- Riesgo IA global: {payload.overall_risk_ai:.1f}%\n"
        f"- Probabilidad maxima de IA en una ventana: {payload.max_ai_prob:.1f}%\n"
        f"- Probabilidad promedio de IA: {payload.avg_ai_prob:.1f}%\n"
        f"- Etiqueta del motor: {payload.label}\n\n"
        "Genera un dictamen forense breve, tecnico y creible en espanol, en el tono de un analista "
        "de seguridad biometrica de voz. No contradigas las metricas dadas (si el riesgo es bajo, "
        "el dictamen debe ser de aprobacion; si es alto, de alerta). Responde SOLO con el JSON solicitado."
    )
    return await _call_gemini(prompt, schema)

@app.post("/gemini/genui-intent", summary="Orquestador GenUI: Gemini decide que widgets renderizar")
async def gemini_genui_intent(payload: GeminiGenUiRequest):
    """
    GenUI real: Gemini interpreta una peticion en lenguaje natural del analista
    y decide dinamicamente que widgets del panel activar.
    """
    schema = {
        "type": "OBJECT",
        "properties": {
            "intent": {"type": "STRING"},
            "response_text": {"type": "STRING"},
            "widgets": {"type": "ARRAY", "items": {"type": "STRING"}},
            "risk_prob": {"type": "NUMBER"},
        },
        "required": ["intent", "response_text", "widgets", "risk_prob"],
    }
    prompt = (
        "Eres el orquestador GenUI de GearShield: decides QUE widgets mostrar en un panel de "
        "seguridad biometrica de voz, segun lo que pide el usuario en lenguaje natural.\n\n"
        "Widgets disponibles (usa EXACTAMENTE estos strings, elige entre 1 y 7):\n"
        '- "spectrogram": visor de espectrograma forense\n'
        '- "gauge": medidor radial de riesgo de IA\n'
        '- "ab_player": comparador de audio A/B (voz real vs sospechosa)\n'
        '- "gemini_note": nota de explicabilidad forense generada por IA\n'
        '- "pdf_preview": generador de certificado PDF de auditoria\n'
        '- "audit_stats": resumen de estadisticas de auditoria (llamadas totales, falsos positivos)\n'
        '- "blacklist_stats": total de intentos de fraude/voces reportadas a la lista negra\n\n'
        f"Contexto actual del analisis:\n"
        f"- Riesgo IA global: {payload.overall_risk_ai:.1f}%\n"
        f"- Probabilidad maxima de IA: {payload.max_ai_prob:.1f}%\n"
        f"- Etiqueta: {payload.label}\n\n"
        f'Peticion del usuario: "{payload.query}"\n\n'
        "Responde SOLO con el JSON: intent (una palabra en mayusculas, ej. EXPLANATION, SPECTROGRAM, "
        "PDF_EXPORT, COMPARISON, AUDIT_STATS), response_text (una frase en espanol confirmando que vas "
        "a mostrar), widgets (lista de 1 a 5 strings del vocabulario de arriba), risk_prob (usa el "
        "riesgo IA global dado arriba, no inventes otro numero)."
    )
    return await _call_gemini(prompt, schema)

@app.get("/health", summary="Estado del Servidor y Motor")
def health_check():
    """
    Verifica el estado de salud del servidor y la disponibilidad del motor ONNX / Joblib.
    """
    onnx_exists = os.path.exists("gearshield_engine.onnx")
    return {
        "status": "online",
        "service": "GearShield Security API",
        "engine_ready": model is not None,
        "onnx_model_available": onnx_exists,
        "onnx_model_path": "gearshield_engine.onnx" if onnx_exists else None,
        "timestamp": datetime.now().isoformat()
    }

@app.post("/detect", response_model=DetectResponse, summary="Altur HackMTY26 Automated Benchmark Endpoint")
async def detect_endpoint(request: Request):
    """
    Endpoint automatizado exigido por Altur (HackMTY26).
    Recibe un clip WAV estéreo (8kHz, codificado en Base64; Canal 0 = caller, Canal 1 = agent).
    Retorna veredicto estricto:
    {
      "is_synthetic": bool,
      "confidence": float
    }
    """
    b64_str = None
    try:
        body_json = await request.json()
        if isinstance(body_json, str):
            b64_str = body_json
        elif isinstance(body_json, dict):
            for key in ["audio_base64", "audio", "wav", "audio_b64", "clip", "file", "data"]:
                if key in body_json and isinstance(body_json[key], str):
                    b64_str = body_json[key]
                    break
            if not b64_str:
                longest_str = ""
                for val in body_json.values():
                    if isinstance(val, str) and len(val) > len(longest_str):
                        longest_str = val
                if len(longest_str) > 20:
                    b64_str = longest_str
    except Exception:
        body_bytes = await request.body()
        raw_text = body_bytes.decode("utf-8", errors="ignore").strip()
        if raw_text.startswith('"') and raw_text.endswith('"'):
            raw_text = raw_text[1:-1]
        b64_str = raw_text

    if not b64_str:
        raise HTTPException(status_code=400, detail="No se encontró contenido audio base64 válido en la solicitud.")

    try:
        # Decodificar Base64
        audio_bytes = base64.b64decode(b64_str)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error decodificando audio base64: {str(e)}")

    try:
        # Leer buffer WAV (Stereo 8kHz)
        data, sr = sf.read(io.BytesIO(audio_bytes), dtype='float32')
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"Error leyendo formato WAV estéreo: {str(e)}")

    # Extraer Canal 0 (Caller)
    if hasattr(data, 'shape') and len(data.shape) > 1:
        caller_audio = data[:, 0] if data.shape[1] >= 2 else data[0, :]
    else:
        caller_audio = data

    # Remuestrear a 16kHz: analyze_audio() asume 16kHz cuando recibe un array
    # en lugar de una ruta de archivo, y el juez envía WAV a 8kHz.
    target_sr = 16000
    if sr != target_sr:
        import librosa
        caller_audio = librosa.resample(caller_audio, orig_sr=sr, target_sr=target_sr)

    # Ejecutar motor de inferencia biofísica
    analysis = analyze_audio(caller_audio, engine=model, scaler=scaler)

    if "error" in analysis:
        raise HTTPException(status_code=400, detail=analysis["error"])

    overall_risk = analysis.get("overall_risk_ai", 0.0)
    max_ai_prob = analysis.get("max_ai_prob", 0.0)

    # Veredicto de IA sintética vs Humano
    is_synthetic = bool(overall_risk >= 50.0 or max_ai_prob >= 60.0)

    # confidence = P(sintetico), score monotono para que el AUC del juez
    # sea coherente entre llamadas humanas y sinteticas (no "certeza del veredicto").
    raw_conf = max(overall_risk, max_ai_prob) / 100.0
    confidence = float(round(max(0.01, min(0.99, raw_conf)), 2))

    return {
        "is_synthetic": is_synthetic,
        "confidence": confidence
    }

@app.post("/analyze", summary="Analizar Archivo de Audio", response_model=AnalysisResponse)
async def analyze_audio_endpoint(file: UploadFile = File(...)):
    """
    Recibe un archivo de audio (.wav, .mp3, .ogg, etc.) y ejecuta el análisis temporal mediante Ventana Deslizante.
    """
    file_id = str(uuid.uuid4())[:8]
    ext = os.path.splitext(file.filename)[1] or ".wav"
    temp_filename = f"{file_id}_{file.filename}"
    temp_path = os.path.join(UPLOAD_DIR, temp_filename)

    try:
        with open(temp_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # Ejecutar análisis con GearShield Engine
        result = analyze_audio(temp_path, engine=model, scaler=scaler)

        if "error" in result:
            raise HTTPException(status_code=400, detail=result["error"])

        # Registrar en la base de datos de administración y métricas
        record_log_entry(result, filename=file.filename)

        return result

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error procesando audio: {str(e)}")
    finally:
        # Limpieza del archivo temporal
        if os.path.exists(temp_path):
            try:
                os.remove(temp_path)
            except Exception:
                pass

@app.post("/reconfirm", summary="Reconfirmación de Voz (5% Audit & Cloud Backup)")
async def reconfirm_voice_endpoint(
    file: UploadFile = File(...),
    user_id: Optional[str] = Form("anonymous"),
    reason: Optional[str] = Form("Auditoria de Segunda Firma de Voz"),
    generate_pdf: bool = Form(True)
):
    """
    Procesa el 5% de audios de reconfirmación que requieren una segunda validación.
    Almacena el registro de auditoría y genera un reporte forense en PDF.
    """
    reconfirm_id = str(uuid.uuid4())[:10]
    filename = f"reconfirm_{reconfirm_id}_{file.filename}"
    save_path = os.path.join(RECONFIRM_DIR, filename)

    try:
        with open(save_path, "wb") as buffer:
            shutil.copyfileobj(file.file, buffer)

        # 1. Analizar el audio de reconfirmacion
        analysis_result = analyze_audio(save_path, engine=model, scaler=scaler)
        if "error" in analysis_result:
            raise HTTPException(status_code=400, detail=analysis_result["error"])

        pdf_path = None
        pdf_filename = None

        # 2. Generar Reporte Forense PDF si fue solicitado
        if generate_pdf:
            pdf_filename = f"Reporte_Reconfirmacion_{reconfirm_id}.pdf"
            pdf_path = os.path.join(REPORTS_DIR, pdf_filename)
            generate_forensic_pdf(analysis_result, output_pdf_path=pdf_path)

        return {
            "status": "reconfirmed",
            "reconfirmation_id": reconfirm_id,
            "user_id": user_id,
            "reason": reason,
            "analysis": analysis_result,
            "pdf_report_path": pdf_path,
            "pdf_download_url": f"/reports/{pdf_filename}" if pdf_filename else None,
            "timestamp": datetime.now().isoformat()
        }

    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error en reconfirmación: {str(e)}")

@app.post("/generate-pdf", summary="Generar y Registrar Reporte PDF")
async def generate_pdf_endpoint(
    analysis_data: dict, 
    user_id: Optional[int] = 1,
    db: Session = Depends(database.get_db)
):
    """
    Recibe un objeto JSON con los resultados de análisis, genera el reporte PDF y lo registra en la Base de Datos.
    """
    try:
        report_uuid = str(uuid.uuid4())[:8]
        pdf_filename = f"Reporte_{report_uuid}.pdf"
        pdf_path = os.path.join(REPORTS_DIR, pdf_filename)
        
        # 1. Generar el PDF físico mediante reportlab
        generate_forensic_pdf(analysis_data, output_pdf_path=pdf_path)

        # 2. Registrar en la Base de Datos
        overall_risk = analysis_data.get("overall_risk_ai", 0.0)
        new_pdf_record = models.PdfExport(
            report_uuid=report_uuid,
            user_id=user_id,
            filename=pdf_filename,
            pdf_path=pdf_path,
            overall_risk_ai=overall_risk,
            is_synthetic=overall_risk >= 50.0
        )
        db.add(new_pdf_record)
        db.commit()

        return FileResponse(
            pdf_path,
            media_type="application/pdf",
            filename=pdf_filename
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error generando PDF: {str(e)}")

class FalsePositiveRequest(BaseModel):
    log_id: str
    reason: Optional[str] = "Reportado por usuario/administrador"

@app.get("/stats", summary="Métricas Globales de Administración y Dashboard")
def get_stats_endpoint():
    """
    Retorna métricas consolidadas: llamadas totales, detecciones IA, deepfakes de alto riesgo y falsos positivos.
    """
    logs = load_logs()
    total_calls = len(logs)
    ai_calls = sum(1 for item in logs if item.get("is_synthetic", False))
    deepfakes = sum(1 for item in logs if item.get("overall_risk_ai", 0.0) >= 75.0)
    false_positives = sum(1 for item in logs if item.get("is_false_positive", False))
    human_calls = total_calls - ai_calls

    ai_percentage = round((ai_calls / total_calls * 100.0), 1) if total_calls > 0 else 0.0

    return {
        "total_calls": total_calls,
        "ai_calls_detected": ai_calls,
        "human_calls_detected": human_calls,
        "deepfakes_count": deepfakes,
        "reported_false_positives": false_positives,
        "ai_percentage": ai_percentage,
        "last_updated": datetime.now().isoformat()
    }

@app.get("/logs", summary="Historial Reciente de Llamadas y Detecciones")
def get_logs_endpoint():
    """
    Retorna el historial ordenado de llamadas analizadas para la tabla de administración.
    """
    return load_logs()

class BlacklistReportRequest(BaseModel):
    audio_path: Optional[str] = None
    label: Optional[str] = None
    overall_risk_ai: float = 0.0
    max_ai_prob: float = 0.0
    reporter_note: Optional[str] = None

@app.post("/blacklist/report", summary="Reportar Voz Sospechosa a la Lista Negra")
def report_to_blacklist(payload: BlacklistReportRequest, db: Session = Depends(database.get_db)):
    """
    Registra un intento de fraude (voz sintética de alto riesgo) en la lista negra
    y regresa el conteo total actualizado de intentos reportados.
    """
    entry = models.BlacklistReport(
        audio_path=payload.audio_path,
        label=payload.label,
        overall_risk_ai=payload.overall_risk_ai,
        max_ai_prob=payload.max_ai_prob,
        reporter_note=payload.reporter_note,
    )
    db.add(entry)
    db.commit()
    db.refresh(entry)

    total_reports = db.query(models.BlacklistReport).count()

    return {
        "status": "success",
        "message": "Voz registrada en la lista negra de intentos de fraude.",
        "report_id": entry.id,
        "total_reports": total_reports,
    }

@app.get("/blacklist/stats", summary="Total de Intentos de Engaño Reportados")
def get_blacklist_stats(db: Session = Depends(database.get_db)):
    """
    Retorna el conteo total de voces reportadas a la lista negra, para el widget
    'Total de Intentos de Engaño' del panel GenUI.
    """
    total_reports = db.query(models.BlacklistReport).count()
    latest = (
        db.query(models.BlacklistReport)
        .order_by(models.BlacklistReport.created_at.desc())
        .limit(5)
        .all()
    )
    return {
        "total_reports": total_reports,
        "recent": [
            {
                "id": r.id,
                "audio_path": r.audio_path,
                "label": r.label,
                "overall_risk_ai": r.overall_risk_ai,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in latest
        ],
    }

@app.post("/report-false-positive", summary="Reportar Falso Positivo")
def report_false_positive_endpoint(payload: FalsePositiveRequest):
    """
    Marca un registro de llamada como Falso Positivo y recalcula las estadísticas.
    """
    logs = load_logs()
    found = False
    for log in logs:
        if log.get("id") == payload.log_id:
            log["is_false_positive"] = True
            log["false_positive_reason"] = payload.reason
            found = True
            break
    
    if not found:
        raise HTTPException(status_code=404, detail="No se encontró el registro especificado.")
    
    save_logs(logs)
    return {
        "status": "success",
        "message": "Falso positivo registrado correctamente.",
        "log_id": payload.log_id
    }

@app.get("/reports/{pdf_filename}", summary="Descargar Reporte PDF")
def download_pdf_endpoint(pdf_filename: str):
    """
    Permite la descarga de un reporte PDF generado previamente.
    """
    file_path = os.path.join(REPORTS_DIR, pdf_filename)
    if not os.path.exists(file_path):
        raise HTTPException(status_code=404, detail="El reporte especificado no existe.")
    
    return FileResponse(file_path, media_type="application/pdf", filename=pdf_filename)

if __name__ == "__main__":
    import uvicorn
    port = int(os.environ.get("PORT", 8000))
    print(f"=== Iniciando Servidor FastAPI de GearShield en puerto {port} ===")
    print(f" Servidor listo en: http://0.0.0.0:{port}")
    print(f" Documentación interactiva Swagger disponible en: http://127.0.0.1:{port}/docs")
    uvicorn.run(app, host="0.0.0.0", port=port)
