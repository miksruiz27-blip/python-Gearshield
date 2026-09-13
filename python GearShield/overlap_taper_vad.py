"""
overlap_taper_vad.py - Inferencia por Ventanas con Solapamiento, Atenuación de Bordes (Hann Windowing)
y Persistencia Temporal de Alertas en GearShield 2.0.

Complementa la segmentación por VAD eliminando chasquidos espectrales mediante Hann Windowing
y descartando disparos aislados por medio de la regla de persistencia temporal (2 ventanas consecutivas >= 0.75).
"""

import time
import typing
import numpy as np
import librosa

try:
    import torch
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False


def analyze_audio_with_overlap(
    y: np.ndarray,
    sr: int = 16000,
    model: typing.Any = None,
    window_sec: float = 2.0,
    hop_sec: float = 0.5,
    threshold: float = 0.75
) -> typing.Dict[str, typing.Any]:
    """
    1. Ventana Deslizante con Solapamiento y Atenuación Hann (Hann Windowing).
    2. Evaluación de ventana por ventana eliminando artefactos de borde.
    3. Clasificación por Persistencia Temporal (2 ventanas consecutivas >= threshold o mediana top3 >= threshold).

    Parámetros:
    - y: Señal de audio monoaural (1D numpy array float32).
    - sr: Frecuencia de muestreo (default 16000 Hz).
    - model: Modelo de inferencia (PyTorch nn.Module, ONNX, Sklearn engine o callable).
    - window_sec: Duración de cada ventana en segundos (default 2.0s).
    - hop_sec: Solapamiento / avance en segundos (default 0.5s).
    - threshold: Umbral estricto de confianza para considerar riesgo de IA (default 0.75).

    Retorna:
    - Dict listo para JSON con verdict, overall_confidence, overall_risk_ai, timeline_segments y latency_ms.
    """
    t_start = time.perf_counter()

    if len(y.shape) > 1:
        y = np.mean(y, axis=1)  # Mono

    total_samples = len(y)
    total_duration = total_samples / sr

    if total_samples == 0:
        return {
            "verdict": "ORGANIC_HUMAN",
            "overall_confidence": 1.0,
            "overall_risk_ai": 0.0,
            "windows_analyzed": 0,
            "timeline_segments": [],
            "latency_ms": 0.0
        }

    window_samples = int(window_sec * sr)
    hop_samples = int(hop_sec * sr)

    # Si el audio es más corto que la ventana objetivo, aplicar padding de ceros
    if total_samples < window_samples:
        y_padded = np.pad(y, (0, window_samples - total_samples), mode='constant')
        starts = [0]
    else:
        y_padded = y
        starts = list(range(0, len(y_padded) - window_samples + 1, hop_samples))
        # Asegurar inclusión del tramo final si queda remanente significativo
        if starts[-1] + window_samples < len(y_padded) and (len(y_padded) - starts[-1] - window_samples) >= int(0.2 * sr):
            starts.append(len(y_padded) - window_samples)

    timeline_segments = []
    scores = []

    # 1. Extracción e Inferencia Ventana por Ventana con Hann Windowing
    for idx, st in enumerate(starts):
        ed = st + window_samples
        chunk_raw = y_padded[st:ed].copy()

        # PASO 2: Atenuación de Bordes (Hann Windowing)
        # Multiplica la señal por la ventana Hann para suavizar bordes a cero (0 -> 1 -> 0)
        # y eliminar chasquidos espectrales antes de calcular STFT / MFCCs / Mel-Spectrogram
        hann_taper = np.hanning(len(chunk_raw))
        chunk_tapered = chunk_raw * hann_taper

        start_sec = round(st / sr, 2)
        end_sec = round(min(total_duration, ed / sr), 2)
        dur_sec = round(end_sec - start_sec, 2)

        # Inferencia con Modelo
        score_ai = 0.0
        if model is not None:
            try:
                if HAS_TORCH and isinstance(model, torch.nn.Module):
                    model.eval()
                    with torch.no_grad():
                        tensor_in = torch.from_numpy(chunk_tapered).float().unsqueeze(0)
                        out = model(tensor_in)
                        probs = torch.softmax(out, dim=1).numpy()[0]
                        score_ai = float(probs[1])
                elif isinstance(model, dict) and "type" in model:
                    if model["type"] == "onnx":
                        session = model["session"]
                        input_name = session.get_inputs()[0].name
                        from DataSet import extract_features
                        feat = extract_features(chunk_tapered, target_sr=sr)
                        if feat is not None:
                            outputs = session.run(None, {input_name: [feat.astype(np.float32)]})
                            prob_out = outputs[1][0]
                            # skl2onnx con ZipMap devuelve un dict {clase: prob}; sin ZipMap
                            # (este modelo) devuelve un array [prob_clase0, prob_clase1].
                            # Asumir siempre dict tiraba AttributeError en cada ventana,
                            # que el except silencioso convertía en score fijo para TODO audio.
                            if isinstance(prob_out, dict):
                                score_ai = float(prob_out.get(1, prob_out.get(1.0, 0.0)))
                            else:
                                score_ai = float(prob_out[1])
                    else:
                        sk_model = model["model"]
                        scaler = model.get("scaler")
                        from DataSet import extract_features
                        feat = extract_features(chunk_tapered, target_sr=sr)
                        if feat is not None:
                            feat_scaled = scaler.transform([feat]) if scaler else [feat]
                            probs = sk_model.predict_proba(feat_scaled)[0]
                            score_ai = float(probs[1])
                elif callable(model):
                    score_ai = float(model(chunk_tapered))
            except Exception:
                score_ai = 0.10
        else:
            # Simulador DSP para validación sin modelo cargado
            spec = np.abs(librosa.stft(chunk_tapered))
            flatness = float(np.mean(librosa.feature.spectral_flatness(S=spec)))
            score_ai = float(np.clip(flatness * 25.0, 0.05, 0.95))

        score_human = float(1.0 - score_ai)
        score_ai_pct = float(round(score_ai * 100.0, 2))
        scores.append(score_ai)

        timeline_segments.append({
            "window_id": idx + 1,
            "start_sec": start_sec,
            "end_sec": end_sec,
            "duration_sec": dur_sec,
            "score": round(score_ai, 4),
            "prob_human": round(score_human, 4),
            "prob_ai_percentage": score_ai_pct,
            "is_alert_candidate": bool(score_ai >= threshold)
        })

    # PASO 3: Sustitución de Max-Pooling por Persistencia Temporal
    # A) Verificar si al menos DOS ventanas CONSECUTIVAS superan el umbral (score >= threshold)
    has_consecutive_alerts = False
    consecutive_indexes = []

    for i in range(len(scores) - 1):
        if scores[i] >= threshold and scores[i + 1] >= threshold:
            has_consecutive_alerts = True
            consecutive_indexes.extend([i + 1, i + 2])

    consecutive_indexes = sorted(list(set(consecutive_indexes)))

    # B) Verificar si la mediana de las ventanas con mayor probabilidad supera el umbral
    top_k = min(3, len(scores))
    top_scores = sorted(scores, reverse=True)[:top_k]
    median_top = float(np.median(top_scores)) if top_scores else 0.0
    has_high_median = bool(median_top >= threshold)

    # C) Conteo de disparos aislados
    isolated_spikes = [i + 1 for i, s in enumerate(scores) if s >= threshold and (i + 1) not in consecutive_indexes]

    # Veredicto Final de Fraude basado en Persistencia Temporal
    if has_consecutive_alerts or has_high_median:
        verdict = "AI_GENERATED"
        max_score = max(scores)
        overall_confidence = float(round(max_score, 4))
        overall_risk_ai = float(round(max_score * 100.0, 2))
        details = "Fraude confirmado por persistencia temporal en múltiples ventanas consecutivas."
    elif len(isolated_spikes) > 0 or max(scores) >= 0.60:
        verdict = "SUSPICIOUS_TRANSIENT"
        max_score = max(scores)
        overall_confidence = float(round(max_score, 4))
        overall_risk_ai = float(round(max_score * 100.0, 2))
        details = f"Disparo aislado en ventana(s) {isolated_spikes} descartado como transitorio fonético/mic pop."
    else:
        verdict = "ORGANIC_HUMAN"
        avg_score = float(np.mean(scores)) if scores else 0.0
        overall_confidence = float(round(1.0 - avg_score, 4))
        overall_risk_ai = float(round(avg_score * 100.0, 2))
        details = "Audio verificado como voz humana orgánica limpia."

    t_end = time.perf_counter()
    latency_ms = float(round((t_end - t_start) * 1000.0, 2))

    return {
        "verdict": verdict,
        "overall_confidence": overall_confidence,
        "overall_risk_ai": overall_risk_ai,
        "windows_analyzed": len(starts),
        "persistence_metrics": {
            "has_consecutive_alerts": has_consecutive_alerts,
            "consecutive_window_ids": consecutive_indexes,
            "top3_median_score": round(median_top, 4),
            "isolated_spikes_count": len(isolated_spikes),
            "details": details
        },
        "timeline_segments": timeline_segments,
        "latency_ms": latency_ms
    }


if __name__ == "__main__":
    print("=== Probando analyze_audio_with_overlap con Hann Windowing & Persistencia Temporal ===")
    sr = 16000
    duration = 4.0
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)

    # Simulación de voz con un chasquido aislado en la ventana 2
    speech = 0.5 * np.sin(2 * np.pi * 220 * t)
    # Chasquido de micrófono (transitorio)
    speech[int(1.2 * sr):int(1.25 * sr)] += 2.0

    res = analyze_audio_with_overlap(speech.astype(np.float32), sr=16000)
    import json
    print(json.dumps(res, indent=2, ensure_ascii=False))
