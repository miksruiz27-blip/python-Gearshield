"""
fetch_human_banking_dataset.py - Recolector Automático de Voces Humanas en Español.
Descarga y procesa audios de locutores humanos en español desde LibriVox y Wikimedia Commons,
segmentándolos en clips de 3.0 segundos para el motor GearShield.
"""

import os
import glob
import time
import requests
import numpy as np
import soundfile as sf
import librosa

HUMAN_OUTPUT_DIR = os.path.join("data", "human")

def fetch_librivox_spanish_samples(target_files=50, target_sr=16000, chunk_duration=3.0):
    """
    Descarga audiolibros en español de dominio público desde la API de LibriVox
    y los corta en fragmentos limpios de `chunk_duration` segundos.
    """
    os.makedirs(HUMAN_OUTPUT_DIR, exist_ok=True)
    print(f"\n[INFO] Consultando API de LibriVox para audiolibros en español...", flush=True)

    api_url = "https://librivox.org/api/feed/audiobooks/?language=Spanish&format=json"
    try:
        resp = requests.get(api_url, timeout=15)
        if resp.status_code != 200:
            print(f"[WARN] Error al consultar LibriVox: Status {resp.status_code}")
            return 0

        books = resp.json().get("books", [])
        print(f"[OK] Se encontraron {len(books)} libros en español disponibles.", flush=True)

        collected_count = 0
        chunk_samples = int(target_sr * chunk_duration)

        for book in books:
            if collected_count >= target_files:
                break

            book_title = book.get("title", "book")
            zip_url = book.get("url_zip_file")
            if not zip_url:
                continue

            archive_item_id = zip_url.split("/")[-1].replace("_librivox.zip", "").replace(".zip", "")
            if not archive_item_id:
                continue

            meta_url = f"https://archive.org/metadata/{archive_item_id}"
            try:
                meta_resp = requests.get(meta_url, timeout=10)
                if meta_resp.status_code != 200:
                    continue

                files_list = meta_resp.json().get("files", [])
                mp3_files = [f for f in files_list if f.get("name", "").endswith(".mp3")]

                if not mp3_files:
                    continue

                mp3_name = mp3_files[0]["name"]
                download_url = f"https://archive.org/download/{archive_item_id}/{mp3_name}"

                print(f" -> Descargando muestra humana desde LibriVox: '{book_title[:30]}...' ({mp3_name})...", flush=True)
                audio_resp = requests.get(download_url, timeout=30, stream=True)
                if audio_resp.status_code == 200:
                    temp_mp3 = os.path.join(HUMAN_OUTPUT_DIR, "_temp_download.mp3")
                    with open(temp_mp3, "wb") as f:
                        for chunk in audio_resp.iter_content(chunk_size=65536):
                            f.write(chunk)

                    try:
                        # Cargar los primeros 90s para extraer fragmentos limpios
                        y, sr = librosa.load(temp_mp3, sr=target_sr, mono=True, duration=90.0)
                        if os.path.exists(temp_mp3):
                            os.remove(temp_mp3)

                        start = 0
                        while start + chunk_samples <= len(y) and collected_count < target_files:
                            chunk_y = y[start : start + chunk_samples]
                            if np.max(np.abs(chunk_y)) > 0.02:
                                out_filename = f"human_librivox_{collected_count+1:03d}.wav"
                                out_path = os.path.join(HUMAN_OUTPUT_DIR, out_filename)
                                sf.write(out_path, chunk_y, target_sr)
                                collected_count += 1
                            start += chunk_samples
                    except Exception as e:
                        print(f"    [!] Error procesando audio descargado: {e}", flush=True)
                        if os.path.exists(temp_mp3):
                            os.remove(temp_mp3)

            except Exception as e:
                print(f"    [!] Error obteniendo metadata del libro: {e}", flush=True)

        print(f"[OK] Finalizada extracción de LibriVox: {collected_count} muestras guardadas en '{HUMAN_OUTPUT_DIR}'.", flush=True)
        return collected_count

    except Exception as e:
        print(f"[ERROR] Error al consultar API LibriVox: {e}", flush=True)
        return 0

