"""
evaluate_test_set.py - Evaluador y Benchmarking de GearShield.
Ejecuta la inferencia completa del motor contra un dataset de prueba independiente (WAV/MP3 + JSON)
y calcula métricas detalladas (Accuracy, Precision, Recall, F1, FAR, FRR, Matriz de Confusión).
"""

import os
import sys
import glob
import json
import re
import argparse
import numpy as np
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score, precision_score, recall_score, f1_score

# Asegurar import de módulos locales
current_dir = os.path.dirname(os.path.abspath(__file__))
if current_dir not in sys.path:
    sys.path.insert(0, current_dir)

from Gearshield1 import analyze_audio, load_gearshield_engine

def natural_sort_key(s):
    """Ordena nombres numéricos de forma natural: 1, 2, 10 en lugar de 1, 10, 2."""
    return [int(text) if text.isdigit() else text.lower() for text in re.split(r'(\d+)', s)]

def determine_ground_truth(meta, base_name):
    """
    Determina si la muestra es sintética (1 / AI) o humana (0 / Human)
    inspeccionando campos comunes en el JSON o el nombre del archivo.
    """
    if not isinstance(meta, dict):
        return 1 if any(k in base_name.lower() for k in ['ai', 'bot', 'syn', 'fake']) else 0

    # 1. Banderas booleanas explícitas
    for key in ['is_ai', 'is_bot', 'is_synthetic', 'synthetic', 'is_machine']:
        if key in meta and isinstance(meta[key], bool):
            return 1 if meta[key] else 0

    # 2. Metadatos de texto
    label_str = str(
        meta.get('receptor_type', '') or 
        meta.get('label', '') or 
        meta.get('type', '') or 
        meta.get('status', '') or 
        meta.get('answering_machine', '')
    ).lower()

    if any(k in label_str for k in ['bot', 'ia', 'ai', 'machine', 'voicemail', 'synthetic', 'fake']):
        return 1
    if any(k in label_str for k in ['human', 'humano', 'real', 'organic']):
        return 0

    # 3. Inspección de turnos si existen
    turns = meta.get('turns', [])
    if isinstance(turns, list) and len(turns) > 0:
        for t in turns:
            t_label = str(t.get('label', '') or t.get('speaker_type', '')).lower()
            if any(k in t_label for k in ['bot', 'ia', 'ai', 'synthetic']):
                return 1

    # 4. Fallback por nombre del archivo
    if any(k in base_name.lower() for k in ['ai', 'bot', 'syn', 'fake']):
        return 1
    
    return 0

