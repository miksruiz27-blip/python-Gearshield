"""
DataSet.py - Extracción de características de alta precisión y gestión de dataset para GearShield.
Extrae 170 dimensiones acústicas clave (MFCCs, Deltas, Delta-Deltas, Chroma, Espectro, Contraste, Planitud, ZCR, RMS)
y soporta la técnica de Ventana Deslizante (Sliding Window / Chunking) tanto para entrenamiento como para inferencia.
"""

import os
import glob
import numpy as np
import librosa
import soundfile as sf

def extract_features(audio_path_or_y, target_sr=16000, n_mfcc=20):
    """
    Extrae un vector denso de 170 características acústicas a partir de un archivo de audio o señal numpy.
    """
    try:
        if isinstance(audio_path_or_y, str):
            try:
                y, sr = sf.read(audio_path_or_y, dtype='float32')
                if len(y.shape) > 1:
                    y = np.mean(y, axis=1)  # Mono
                if sr != target_sr:
                    y = librosa.resample(y, orig_sr=sr, target_sr=target_sr)
                    sr = target_sr
            except Exception:
                y, sr = librosa.load(audio_path_or_y, sr=target_sr, mono=True, duration=15.0)
        else:
            y = audio_path_or_y
            if hasattr(y, 'shape') and len(y.shape) > 1:
                y = y[:, 0] if y.shape[1] >= 2 else y[0, :]
            sr = target_sr

        if len(y) < int(sr * 0.5):  # Menos de 500 ms (requerido para librosa.feature.delta width=9)
            y = np.pad(y, (0, int(sr * 0.5) - len(y)))

        features = []

        # 1. MFCCs (Media y Desviación Estándar) -> 40 características
        mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=n_mfcc)
        features.extend(np.mean(mfcc, axis=1))
        features.extend(np.std(mfcc, axis=1))

        # 2. Delta MFCC (Velocidad de cambio articular) -> 40 características
        mfcc_delta = librosa.feature.delta(mfcc)
        features.extend(np.mean(mfcc_delta, axis=1))
        features.extend(np.std(mfcc_delta, axis=1))

        # 3. Delta-Delta MFCC (Aceleración de cambio vocal) -> 40 características
        mfcc_delta2 = librosa.feature.delta(mfcc, order=2)
        features.extend(np.mean(mfcc_delta2, axis=1))
        features.extend(np.std(mfcc_delta2, axis=1))

        # 4. Spectral Centroid (Centro de masa del espectro) -> 2 características
        centroid = librosa.feature.spectral_centroid(y=y, sr=sr)
        features.append(np.mean(centroid))
        features.append(np.std(centroid))

        # 5. Spectral Rolloff (Frecuencia límite espectral) -> 2 características
        rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr)
        features.append(np.mean(rolloff))
        features.append(np.std(rolloff))

        # 6. Zero Crossing Rate (Frecuencia de cruce por cero) -> 2 características
        zcr = librosa.feature.zero_crossing_rate(y)
        features.append(np.mean(zcr))
        features.append(np.std(zcr))

        # 7. RMS Energy (Energía cuadrática media) -> 2 características
        rms = librosa.feature.rms(y=y)
        features.append(np.mean(rms))
        features.append(np.std(rms))

        # 8. Spectral Bandwidth (Ancho de banda espectral) -> 2 características
        bandwidth = librosa.feature.spectral_bandwidth(y=y, sr=sr)
        features.append(np.mean(bandwidth))
        features.append(np.std(bandwidth))

        # 9. Chroma STFT (Estructura armónica y formantes) -> 24 características
        chroma = librosa.feature.chroma_stft(y=y, sr=sr)
        features.extend(np.mean(chroma, axis=1))
        features.extend(np.std(chroma, axis=1))

        # 10. Spectral Contrast (Diferencia pico-valle por sub-bandas) -> 14 características
        contrast = librosa.feature.spectral_contrast(y=y, sr=sr)
        features.extend(np.mean(contrast, axis=1))
        features.extend(np.std(contrast, axis=1))

        # 11. Spectral Flatness (Planitud espectral / tono vs ruido) -> 2 características
        flatness = librosa.feature.spectral_flatness(y=y)
        features.append(np.mean(flatness))
        features.append(np.std(flatness))

        # --- CARACTERÍSTICAS BIOFÍSICAS Y FASE ESPECTRAL (GearShield 2.0: 50 dimensiones adicionales) ---
        # 12. Jitter & Instabilidad de Tono Fundamental (10 características)
        try:
            y_sub = librosa.resample(y, orig_sr=sr, target_sr=8000)
            pitch = librosa.yin(y_sub, fmin=65, fmax=500, sr=8000, frame_length=512, hop_length=256)
            valid_p = pitch[(pitch > 65) & (pitch < 500)]
            if len(valid_p) > 2:
                p_mean, p_std = float(np.mean(valid_p)), float(np.std(valid_p))
                p_max, p_min = float(np.max(valid_p)), float(np.min(valid_p))
                p_diff = np.abs(np.diff(valid_p))
                j_local = float(np.mean(p_diff) / (p_mean + 1e-6))
                j_rap = float(np.mean(np.abs(valid_p[2:] - 2*valid_p[1:-1] + valid_p[:-2])) / (p_mean + 1e-6))
                p_d_mean, p_d_std = float(np.mean(p_diff)), float(np.std(p_diff))
                v_ratio = float(len(valid_p) / len(pitch))
                # PPQ5 (Period Perturbation Quotient a 5 puntos): compara cada
                # periodo de pitch contra el promedio de sus 4 vecinos más
                # cercanos. Complementa a jitter local/RAP con una ventana más
                # ancha, estándar en análisis clínico de voz (Praat, PRAAT-like).
                if len(valid_p) > 4:
                    smooth5 = np.convolve(valid_p, np.ones(5) / 5.0, mode='valid')
                    ppq5 = float(np.mean(np.abs(valid_p[2:-2] - smooth5)) / (p_mean + 1e-6))
                else:
                    ppq5 = 0.0
            else:
                p_mean=p_std=p_max=p_min=j_local=j_rap=p_d_mean=p_d_std=v_ratio=0.0
                ppq5 = 0.0
        except Exception:
            p_mean=p_std=p_max=p_min=j_local=j_rap=p_d_mean=p_d_std=v_ratio=0.0
            ppq5 = 0.0
        features.extend([p_mean, p_std, p_max, p_min, j_local, j_rap, p_d_mean, p_d_std, v_ratio, ppq5])

        # 13. Shimmer & Perturbación Micro-Amplitud de Cuerdas Vocales (10 características)
        rms_arr = rms[0]
        rms_mean = float(np.mean(rms_arr) + 1e-6)
        rms_diff = np.abs(np.diff(rms_arr))
        s_local = float(np.mean(rms_diff) / rms_mean)
        s_db = float(20 * np.log10(s_local + 1.0))
        s_apq3 = float(np.mean(np.abs(rms_arr[2:] - 2*rms_arr[1:-1] + rms_arr[:-2])) / rms_mean) if len(rms_arr)>2 else 0.0
        s_apq5 = float(np.mean(np.abs(rms_arr[4:] - 2*rms_arr[2:-2] + rms_arr[:-4])) / rms_mean) if len(rms_arr)>4 else 0.0
        rms_std = float(np.std(rms_arr))
        rms_skew = float(np.mean((rms_arr - np.mean(rms_arr))**3) / (rms_std**3 + 1e-6))
        peak_rms = float(np.max(np.abs(y)) / rms_mean)
        dyn_range = float(20 * np.log10(np.max(np.abs(y)) / (np.min(np.abs(y)[np.abs(y)>1e-5]) + 1e-6) + 1.0))
        # Curtosis de energía: qué tan "pico" es la distribución de RMS entre
        # frames. Un motor TTS suele producir una envolvente de energía más
        # uniforme (curtosis baja) que la dinámica irregular del habla humana.
        rms_kurtosis = float(np.mean((rms_arr - np.mean(rms_arr)) ** 4) / (rms_std ** 4 + 1e-6)) if rms_std > 0 else 0.0
        # Proporción de frames cerca del piso de silencio digital. El habla
        # humana rara vez cae en silencio absoluto (ruido de sala/línea);
        # muchos TTS sí generan silencio "perfecto" entre palabras.
        floor_ratio = float(np.mean(rms_arr < (0.02 * np.max(rms_arr) + 1e-9))) if len(rms_arr) > 0 else 0.0
        features.extend([s_local, s_db, s_apq3, s_apq5, rms_std, rms_skew, peak_rms, dyn_range, rms_kurtosis, floor_ratio])

        # 14. Relación Armónico a Ruido (HNR) y Energía Glótica (10 características)
        stft = librosa.stft(y)
        mag = np.abs(stft)
        # Bandas como arrays (no colapsadas a escalar todavía): antes `low_e`/
        # `high_e` ya eran floats aquí y std(low_e)/std(high_e) más abajo
        # eran std() de un escalar -> siempre 0.0 en TODAS las muestras.
        low_band = mag[:50, :]
        high_band = mag[50:, :]
        low_e = float(np.mean(low_band))
        high_e = float(np.mean(high_band))
        hnr_proxy = float(10 * np.log10((low_e + 1e-9) / (high_e + 1e-9)))
        h_ratio = float(low_e / (low_e + high_e + 1e-9))
        # Flujo espectral (cambio frame-a-frame del espectro, media rectificada):
        # el habla humana varía de forma más abrupta e irregular; un TTS suave
        # tiende a transiciones más lineales/predecibles.
        flux = np.diff(mag, axis=1)
        flux_pos = np.clip(flux, 0.0, None)
        flux_mean = float(np.mean(flux_pos))
        flux_std = float(np.std(flux_pos))
        # Entropía espectral (Shannon) del espectro de potencia normalizado por
        # frame: mide qué tan "ruidoso" vs. tonal-perfecto es el espectro.
        power = mag ** 2
        power_norm = power / (np.sum(power, axis=0, keepdims=True) + 1e-12)
        spec_entropy = -np.sum(power_norm * np.log2(power_norm + 1e-12), axis=0)
        spec_entropy_mean = float(np.mean(spec_entropy))
        spec_entropy_std = float(np.std(spec_entropy))
        features.extend([
            hnr_proxy, h_ratio, low_e, float(np.std(low_band)), high_e, float(np.std(high_band)),
            flux_mean, flux_std, spec_entropy_mean, spec_entropy_std,
        ])

        # 15. Coherencia de Fase Espectral y Frecuencia Instantánea (20 características)
        phase = np.angle(stft)
        inst_freq = np.diff(np.unwrap(phase, axis=1), axis=1)
        group_delay = np.diff(np.unwrap(phase, axis=0), axis=0)
        bands = np.array_split(inst_freq, 8, axis=0)
        for b in bands:
            features.append(float(np.mean(b)))
            features.append(float(np.std(b)))
        gd_bands = np.array_split(group_delay, 4, axis=0)
        for g in gd_bands:
            features.append(float(np.std(g)))

        arr = np.nan_to_num(np.array(features, dtype=np.float32), nan=0.0, posinf=0.0, neginf=0.0)
        return arr
    except Exception as e:
        print(f"[ERROR] Error procesando audio: {e}")
        return None

