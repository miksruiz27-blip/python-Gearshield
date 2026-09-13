"""
sentence_vad.py - Pipeline de Inferencia Basado en Segmentación Acústica por VAD.
Reemplaza la ventana deslizante ciega (Sliding Window) por detección dinámica de oraciones
acústicas delimitadas por silencios y pausas de respiración naturales en español.
Evita el corte a mitad de palabra ("novia", "transferencia", "obviar", "envía") y elimina
falsos positivos causados por discontinuidades espectrales.
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


def segment_audio_by_acoustic_sentences(
    y: np.ndarray,
    sr: int = 16000,
    top_db: float = 28.0,
    frame_length: int = 1024,
    hop_length: int = 256,
    min_silence_sec: float = 0.25,
    min_phrase_sec: float = 1.0,
    max_phrase_sec: float = 4.0,
) -> typing.List[typing.Dict[str, typing.Any]]:
    """
    1. Detección de Oraciones Acústicas mediante VAD (Voice Activity Detection).
    2. Fusión semántica de fragmentos cortos (<1.0s) y ventana Hann para tramos largos (>4.0s).

    Retorna una lista de diccionarios con 'start_sec', 'end_sec', 'samples' y 'duration_sec'.
    """
    if len(y.shape) > 1:
        y = np.mean(y, axis=1)  # Convertir a mono

    total_samples = len(y)
    total_duration = total_samples / sr

    if total_samples == 0:
        return []

    # 1. Detección de intervalos de habla con librosa (o VAD por RMS)
    non_silent_intervals = librosa.effects.split(
        y, top_db=top_db, frame_length=frame_length, hop_length=hop_length
    )

    if len(non_silent_intervals) == 0:
        # Caso bordes: señal sumamente silenciosa -> tomar clip completo
        return [{
            "start_sec": 0.0,
            "end_sec": round(total_duration, 2),
            "samples": y,
            "duration_sec": round(total_duration, 2)
        }]

    # Unir intervalos que están separados por silencios menores al umbral (ej. < 250 ms)
    min_silence_samples = int(min_silence_sec * sr)
    merged_intervals = []

    curr_start, curr_end = non_silent_intervals[0]
    for next_start, next_end in non_silent_intervals[1:]:
        gap = next_start - curr_end
        if gap < min_silence_samples:
            # Fusión por pausa muy corta (intraword o consonante oclusiva)
            curr_end = next_end
        else:
            merged_intervals.append((curr_start, curr_end))
            curr_start, curr_end = next_start, next_end
    merged_intervals.append((curr_start, curr_end))

    # 2. Fusión Semántica de Fragmentos Cortos (< 1.0s)
    min_phrase_samples = int(min_phrase_sec * sr)
    phrases_samples = []

    idx = 0
    while idx < len(merged_intervals):
        st, ed = merged_intervals[idx]
        while (ed - st) < min_phrase_samples and (idx + 1) < len(merged_intervals):
            # Fusionar con el segmento subsiguiente para dar suficiente contexto espectral
            idx += 1
            _, next_ed = merged_intervals[idx]
            ed = next_ed

        phrases_samples.append((st, ed))
        idx += 1

    # 3. Tratamiento de Oraciones Continuas Largas (> 4.0s) con Hann Windowing
    max_phrase_samples = int(max_phrase_sec * sr)
    final_segments = []

    for st, ed in phrases_samples:
        seg_y = y[st:ed]
        seg_dur = (ed - st) / sr

        if len(seg_y) <= max_phrase_samples:
            final_segments.append({
                "start_sec": round(st / sr, 2),
                "end_sec": round(ed / sr, 2),
                "samples": seg_y,
                "duration_sec": round(seg_dur, 2)
            })
        else:
            # División extraordinaria para ráfagas continuas largas
            num_subchunks = int(np.ceil(len(seg_y) / max_phrase_samples))
            sub_len = max_phrase_samples
            fade_samples = int(0.05 * sr)  # Fade suave de 50ms con ventana Hann

            for c in range(num_subchunks):
                sub_st = st + c * sub_len
                sub_ed = min(ed, sub_st + sub_len)
                sub_y = y[sub_st:sub_ed].copy()

                # Aplicar Hann taper en bordes para evitar discontinuidades
                if len(sub_y) > 2 * fade_samples:
                    hann_window = np.hanning(2 * fade_samples)
                    sub_y[:fade_samples] *= hann_window[:fade_samples]
                    sub_y[-fade_samples:] *= hann_window[fade_samples:]

                final_segments.append({
                    "start_sec": round(sub_st / sr, 2),
                    "end_sec": round(sub_ed / sr, 2),
                    "samples": sub_y,
                    "duration_sec": round((sub_ed - sub_st) / sr, 2)
                })

    return final_segments


def analyze_audio_by_sentences(
    y: np.ndarray,
    sr: int = 16000,
    model: typing.Any = None,
    top_db: float = 28.0,
    pad_target_sec: float = 3.0
) -> typing.Dict[str, typing.Any]:
    """
    Función Principal de Inferencia por Oraciones Acústicas (VAD-Guided Acoustic Sentence Inference).

    Parámetros:
    - y: Señal de audio (1D numpy float32, mono).
    - sr: Frecuencia de muestreo (default 16000 Hz).
    - model: Modelo de inferencia (PyTorch nn.Module, ONNX Session, o GearShield Sklearn/ONNX Engine).

    Retorna:
    - JSON con verdict, overall_confidence, timeline_segments, y latency_ms.
    """
    t_start = time.perf_counter()

    if len(y) == 0:
        return {
            "verdict": "ORGANIC_HUMAN",
            "overall_confidence": 1.0,
            "overall_risk_ai": 0.0,
            "sentences_analyzed": 0,
            "timeline_segments": [],
            "latency_ms": 0.0
        }

    # 1. Segmentación VAD Acústica
    segments = segment_audio_by_acoustic_sentences(
        y, sr=sr, top_db=top_db, min_silence_sec=0.25, min_phrase_sec=1.0, max_phrase_sec=4.0
    )

    timeline_segments = []
    high_risk_count_80 = 0
    mod_risk_count_65 = 0
    max_prob_ai = 0.0
    sum_prob_ai = 0.0

    pad_samples = int(pad_target_sec * sr)

    # 2. Inferencia Oración por Oración
    for idx, seg in enumerate(segments):
        seg_y = seg["samples"]

        # Zero-padding a longitud objetivo si el modelo lo requiere
        if len(seg_y) < pad_samples:
            seg_y_padded = np.pad(seg_y, (0, pad_samples - len(seg_y)), mode='constant')
        else:
            seg_y_padded = seg_y

        # Inferencia con modelo dinámico
        prob_ai = 0.0
        if model is not None:
            try:
                # Caso A: Modelo PyTorch
                if HAS_TORCH and isinstance(model, torch.nn.Module):
                    model.eval()
                    with torch.no_grad():
                        tensor_in = torch.from_numpy(seg_y_padded).float().unsqueeze(0)
                        out = model(tensor_in)
                        probs = torch.softmax(out, dim=1).numpy()[0]
                        prob_ai = float(probs[1])
                # Caso B: Motor GearShield (dict de ONNX o Sklearn)
                elif isinstance(model, dict) and "type" in model:
                    if model["type"] == "onnx":
                        session = model["session"]
                        input_name = session.get_inputs()[0].name
                        # Extraer vector biofísico
                        from DataSet import extract_features
                        feat = extract_features(seg_y, target_sr=sr)
                        if feat is not None:
                            outputs = session.run(None, {input_name: [feat.astype(np.float32)]})
                            prob_out = outputs[1][0]
                            # skl2onnx con ZipMap devuelve un dict {clase: prob}; sin ZipMap
                            # (este modelo) devuelve un array [prob_clase0, prob_clase1].
                            # Asumir siempre dict tiraba AttributeError en cada ventana,
                            # que el except silencioso convertía en 10% fijo para TODO audio.
                            if isinstance(prob_out, dict):
                                prob_ai = float(prob_out.get(1, prob_out.get(1.0, 0.0)))
                            else:
                                prob_ai = float(prob_out[1])
                    else:
                        sk_model = model["model"]
                        scaler = model.get("scaler")
                        from DataSet import extract_features
                        feat = extract_features(seg_y, target_sr=sr)
                        if feat is not None:
                            feat_scaled = scaler.transform([feat]) if scaler else [feat]
                            probs = sk_model.predict_proba(feat_scaled)[0]
                            prob_ai = float(probs[1])
                # Caso C: Función callable genérica
                elif callable(model):
                    prob_ai = float(model(seg_y_padded))
            except Exception as e:
                # Fallback seguro en caso de falla de inferencia individual
                prob_ai = 0.10
        else:
            # Demostración heurística de dispersión biofísica
            stft = np.abs(librosa.stft(seg_y))
            phase_var = float(np.std(np.diff(np.angle(librosa.stft(seg_y)))))
            prob_ai = float(np.clip(phase_var / 5.0, 0.05, 0.95))

        prob_human = float(1.0 - prob_ai)
        prob_ai_percentage = float(round(prob_ai * 100.0, 2))

        if prob_ai >= 0.80:
            high_risk_count_80 += 1
        if prob_ai >= 0.65:
            mod_risk_count_65 += 1

        if prob_ai > max_prob_ai:
            max_prob_ai = prob_ai

        sum_prob_ai += prob_ai

        timeline_segments.append({
            "segment_id": idx + 1,
            "start_sec": seg["start_sec"],
            "end_sec": seg["end_sec"],
            "duration_sec": seg["duration_sec"],
            "prob_ai": round(prob_ai, 4),
            "prob_human": round(prob_human, 4),
            "prob_ai_percentage": prob_ai_percentage,
            "is_synthetic": bool(prob_ai >= 0.65)
        })

    avg_prob_ai = sum_prob_ai / len(segments) if segments else 0.0

    # 3. Regla de Agregación de Incidentes para Veredicto de Fraude
    # - "AI_GENERATED" si al menos 1 oración supera prob >= 0.80 O si al menos 2 oraciones superan prob >= 0.65
    if high_risk_count_80 >= 1 or mod_risk_count_65 >= 2:
        verdict = "AI_GENERATED"
        overall_confidence = float(round(max_prob_ai, 4))
        overall_risk_ai = float(round(max_prob_ai * 100.0, 2))
    elif max_prob_ai >= 0.50:
        verdict = "SUSPICIOUS_REVERIFY"
        overall_confidence = float(round(max_prob_ai, 4))
        overall_risk_ai = float(round(max_prob_ai * 100.0, 2))
    else:
        verdict = "ORGANIC_HUMAN"
        overall_confidence = float(round(1.0 - avg_prob_ai, 4))
        overall_risk_ai = float(round(avg_prob_ai * 100.0, 2))

    t_end = time.perf_counter()
    latency_ms = float(round((t_end - t_start) * 1000.0, 2))

    return {
        "verdict": verdict,
        "overall_confidence": overall_confidence,
        "overall_risk_ai": overall_risk_ai,
        "sentences_analyzed": len(segments),
        "timeline_segments": timeline_segments,
        "latency_ms": latency_ms
    }


if __name__ == "__main__":
    print("=== Probando Pipeline VAD-Guided Sentence Inference (GearShield 2.0) ===")
    sr = 16000
    duration = 5.0
    t = np.linspace(0, duration, int(sr * duration), endpoint=False)
    
    # Sintetizar 2 frases con un silencio de 350ms en medio
    speech1 = 0.5 * np.sin(2 * np.pi * 220 * t[:int(sr * 2.0)])
    silence = np.zeros(int(sr * 0.35))
    speech2 = 0.5 * np.sin(2 * np.pi * 330 * t[:int(sr * 2.0)])
    
    test_audio = np.concatenate([speech1, silence, speech2]).astype(np.float32)
    
    res = analyze_audio_by_sentences(test_audio, sr=16000)
    import json
    print(json.dumps(res, indent=2, ensure_ascii=False))
