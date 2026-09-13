"""
build_dataset.py - Generador y Descargador Automático de Dataset para GearShield.
Crea cientos de muestras de audios de IA y descarga audios humanos reales automáticamente
para evitar descargas manuales.
"""

import os
import sys
import glob
import asyncio
import zipfile
import urllib.request
import edge_tts

# Lista de voces neurales de IA diversas para generar audios sintéticos
AI_VOICES = [
    "es-MX-DaliaNeural",
    "es-MX-JorgeNeural",
    "es-ES-AlvaroNeural",
    "es-ES-ElviraNeural",
    "es-AR-TomasNeural",
    "es-CO-GonzaloNeural",
    "en-US-JennyNeural",
    "en-US-GuyNeural",
]

# Frases de prueba para síntesis de IA (diversificadas a propósito: ver nota en
# generate_rich_dataset.py sobre el sesgo de vocabulario bancario detectado en producción)
AI_TEXTS = [
    "Hola, te llamo de parte del servicio técnico corporativo para solicitar la actualización de tus credenciales de acceso.",
    "El informe meteorológico indica lluvias moderadas a fuertes durante las próximas horas en el sector metropolitano.",
    "Recuerde que su paquete de correo privado está listo para ser retirado en la sucursal más cercana a su domicilio.",
    "Para completar el proceso de autenticación de dos factores, ingrese el código de seis dígitos enviado a su dispositivo.",
    "La inteligencia artificial ha evolucionado de forma exponencial permitiendo la síntesis de voz humana de alta fidelidad.",
    "El equipo local ganó el partido con un gol anotado en el último minuto.",
    "Preparamos una cena sencilla con pasta, verduras salteadas y un poco de queso parmesano.",
    "El vuelo hacia la costa salió con casi una hora de retraso por el mal clima.",
    "Mi hermano llegó tarde otra vez porque se quedó dormido después del almuerzo.",
    "El médico recomendó descansar más y beber suficiente agua durante la semana.",
    "La biblioteca amplió su horario de atención durante la temporada de exámenes finales.",
    "La película ganó varios premios importantes en el festival internacional de cine.",
    "Adoptamos un cachorro la semana pasada y ya se robó el corazón de toda la familia.",
    "Espero que tengas un excelente fin de semana en compañía de tu familia."
]

async def generate_ai_samples(output_dir="data/ai", target_count=50):
    """
    Genera automáticamente decenas de audios sintéticos de IA utilizando diferentes
    voces neurales, velocidades y tonos.
    """
    print(f"\n[INFO] Generando {target_count} audios sintéticos de IA en '{output_dir}'...")
    os.makedirs(output_dir, exist_ok=True)
    
    count = 0
    for idx, text in enumerate(AI_TEXTS):
        for voice in AI_VOICES:
            if count >= target_count:
                break
            
            filename = f"generated_ai_voice_{count+1:03d}_{voice.replace('-', '_')}.mp3"
            filepath = os.path.join(output_dir, filename)
            
            try:
                # Variar velocidad y tono para simular distintos motores de IA
                rate = "+0%" if count % 2 == 0 else "-5%"
                pitch = "+0Hz" if count % 3 == 0 else "+10Hz"
                
                tts = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
                await tts.save(filepath)
                count += 1
                if count % 10 == 0 or count == target_count:
                    print(f"   [+] Generados {count}/{target_count} audios de IA...")
            except Exception as e:
                print(f"   [!] Error generando con voz {voice}: {e}")

    print(f"[OK] Generación de IA finalizada. Total: {count} archivos MP3 en '{output_dir}'.")

def download_human_dataset(output_dir="data/human"):
    """
    Descarga automáticamente un conjunto de muestras de voz humana real desde un repositorio público open-source (LibriSpeech/OpenSLR).
    """
    print(f"\n[INFO] Descargando muestras de voz humana real en '{output_dir}'...")
    os.makedirs(output_dir, exist_ok=True)

    # URL pública de dataset de voz humana libre (LibriSpeech dev-clean mini sample)
    url = "https://www.openslr.org/resources/12/dev-clean.tar.gz"
    archive_path = "dev-clean_mini.tar.gz"

    try:
        if not os.path.exists(archive_path):
            print(f"   [+] Descargando archivo comprimido desde OpenSLR ({url})...")
            # Descargar archivo con barra de progreso basica
            urllib.request.urlretrieve(url, archive_path)
            print("   [+] Descarga completada. Extrayendo archivos de voz humana...")

        import tarfile
        with tarfile.open(archive_path, "r:gz") as tar:
            # Extraer archivos .flac / .wav en la carpeta human
            members = [m for m in tar.getmembers() if m.name.endswith(".flac") or m.name.endswith(".wav")]
            print(f"   [+] Extrayendo {len(members)} archivos de voz de personas reales...")
            for m in members[:100]:  # Extraer las primeras 100 muestras reales
                m.name = os.path.basename(m.name)
                tar.extract(m, path=output_dir)

        print(f"[OK] Muestras de voz humana extraídas exitosamente en '{output_dir}'.")

    except Exception as e:
        print(f"[WARN] No se pudo descargar el dataset público automáticamente: {e}")
        print("💡 CONSEJO: Puedes copiar de 3 a 5 audios largos (ej. podcasts/entrevistas de 5 min) dentro de 'data/human/' y DataSet.py los convertirá automáticamente en más de 600 muestras de entrenamiento.")

if __name__ == "__main__":
    print("======================================================================")
    print("   BUILD DATASET - GENERADOR & DESCARGADOR AUTOMÁTICO PARA GEARSHIELD ")
    print("======================================================================")
    
    # 1. Generar audios de IA
    asyncio.run(generate_ai_samples(target_count=40))

    # 2. Intentar descargar voz humana
    download_human_dataset()

    print("\n======================================================================")
    print(" [OK] ¡Dataset preparado! Ahora ejecuta 'python MLbaseline.py' para entrenar.")
    print("======================================================================\n")