def fetch_wikimedia_spanish_samples(target_files=30, target_sr=16000, chunk_duration=3.0):
    """
    Descarga audios de pronunciación humana en español desde Wikimedia Commons.
    """
    os.makedirs(HUMAN_OUTPUT_DIR, exist_ok=True)
    print(f"\n[INFO] Consultando API de Wikimedia Commons para audios en español...", flush=True)

    wiki_url = "https://commons.wikimedia.org/w/api.php?action=query&list=categorymembers&cmtitle=Category:Spanish_pronunciation&cmlimit=100&format=json"
    headers = {"User-Agent": "GearShieldAudioCollector/2.0 (antigravity@gemini.ai)"}

    try:
        resp = requests.get(wiki_url, headers=headers, timeout=15)
        if resp.status_code != 200:
            return 0

        members = resp.json().get("query", {}).get("categorymembers", [])
        ogg_file_titles = [m["title"] for m in members if m["title"].endswith(".ogg") or m["title"].endswith(".wav")]

        print(f"[OK] Se encontraron {len(ogg_file_titles)} archivos de voz en Wikimedia Commons.", flush=True)

        collected_count = 0
        chunk_samples = int(target_sr * chunk_duration)

        for title in ogg_file_titles:
            if collected_count >= target_files:
                break

            file_meta_url = f"https://commons.wikimedia.org/w/api.php?action=query&titles={title}&prop=imageinfo&iiprop=url&format=json"
            try:
                meta_resp = requests.get(file_meta_url, headers=headers, timeout=10)
                pages = meta_resp.json().get("query", {}).get("pages", {})
                imageinfo = None
                for p_id in pages:
                    if "imageinfo" in pages[p_id]:
                        imageinfo = pages[p_id]["imageinfo"][0]
                        break

                if not imageinfo or "url" not in imageinfo:
                    continue

                audio_url = imageinfo["url"]
                audio_resp = requests.get(audio_url, headers=headers, timeout=15)

                if audio_resp.status_code == 200:
                    ext = ".ogg" if title.endswith(".ogg") else ".wav"
                    temp_file = os.path.join(HUMAN_OUTPUT_DIR, f"_temp_wiki{ext}")
                    with open(temp_file, "wb") as f:
                        f.write(audio_resp.content)

                    try:
                        y, sr = librosa.load(temp_file, sr=target_sr, mono=True)
                        if os.path.exists(temp_file):
                            os.remove(temp_file)

                        if len(y) < chunk_samples:
                            if np.max(np.abs(y)) > 0.01:
                                y = np.pad(y, (0, chunk_samples - len(y)))
                                out_filename = f"human_wiki_{collected_count+1:03d}.wav"
                                sf.write(os.path.join(HUMAN_OUTPUT_DIR, out_filename), y, target_sr)
                                collected_count += 1
                        else:
                            start = 0
                            while start + chunk_samples <= len(y) and collected_count < target_files:
                                chunk_y = y[start : start + chunk_samples]
                                if np.max(np.abs(chunk_y)) > 0.01:
                                    out_filename = f"human_wiki_{collected_count+1:03d}.wav"
                                    sf.write(os.path.join(HUMAN_OUTPUT_DIR, out_filename), chunk_y, target_sr)
                                    collected_count += 1
                                start += chunk_samples
                    except Exception as e:
                        if os.path.exists(temp_file):
                            os.remove(temp_file)

            except Exception:
                pass

        print(f"[OK] Finalizada extracción de Wikimedia: {collected_count} muestras guardadas en '{HUMAN_OUTPUT_DIR}'.", flush=True)
        return collected_count

    except Exception as e:
        print(f"[ERROR] Error consultando Wikimedia: {e}", flush=True)
        return 0

if __name__ == "__main__":
    print("=======================================================================", flush=True)
    print("  RECOLECTOR AUTOMÁTICO DE VOCES HUMANAS EN ESPAÑOL (GEARSHIELD 2.0)", flush=True)
    print("=======================================================================", flush=True)

    c1 = fetch_librivox_spanish_samples(target_files=50)
    c2 = fetch_wikimedia_spanish_samples(target_files=30)

    total_human = len(glob.glob(os.path.join(HUMAN_OUTPUT_DIR, "*.wav"))) + len(glob.glob(os.path.join(HUMAN_OUTPUT_DIR, "*.mp3")))
    print(f"\n[ÉXITO] Recolección completada. Total de archivos humanos en '{HUMAN_OUTPUT_DIR}': {total_human}", flush=True)