def extract_features_sliding_window(audio_path, window_sec=3.0, hop_sec=1.5, target_sr=16000):
    """
    Estrategia de Ventana Deslizante (Sliding Window / Chunking).
    Segmenta el audio en ventanas de `window_sec` segundos con avance de `hop_sec` segundos.
    """
    try:
        if isinstance(audio_path, str):
            try:
                y, sr = sf.read(audio_path, dtype='float32')
                if len(y.shape) > 1:
                    y = np.mean(y, axis=1)
                if sr != target_sr:
                    y = librosa.resample(y, orig_sr=sr, target_sr=target_sr)
                    sr = target_sr
            except Exception:
                y, sr = librosa.load(audio_path, sr=target_sr, mono=True, duration=9.0)
        if len(y) > int(sr * 9.0):
            y = y[: int(sr * 9.0)]

        total_duration = len(y) / sr
        window_samples = int(window_sec * sr)
        hop_samples = int(hop_sec * sr)

        chunks = []

        if len(y) <= window_samples:
            feat = extract_features(y, target_sr=sr)
            if feat is not None:
                chunks.append({
                    "start_sec": 0.0,
                    "end_sec": total_duration,
                    "features": feat
                })
            return chunks

        start = 0
        while start + window_samples <= len(y):
            chunk_y = y[start : start + window_samples]
            start_sec = start / sr
            end_sec = (start + window_samples) / sr
            
            feat = extract_features(chunk_y, target_sr=sr)
            if feat is not None:
                chunks.append({
                    "start_sec": round(start_sec, 2),
                    "end_sec": round(end_sec, 2),
                    "features": feat
                })
            
            start += hop_samples

        if start < len(y) and (len(y) - start) >= int(0.5 * sr):
            chunk_y = y[start:]
            start_sec = start / sr
            end_sec = len(y) / sr
            feat = extract_features(chunk_y, target_sr=sr)
            if feat is not None:
                chunks.append({
                    "start_sec": round(start_sec, 2),
                    "end_sec": round(end_sec, 2),
                    "features": feat
                })

        return chunks

    except Exception as e:
        print(f"[ERROR] Error en ventana deslizante para {audio_path}: {e}")
        return []

