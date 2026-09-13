"""
process_altur_dataset.py - Ingesta Automática de Carpetas Separadas (jsons/ y wavs/).
Pareado automático por nombre o por índice ordinal (1 a 282).
"""

import os
import json
import glob
import re
import librosa
import soundfile as sf

def natural_sort_key(s):
    """Ordena nombres numéricos de forma natural: 1, 2, 10 en lugar de 1, 10, 2."""
    return [int(text) if text.isdigit() else text.lower() for text in re.split(r'(\d+)', s)]

def process_altur_dataset(raw_dir="data/altur_raw", output_base="data", receptor_channel=1):
    print(f"\n======================================================================")
    print(f"   PROCESADOR DE DATASET ALTUR - PAREADO AUTOMÁTICO (JSONS & WAVS)")
    print(f"======================================================================\n")

    human_out = os.path.join(output_base, "human")
    ai_out = os.path.join(output_base, "ai")
    os.makedirs(human_out, exist_ok=True)
    os.makedirs(ai_out, exist_ok=True)

    # 1. Detectar si los archivos están en carpetas separadas 'jsons/' y 'wavs/'
    jsons_dir = os.path.join(raw_dir, "jsons")
    wavs_dir = os.path.join(raw_dir, "wavs")

    if not os.path.exists(jsons_dir):
        jsons_dir = raw_dir
    if not os.path.exists(wavs_dir):
        wavs_dir = raw_dir

    json_files = sorted(glob.glob(os.path.join(jsons_dir, "*.json")), key=natural_sort_key)
    wav_files = sorted(glob.glob(os.path.join(wavs_dir, "*.wav")) + glob.glob(os.path.join(wavs_dir, "*.mp3")), key=natural_sort_key)

    if not json_files or not wav_files:
        print(f"[!] No se encontraron archivos de audio o JSON.")
        print(f"💡 ESTRUCTURA SUGERIDA:")
        print(f"   Crea la carpeta 'data/altur_raw/' con dos subcarpetas:")
        print(f"     - data/altur_raw/jsons/  (Arrastra aquí tus 282 JSONs)")
        print(f"     - data/altur_raw/wavs/   (Arrastra aquí tus 282 WAVs)")
        return

    print(f"[INFO] Encontrados {len(json_files)} JSONs y {len(wav_files)} WAVs.")

    # 2. Estrategia de Pareado: Primero intentamos por nombre coincidente, si no, por posición ordinal (1 a 1)
    pairs = []
    wav_dict = {os.path.splitext(os.path.basename(w))[0]: w for w in wav_files}

    matched_by_name = True
    for j_path in json_files:
        bname = os.path.splitext(os.path.basename(j_path))[0]
        if bname in wav_dict:
            pairs.append((j_path, wav_dict[bname]))
        else:
            matched_by_name = False
            break

    if not matched_by_name or len(pairs) == 0:
        print(f"[INFO] Pareando archivos secuencialmente por orden ordinal (1º JSON con 1º WAV, etc.)...")
        pairs = list(zip(json_files, wav_files))

    print(f"[OK] Se formaron {len(pairs)} pares exitosos para procesar.\n")

    processed_calls = 0
    total_segments = 0

    for idx_pair, (json_path, wav_path) in enumerate(pairs):
        base_name = os.path.splitext(os.path.basename(wav_path))[0]

        try:
            with open(json_path, 'r', encoding='utf-8') as f:
                meta = json.load(f)

            # Determinar si la llamada/receptor es Humano o IA por metadatos o nombre
            is_ai = False
            label_str = str(meta.get('receptor_type', '') or meta.get('label', '') or meta.get('status', '') or meta.get('answering_machine', '')).lower()
            if 'bot' in label_str or 'ia' in label_str or 'machine' in label_str or 'voicemail' in label_str or meta.get('is_ai') is True or meta.get('is_bot') is True:
                is_ai = True
            elif 'ai' in base_name.lower() or 'bot' in base_name.lower():
                is_ai = True

            turns = meta.get('turns', [])
            if not turns:
                continue

            # Filtrar los turnos del receptor (channel 1 por defecto, o channel 0 fallback)
            receptor_turns = [t for t in turns if t.get('channel') == receptor_channel]
            if not receptor_turns:
                alt_channel = 0 if receptor_channel == 1 else 1
                receptor_turns = [t for t in turns if t.get('channel') == alt_channel]

            if not receptor_turns:
                continue

            y, sr = sf.read(wav_path, dtype='float32')
            if len(y.shape) > 1 and y.shape[1] >= 2:
                ch_idx = receptor_channel if receptor_channel < y.shape[1] else 0
                y = y[:, ch_idx]
            elif len(y.shape) > 1:
                y = y[:, 0]

            if sr != 16000:
                y = librosa.resample(y, orig_sr=sr, target_sr=16000)
                sr = 16000

            tag = "ai" if is_ai else "human"
            dest_folder = ai_out if is_ai else human_out

            call_segs = 0
            for t_idx, turn in enumerate(receptor_turns):
                start_s = turn.get('start', 0.0)
                end_s = turn.get('end', 0.0)
                duration = end_s - start_s

                if duration < 0.4:
                    continue

                start_sample = int(start_s * sr)
                end_sample = int(end_s * sr)
                chunk_y = y[start_sample:end_sample]

                if len(chunk_y) > 0:
                    out_name = f"altur_{tag}_{base_name}_t{t_idx:03d}.wav"
                    sf.write(os.path.join(dest_folder, out_name), chunk_y, sr)
                    call_segs += 1
                    total_segments += 1

            processed_calls += 1
            if (idx_pair + 1) % 50 == 0 or (idx_pair + 1) == len(pairs):
                print(f"   [+] Procesadas {idx_pair + 1}/{len(pairs)} llamadas Altur...")

        except Exception as e:
            print(f"   [!] Error procesando par {base_name}: {e}")

    print(f"\n======================================================================")
    print(f"[OK] Procesamiento Finalizado:")
    print(f"   - Llamadas emparejadas y procesadas: {processed_calls}/{len(pairs)}")
    print(f"   - Fragmentos del receptor extraídos: {total_segments}")
    print(f"======================================================================\n")

if __name__ == "__main__":
    process_altur_dataset()
