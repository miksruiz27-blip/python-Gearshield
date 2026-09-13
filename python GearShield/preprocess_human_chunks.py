"""
preprocess_human_chunks.py - Pre-procesador y Estandarizador de Chunks de Voz Humana.
Convierte todos los archivos de audio en data/human a fragmentos limpios de exactamente 3.0 segundos
en data/human_clean_3s/ para acelerar la extracción y garantizar la máxima cobertura fonética.
"""

import os
import glob
import numpy as np
import soundfile as sf
import librosa

INPUT_HUMAN_DIR = os.path.join("data", "human")
OUTPUT_CLEAN_DIR = os.path.join("data", "human_clean_3s")

def preprocess_and_segment_human_audio(target_sr=16000, chunk_duration=3.0, max_files_to_process=600):
    """
    Lee archivos de audio desde `data/human`, recorta en clips de 3.0 segundos
    filtrando silencios y guarda en `data/human_clean_3s`.
    """
    os.makedirs(OUTPUT_CLEAN_DIR, exist_ok=True)
    extensions = ["*.wav", "*.mp3", "*.flac", "*.ogg"]
    audio_files = []
    for ext in extensions:
        audio_files.extend(glob.glob(os.path.join(INPUT_HUMAN_DIR, ext)))

    print(f"=======================================================================", flush=True)
    print(f"  PRE-PROCESADOR DE AUDIOS HUMANOS GEARSHIELD 2.0", flush=True)
    print(f"  Encontrados {len(audio_files)} archivos de audio en '{INPUT_HUMAN_DIR}'.", flush=True)
    print(f"=======================================================================", flush=True)

    chunk_samples = int(target_sr * chunk_duration)
    saved_chunks_count = 0
    processed_files_count = 0

    for filepath in audio_files:
        if processed_files_count >= max_files_to_process:
            break

        base_name = os.path.splitext(os.path.basename(filepath))[0]
        # Omitir archivos temporales de descarga
        if base_name.startswith("_temp"):
            continue

        try:
            # Cargar los primeros 15 segundos max por archivo
            y, sr = librosa.load(filepath, sr=target_sr, mono=True, duration=15.0)
            if len(y) < int(target_sr * 0.3): # Omitir audios extremadamente cortos
                continue

            processed_files_count += 1
            start = 0
            file_chunk_idx = 0

            # Si es más corto que 3s pero tiene voz limpia, hacer pad
            if len(y) < chunk_samples:
                if np.max(np.abs(y)) > 0.015:
                    y_padded = np.pad(y, (0, chunk_samples - len(y)))
                    out_filename = f"hclean_{processed_files_count:04d}_{file_chunk_idx:02d}.wav"
                    sf.write(os.path.join(OUTPUT_CLEAN_DIR, out_filename), y_padded, target_sr)
                    saved_chunks_count += 1
            else:
                while start + chunk_samples <= len(y):
                    chunk_y = y[start : start + chunk_samples]
                    # Filtrar silencios
                    if np.max(np.abs(chunk_y)) > 0.015 and np.std(chunk_y) > 0.005:
                        out_filename = f"hclean_{processed_files_count:04d}_{file_chunk_idx:02d}.wav"
                        sf.write(os.path.join(OUTPUT_CLEAN_DIR, out_filename), chunk_y, target_sr)
                        saved_chunks_count += 1
                        file_chunk_idx += 1
                    start += chunk_samples

            if processed_files_count % 50 == 0 or processed_files_count == len(audio_files):
                print(f"   [+] Procesados {processed_files_count} archivos base. Clips limpios generados: {saved_chunks_count}...", flush=True)

        except Exception:
            pass

    print(f"\n[ÉXITO] Pre-procesamiento completado. Total de clips limpios de 3.0s en '{OUTPUT_CLEAN_DIR}': {saved_chunks_count}", flush=True)
    return saved_chunks_count

if __name__ == "__main__":
    preprocess_and_segment_human_audio()