def _process_single_file(args):
    filepath, label, group_id, window_sec, hop_sec = args
    results = []
    try:
        chunks = extract_features_sliding_window(filepath, window_sec=window_sec, hop_sec=hop_sec)
        for c in chunks:
            results.append((c["features"], label, group_id))
    except Exception:
        pass
    return results

def load_dataset_from_directory(data_dir="data", window_sec=3.0, hop_sec=1.5, max_human_base_files=500):
    """
    Carga todos los archivos de audio en data_dir/human_clean_3s (o human), human_augmented, ai y ai_augmented.
    Procesa las características en paralelo (Multiprocessing) para máxima velocidad.
    Segmenta automáticamente audios largos en sub-muestras de 3 segundos para el entrenamiento.
    """
    cache_path = os.path.join(data_dir, "dataset_220_cache_v2.joblib")
    if os.path.exists(cache_path):
        try:
            print(f"[INFO] Cargando dataset precargado desde cache '{cache_path}'...")
            cached_data = joblib.load(cache_path)
            print(f"[OK] Cache cargado: {cached_data['X'].shape[0]} muestras, {cached_data['X'].shape[1]} características, {len(set(cached_data['groups']))} archivos fuente.")
            return cached_data["X"], cached_data["y"], cached_data["groups"]
        except Exception:
            pass

    import concurrent.futures

    X, y, groups = [], [], []
    audio_extensions = ["*.wav", "*.mp3", "*.flac", "*.ogg"]
    human_clean_dir = os.path.join(data_dir, "human_clean_3s")
    human_folder_name = "human_clean_3s" if os.path.exists(human_clean_dir) else "human"
    categories = [(human_folder_name, 0), ("human_augmented", 0), ("ai", 1), ("ai_augmented", 1)]
    AUG_SUFFIXES = ("_telephony", "_gsm", "_opus", "_noisy", "_pitch")

    def base_group_key(filepath):
        name = os.path.splitext(os.path.basename(filepath))[0]
        for suffix in AUG_SUFFIXES:
            if name.endswith(suffix):
                return name[: -len(suffix)]
        return name

    def _select_base_keys(folder_path, cap):
        """Selecciona hasta `cap` claves base únicas a partir de los propios
        archivos de `folder_path` (no de otra carpeta)."""
        files = []
        if os.path.exists(folder_path):
            for ext in audio_extensions:
                files.extend(glob.glob(os.path.join(folder_path, ext)))
        keys = set()
        for f in files:
            if len(keys) >= cap:
                break
            keys.add(base_group_key(f))
        return keys

    # Selección balanceada de claves de grupo, calculada de forma INDEPENDIENTE
    # por carpeta (antes se calculaba solo desde `human_clean_3s`/`human` y
    # ese mismo set se reusaba también para filtrar `human_augmented` por
    # coincidencia de substring "human" en el nombre de carpeta).
    #
    # Eso rompía en silencio la carpeta `human_augmented`: sus archivos vienen
    # del pipeline de la llamada de Altur (`altur_human_call_<id>_t###_<aug>`),
    # una fuente distinta a `human_clean_3s` (`hclean_####_##`), así que sus
    # claves base NUNCA coincidían con `selected_human_base_keys` -> los
    # 26,535 archivos de `human_augmented` (voz humana con condiciones
    # realistas: teléfono, GSM, ruido, compresión) quedaban excluidos de TODO
    # entrenamiento pasado, mientras que `ai_augmented` sí se incluía siempre
    # (`ai_sample_01` + sufijo SÍ comparte clave con `ai_sample_01.wav`). El
    # modelo nunca vio voz humana degradada por códec/ruido, solo voz IA en
    # esas condiciones -> aprendía a asociar compresión/ruido con "IA".
    selected_human_base_keys = _select_base_keys(os.path.join(data_dir, human_folder_name), max_human_base_files)
    selected_human_augmented_base_keys = _select_base_keys(os.path.join(data_dir, "human_augmented"), max_human_base_files)
    selected_ai_base_keys = _select_base_keys(os.path.join(data_dir, "ai"), max_human_base_files)

    category_key_sets = {
        human_folder_name: selected_human_base_keys,
        "human_augmented": selected_human_augmented_base_keys,
        "ai": selected_ai_base_keys,
        "ai_augmented": selected_ai_base_keys,  # ai_augmented SÍ comparte claves base con ai
    }

    group_key_to_id = {}
    tasks = []

    for category_folder, label in categories:
        folder_path = os.path.join(data_dir, category_folder)
        if not os.path.exists(folder_path):
            continue

        files = []
        for ext in audio_extensions:
            files.extend(glob.glob(os.path.join(folder_path, ext)))

        # Filtrar por la selección balanceada propia de ESTA carpeta.
        allowed_keys = category_key_sets.get(category_folder)
        if allowed_keys:
            files = [f for f in files if base_group_key(f) in allowed_keys]

        print(f"[INFO] Preparando {len(files)} archivos desde '{folder_path}' (Etiqueta {label} - {category_folder.upper()})...", flush=True)

        for filepath in files:
            key = base_group_key(filepath)
            if key not in group_key_to_id:
                group_key_to_id[key] = len(group_key_to_id)
            group_id = group_key_to_id[key]
            tasks.append((filepath, label, group_id, window_sec, hop_sec))

    # El código decía "en paralelo usando Multiprocessing" pero nunca usaba
    # el `concurrent.futures` importado arriba: el bucle era secuencial.
    # Con ProcessPoolExecutor real se usan todos los núcleos disponibles.
    max_workers = max(1, (os.cpu_count() or 4) - 1)
    print(f"[INFO] Procesando {len(tasks)} archivos de audio en paralelo usando Multiprocessing ({max_workers} procesos)...", flush=True)

    total_chunks = 0
    if tasks:
        with concurrent.futures.ProcessPoolExecutor(max_workers=max_workers) as executor:
            for idx, res_list in enumerate(executor.map(_process_single_file, tasks, chunksize=4)):
                for feat, label, group_id in res_list:
                    X.append(feat)
                    y.append(label)
                    groups.append(group_id)
                    total_chunks += 1
                if (idx + 1) % 200 == 0:
                    print(f"   ... {idx + 1}/{len(tasks)} archivos procesados, {total_chunks} fragmentos extraídos", flush=True)

    print(f"[OK] Extracción finalizada. Total fragmentos: {total_chunks}.", flush=True)

    if len(X) == 0:
        print("[WARN] No se encontraron archivos de audio válidos en el directorio especificado.")
        return np.array([]), np.array([]), np.array([])

    X_arr, y_arr, groups_arr = np.array(X, dtype=np.float32), np.array(y, dtype=np.int64), np.array(groups, dtype=np.int64)
    try:
        joblib.dump({"X": X_arr, "y": y_arr, "groups": groups_arr}, cache_path)
        print(f"[OK] Dataset guardado en cache '{cache_path}'.")
    except Exception:
        pass

    return X_arr, y_arr, groups_arr