def run_benchmark(test_dir="python GearShield/TESTING", mode="sentence_vad", output_report=True):
    print("\n" + "=" * 75)
    print("   EVALUADOR DE BENCHMARKING DE GEARSHIELD 2.0 (TEST SET EVALUATION)")
    print("=" * 75 + "\n")

    # Búsqueda robusta de la carpeta de testing
    candidates = [
        test_dir,
        os.path.join(current_dir, test_dir),
        os.path.join(current_dir, "TESTING"),
        os.path.join(current_dir, "..", test_dir)
    ]
    test_dir_abs = None
    for cand in candidates:
        if os.path.exists(cand):
            test_dir_abs = os.path.abspath(cand)
            break
    if not test_dir_abs:
        test_dir_abs = os.path.abspath(test_dir)

    jsons_dir = os.path.join(test_dir_abs, "JSON")
    if not os.path.exists(jsons_dir):
        jsons_dir = os.path.join(test_dir_abs, "jsons")
    if not os.path.exists(jsons_dir):
        jsons_dir = test_dir_abs

    wavs_dir = os.path.join(test_dir_abs, "WAV")
    if not os.path.exists(wavs_dir):
        wavs_dir = os.path.join(test_dir_abs, "wavs")
    if not os.path.exists(wavs_dir):
        wavs_dir = test_dir_abs

    json_files = sorted(glob.glob(os.path.join(jsons_dir, "*.json")), key=natural_sort_key)
    audio_extensions = ["*.wav", "*.mp3", "*.flac", "*.ogg", "*.m4a"]
    wav_files = []
    for ext in audio_extensions:
        wav_files.extend(glob.glob(os.path.join(wavs_dir, ext)))
    wav_files = sorted(wav_files, key=natural_sort_key)

    if not wav_files:
        print(f"[!] No se encontraron archivos de audio (.wav, .mp3, etc.) en '{wavs_dir}'.")
        print(f"💡 Asegúrate de colocar los archivos de audio en la carpeta:\n    {wavs_dir}")
        return

    print(f"[INFO] Carpeta de Pruebas: {test_dir_abs}")
    print(f"[INFO] Encontrados {len(wav_files)} archivos de audio y {len(json_files)} JSONs de metadatos.")

    # Pareado por nombre o por orden ordinal
    pairs = []
    wav_dict = {os.path.splitext(os.path.basename(w))[0]: w for w in wav_files}
    matched_by_name = True

    if json_files:
        for j_path in json_files:
            bname = os.path.splitext(os.path.basename(j_path))[0]
            if bname in wav_dict:
                pairs.append((j_path, wav_dict[bname]))
            else:
                matched_by_name = False
                break
        
        if not matched_by_name or len(pairs) == 0:
            print("[INFO] Pareando archivos secuencialmente por orden ordinal...")
            pairs = list(zip(json_files, wav_files))
    else:
        print("[INFO] No se encontraron JSONs. Se inferirá Ground Truth a partir del nombre del archivo.")
        pairs = [(None, w) for w in wav_files]

    print(f"[OK] Se formaron {len(pairs)} muestras para evaluación.\n")

    # Cargar motor GearShield
    print("[INFO] Inicializando motor de inferencia GearShield...")
    engine, scaler = load_gearshield_engine()
    if engine is None:
        print("[ERROR] No se pudo cargar el motor GearShield.")
        return

    y_true = []
    y_pred = []
    y_scores = []
    details = []

    for idx, (json_path, wav_path) in enumerate(pairs):
        base_name = os.path.splitext(os.path.basename(wav_path))[0]
        meta = {}
        if json_path and os.path.exists(json_path):
            try:
                with open(json_path, 'r', encoding='utf-8') as f:
                    meta = json.load(f)
            except Exception as e:
                print(f"   [!] Error leyendo JSON '{json_path}': {e}")

        ground_truth = determine_ground_truth(meta, base_name)
        
        # Inferencia con GearShield
        result = analyze_audio(wav_path, engine=engine, scaler=scaler, mode=mode)
        
        if "error" in result:
            print(f"   [!] Error en audio {base_name}: {result['error']}")
            continue

        verdict = result.get("verdict", "ORGANIC_HUMAN")
        risk_pct = float(result.get("overall_risk_ai", result.get("risk_score_ai", 0.0)))

        # Veredicto binario: AI_GENERATED -> 1, ORGANIC_HUMAN / SUSPICIOUS_REVERIFY -> 0 (o según threshold)
        pred_label = 1 if verdict == "AI_GENERATED" or risk_pct >= 60.0 else 0

        y_true.append(ground_truth)
        y_pred.append(pred_label)
        y_scores.append(risk_pct)

        status_str = "MATCH [OK]" if ground_truth == pred_label else "MISMATCH [FAIL]"
        gt_str = "AI" if ground_truth == 1 else "HUMAN"
        pred_str = "AI" if pred_label == 1 else "HUMAN"

        print(f"[{idx+1:03d}/{len(pairs):03d}] {base_name[:30]:<30} | Esperanza: {gt_str:<5} | Predicho: {verdict:<18} ({risk_pct:5.1f}%) | {status_str}")

        details.append({
            "audio_file": os.path.basename(wav_path),
            "json_file": os.path.basename(json_path) if json_path else None,
            "ground_truth": ground_truth,
            "ground_truth_label": gt_str,
            "predicted_label": pred_label,
            "predicted_label_str": pred_str,
            "verdict": verdict,
            "risk_ai_percentage": risk_pct,
            "correct": ground_truth == pred_label,
            "sentences_analyzed": result.get("sentences_analyzed", len(result.get("timeline", []))),
            "latency_ms": result.get("latency_ms", 0.0)
        })

    y_true = np.array(y_true)
    y_pred = np.array(y_pred)

    if len(y_true) == 0:
        print("[!] No se procesaron muestras válidas.")
        return

    # Cálculo de Métricas
    acc = accuracy_score(y_true, y_pred)
    prec = precision_score(y_true, y_pred, zero_division=0)
    rec = recall_score(y_true, y_pred, zero_division=0)
    f1 = f1_score(y_true, y_pred, zero_division=0)
    cm = confusion_matrix(y_true, y_pred, labels=[0, 1])

    tn, fp, fn, tp = cm.ravel() if cm.size == 4 else (0, 0, 0, 0)
    far = (fp / (fp + tn)) * 100.0 if (fp + tn) > 0 else 0.0  # False Acceptance Rate (Humano como IA)
    frr = (fn / (fn + tp)) * 100.0 if (fn + tp) > 0 else 0.0  # False Rejection Rate (IA como Humano)

    print("\n" + "=" * 75)
    print("                RESULTADOS DEL BENCHMARK DE GEARSHIELD 2.0")
    print("=" * 75)
    print(f" Muestras Evaluadas:                 {len(y_true)}")
    print(f" Exactitud (Accuracy):               {acc * 100:.2f}%")
    print(f" Precisión (Precision):             {prec * 100:.2f}%")
    print(f" Sensibilidad (Recall):             {rec * 100:.2f}%")
    print(f" Puntaje F1 (F1-Score):             {f1 * 100:.2f}%")
    print(f" Tasa de Falsos Positivos (FAR):     {far:.2f}%  (Humanos calificados como IA)")
    print(f" Tasa de Falsos Negativos (FRR):     {frr:.2f}%  (IA no detectada)")
    print("-" * 75)
    print(" Matriz de Confusión:")
    print(f"   [Verdaderos Humanos: {tn:4d} | Falsos IA (FP):    {fp:4d}]")
    print(f"   [Falsos Humanos (FN): {fn:4d} | Verdaderos IA (TP): {tp:4d}]")
    print("=" * 75 + "\n")

    if output_report:
        report_data = {
            "summary": {
                "total_samples": int(len(y_true)),
                "accuracy": float(acc),
                "precision": float(prec),
                "recall": float(rec),
                "f1_score": float(f1),
                "far_percentage": float(far),
                "frr_percentage": float(frr),
                "confusion_matrix": {
                    "tn": int(tn), "fp": int(fp),
                    "fn": int(fn), "tp": int(tp)
                }
            },
            "details": details
        }
        report_path = os.path.join(test_dir_abs, "benchmark_report.json")
        with open(report_path, "w", encoding="utf-8") as f:
            json.dump(report_data, f, indent=2, ensure_ascii=False)
        print(f"[OK] Reporte detallado guardado en '{report_path}'.")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Evaluador de Benchmark para GearShield")
    parser.add_argument("--test_dir", type=str, default="python GearShield/TESTING", help="Ruta a la carpeta de testing")
    parser.add_argument("--mode", type=str, default="sentence_vad", choices=["sentence_vad", "overlap", "sliding"], help="Modo VAD de inferencia")
    args = parser.parse_args()

    run_benchmark(test_dir=args.test_dir, mode=args.mode)
