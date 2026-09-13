"""
test_detect_endpoint.py - Prueba de integración para el endpoint POST /detect de Altur (HackMTY26).
"""

import base64
import io
import numpy as np
import soundfile as sf
from fastapi.testclient import TestClient

from main import app

client = TestClient(app)

def generate_mock_stereo_wav_b64(sr=8000, duration_sec=3.0, is_synthetic=False):
    """
    Genera un buffer WAV estéreo a 8kHz codificado en Base64.
    Canal 0 = Caller
    Canal 1 = Agent
    """
    t = np.linspace(0, duration_sec, int(sr * duration_sec), endpoint=False)
    
    if is_synthetic:
        # Señal sintética con alta frecuencia armónica y baja variabilidad
        caller_ch = (0.7 * np.sin(2 * np.pi * 220 * t) + 0.4 * np.sin(2 * np.pi * 7500 * t)).astype(np.float32)
    else:
        # Señal humana simulada con variación F0 y ruido natural
        f0 = 130.0 + 10.0 * np.sin(2 * np.pi * 2 * t)
        caller_ch = (0.5 * np.sin(2 * np.pi * f0 * t) + np.random.normal(0, 0.02, len(t))).astype(np.float32)
        
    agent_ch = (0.5 * np.sin(2 * np.pi * 300 * t)).astype(np.float32)
    
    # Intercalar en estéreo: shape (samples, 2)
    stereo_signal = np.column_stack((caller_ch, agent_ch))
    
    buf = io.BytesIO()
    sf.write(buf, stereo_signal, sr, format='WAV')
    buf.seek(0)
    
    wav_bytes = buf.read()
    return base64.b64encode(wav_bytes).decode('utf-8')

def test_detect_human_and_synthetic():
    print("=== PROBANDO ENDPOINT POST /detect (Especificacion Altur - HackMTY26) ===", flush=True)
    
    # 1. Probar muestra humana
    human_b64 = generate_mock_stereo_wav_b64(is_synthetic=False)
    resp_human = client.post("/detect", json={"audio": human_b64})
    
    print(f"\n[+] Petición Audio Humano Estéreo (8kHz): HTTP {resp_human.status_code}", flush=True)
    print(f"    Respuesta JSON: {resp_human.json()}", flush=True)
    assert resp_human.status_code == 200
    data_h = resp_human.json()
    assert "is_synthetic" in data_h
    assert "confidence" in data_h
    assert isinstance(data_h["is_synthetic"], bool)
    assert isinstance(data_h["confidence"], float)

    # 2. Probar muestra sintética
    syn_b64 = generate_mock_stereo_wav_b64(is_synthetic=True)
    resp_syn = client.post("/detect", json={"audio": syn_b64})
    
    print(f"\n[+] Petición Audio Sintético Estéreo (8kHz): HTTP {resp_syn.status_code}", flush=True)
    print(f"    Respuesta JSON: {resp_syn.json()}", flush=True)
    assert resp_syn.status_code == 200
    data_s = resp_syn.json()
    assert "is_synthetic" in data_s
    assert "confidence" in data_s
    assert isinstance(data_s["is_synthetic"], bool)
    assert isinstance(data_s["confidence"], float)
    
    print("\n[OK] ¡Todas las verificaciones del endpoint POST /detect pasaron exitosamente!", flush=True)

if __name__ == "__main__":
    test_detect_human_and_synthetic()