def create_dummy_dataset(output_dir="data", samples_per_class=15, sr=16000, duration=3.0):
    """
    Genera un dataset sintético de demostración.
    """
    print("[INFO] Generando dataset sintético de prueba...")
    human_dir = os.path.join(output_dir, "human")
    ai_dir = os.path.join(output_dir, "ai")

    os.makedirs(human_dir, exist_ok=True)
    os.makedirs(ai_dir, exist_ok=True)

    t = np.linspace(0, duration, int(sr * duration), endpoint=False)

    for i in range(samples_per_class):
        f0 = 120.0 + np.random.uniform(-20, 20)
        signal = 0.6 * np.sin(2 * np.pi * f0 * t) + 0.3 * np.sin(2 * np.pi * (2 * f0) * t)
        envelope = 0.5 + 0.5 * np.sin(2 * np.pi * 3 * t)
        noise = np.random.normal(0, 0.02, len(t))
        human_audio = (signal * envelope + noise).astype(np.float32)
        
        filepath = os.path.join(human_dir, f"human_sample_{i+1:02d}.wav")
        sf.write(filepath, human_audio, sr)

    for i in range(samples_per_class):
        f0 = 220.0 + np.random.uniform(-10, 10)
        signal = 0.7 * np.sin(2 * np.pi * f0 * t) + 0.4 * np.sin(2 * np.pi * 7500 * t)
        envelope = np.ones_like(t) * 0.8
        ai_audio = (signal * envelope).astype(np.float32)
        
        filepath = os.path.join(ai_dir, f"ai_sample_{i+1:02d}.wav")
        sf.write(filepath, ai_audio, sr)

if __name__ == "__main__":
    print("=== Probando Extracción Avanzada de 170 Características en DataSet.py ===")
    data_path = "data"
    X, y, groups = load_dataset_from_directory(data_path)
    print(f"[OK] Muestras extraídas X: {X.shape}")
    print(f"[OK] Etiquetas y: {y.shape}")
    print(f"[OK] Archivos fuente (groups): {len(set(groups))}")
