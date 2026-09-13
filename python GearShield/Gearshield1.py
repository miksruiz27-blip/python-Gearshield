"""
Gearshield1.py - Motor Principal de Inferencia y Detección de Audio (GearShield 2.0 Enterprise).
Soporta análisis temporal biofísico de 220 dimensiones, suavizado EMA y detección de inyección/splicing mid-sentence.
"""

import os
import sys
import glob
import joblib
import numpy as np

try:
    import onnxruntime as ort
    HAS_ONNX = True
except ImportError:
    HAS_ONNX = False

from DataSet import extract_features, extract_features_sliding_window
from MLbaseline import train_baseline_model, MODEL_PATH

AI_THRESHOLD = 60.0  # Umbral calibrado de riesgo para declarar presencia de IA (%)
ONNX_MODEL_PATH = "gearshield_engine.onnx"

def load_gearshield_engine(model_path=MODEL_PATH):
    """
    Carga el motor de inferencia ONNX runtime o Scikit-Learn pipeline fallback.
    """
    # Preferir ONNX Runtime para máxima velocidad e integración móvil
    if HAS_ONNX and os.path.exists(ONNX_MODEL_PATH):
        try:
            session = ort.InferenceSession(ONNX_MODEL_PATH)
            pipeline_data = joblib.load(model_path) if os.path.exists(model_path) else None
            scaler = pipeline_data["scaler"] if pipeline_data else None
            return {"type": "onnx", "session": session, "scaler": scaler}, scaler
        except Exception:
            pass

    if not os.path.exists(model_path):
        print(f"[INFO] Modelo '{model_path}' no encontrado. Generando y entrenando motor GearShield 2.0...")
        train_baseline_model(model_save_path=model_path)

    try:
        pipeline_data = joblib.load(model_path)
        return {"type": "sklearn", "model": pipeline_data["model"], "scaler": pipeline_data["scaler"]}, pipeline_data["scaler"]
    except Exception as e:
        print(f"[ERROR] No se pudo cargar el motor desde '{model_path}': {e}")
        return None, None

def analyze_audio(audio_path, engine=None, scaler=None, model_path=MODEL_PATH, window_sec=3.0, hop_sec=1.0, alpha_ema=0.4):
    """
    Analiza un archivo de audio mediante Ventana Deslizante (Chunking / Sliding Window) con Suavizado EMA
    y Detección de Inyección/Empalme (Audio Splicing).
    """
    if engine is None or scaler is None:
        engine, scaler = load_gearshield_engine(model_path)
        if engine is None:
            return {"error": "No se pudo inicializar el motor GearShield 2.0."}

    if isinstance(audio_path, str):
        if not os.path.exists(audio_path):
            return {"error": f"El archivo '{audio_path}' no existe."}
        audio_input = audio_path
    else:
        audio_input = audio_path

    # 1. Extracción de ventanas deslizantes (220 características biofísicas)
    chunks = extract_features_sliding_window(audio_input, window_sec=window_sec, hop_sec=hop_sec)
    if not chunks:
        return {"error": "Error al extraer ventanas de audio."}

    timeline = []
    ai_detected_intervals = []
    max_ai_prob = 0.0
    sum_ai_prob = 0.0
    prev_ema = None

    # 2. Inferencia segmento a segmento con suavizado EMA
    for chunk in chunks:
        feat = chunk["features"].astype(np.float32)
        
        if engine["type"] == "onnx":
            session = engine["session"]
            input_name = session.get_inputs()[0].name
            outputs = session.run(None, {input_name: [feat]})
            prob_arr = outputs[1][0]
            if isinstance(prob_arr, dict):
                raw_prob_ai = float(prob_arr.get(1, prob_arr.get(1.0, 0.0)) * 100)
            else:
                raw_prob_ai = float(prob_arr[1] * 100)
        else:
            model = engine["model"]
            feat_scaled = scaler.transform([feat])
            probs = model.predict_proba(feat_scaled)[0]
            raw_prob_ai = float(probs[1] * 100)

        # Suavizado Exponencial Temporal (EMA)
        if prev_ema is None:
            prob_ai = raw_prob_ai
        else:
            prob_ai = alpha_ema * raw_prob_ai + (1 - alpha_ema) * prev_ema
        prev_ema = prob_ai

        prob_human = 100.0 - prob_ai

        if prob_ai > max_ai_prob:
            max_ai_prob = prob_ai
            
        sum_ai_prob += prob_ai

        is_ai_chunk = prob_ai >= AI_THRESHOLD
        if is_ai_chunk:
            ai_detected_intervals.append((chunk["start_sec"], chunk["end_sec"], prob_ai))

        timeline.append({
            "start_sec": chunk["start_sec"],
            "end_sec": chunk["end_sec"],
            "prob_human": prob_human,
            "prob_ai": prob_ai,
            "raw_prob_ai": raw_prob_ai,
            "is_ai": is_ai_chunk
        })

    avg_ai_prob = sum_ai_prob / len(chunks)

    # 3. Arquitectura de 3 Zonas de Riesgo Empresarial (Verde / Amarilla / Roja)
    if max_ai_prob >= 70.0 or len(ai_detected_intervals) == len(chunks):
        risk_zone = "ZONA_ROJA"
        label = "INTELIGENCIA ARTIFICIAL (100% Sintético / Deepfake)"
        action_required = "BLOQUEO_ALERTA_DEEPFAKE"
        overall_risk = max_ai_prob
    elif max_ai_prob >= 35.0 or len(ai_detected_intervals) > 0:
        risk_zone = "ZONA_AMARILLA"
        label = "AUDIO SOSPECHOSO / AMBIGUO (Requiere Reconfirmación de Voz)"
        action_required = "RECONFIRMACION_SEGUNDA_PRUEBA"
        overall_risk = max_ai_prob
    else:
        risk_zone = "ZONA_VERDE"
        label = "VOZ HUMANA ORGÁNICA (Sin alteración de IA)"
        action_required = "APROBADO_ACCESO_CONCEDIDO"
        overall_risk = avg_ai_prob

    return {
        "audio_path": audio_path,
        "label": label,
        "risk_zone": risk_zone,
        "action_required": action_required,
        "overall_risk_ai": overall_risk,
        "max_ai_prob": max_ai_prob,
        "avg_ai_prob": avg_ai_prob,
        "ai_detected_intervals": ai_detected_intervals,
        "timeline": timeline
    }

def print_analysis_report(result):
    """
    Imprime un informe detallado con la línea de tiempo de riesgo (Risk Timeline).
    """
    if "error" in result:
        print(f"\n[ERROR] {result['error']}\n")
        return

    filename = os.path.basename(result['audio_path'])
    print("\n" + "=" * 75)
    print("        GEARSHIELD 2.0 ENTERPRISE ENGINE - ANALISIS BIOFISICO TEMPORAL")
    print("=" * 75)
    print(f" Archivo Analizado: {filename}")
    print(f" Diagnóstico:      {result['label']}")
    print(f" Zona de Riesgo:   {result['risk_zone']}")
    print(f" Acción Requerida: {result['action_required']}")
    print(f" Nivel Máx de Riesgo IA: {result['max_ai_prob']:.2f}% (Promedio: {result['avg_ai_prob']:.2f}%)")
    print("-" * 75)

    # Imprimir Alerta de Intervalos Mixtos / Inyección
    if result["ai_detected_intervals"]:
        print(" [ALERTA DE SEGURIDAD] IA / Inyeccion detectada en los siguientes intervalos:")
        for start, end, prob in result["ai_detected_intervals"]:
            print(f"    --> Segundos {start:.1f}s a {end:.1f}s | Riesgo IA (EMA): {prob:.1f}%")
        print("-" * 75)

    # Imprimir Timeline de Riesgo Ventana por Ventana
    print(" LINEA DE TIEMPO DE RIESGO (VENTANA DESLIZANTE CON BIOFISICA 220-D):")
    for item in result["timeline"]:
        tag = "[!] ALERTA IA" if item["is_ai"] else "[OK] Humano  "
        bar = "#" * int(item["prob_ai"] // 5)
        print(f"  [{item['start_sec']:4.1f}s - {item['end_sec']:4.1f}s] {tag} | IA: {item['prob_ai']:5.1f}% [{bar:<20}]")
    
    print("=" * 75 + "\n")

if __name__ == "__main__":
    print("===========================================================================")
    print("    GEARSHIELD 2.0 ENTERPRISE - AUDIO DEEPFAKE & SPLICING DETECTOR ENGINE ")
    print("===========================================================================")

    engine, scaler = load_gearshield_engine()

    if len(sys.argv) > 1:
        target_audio = sys.argv[1]
        res = analyze_audio(target_audio, engine, scaler)
        print_analysis_report(res)
    else:
        # Probar audios reales de WhatsApp y sintéticos
        gaby_path = "gabyruiz.ogg"
        if os.path.exists(gaby_path):
            print("\n[INFO] Ejecutando analisis en nota de voz real de WhatsApp (gabyruiz.ogg):")
            res_gaby = analyze_audio(gaby_path, engine, scaler)
            print_analysis_report(res_gaby)

        gali_path = "data/human/gali.ogg"
        if os.path.exists(gali_path):
            print("\n[INFO] Ejecutando analisis en nota de voz real de WhatsApp (gali.ogg):")
            res_gali = analyze_audio(gali_path, engine, scaler)
            print_analysis_report(res_gali)

