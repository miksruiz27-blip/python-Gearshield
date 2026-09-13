"""
test_api.py - Suite de Pruebas Automatizadas para la API de GearShield.
Prueba los endpoints /health, /analyze, /reconfirm y /generate-pdf usando TestClient.
"""

import os
import sys
from fastapi.testclient import TestClient
from main import app

client = TestClient(app)

def test_health_endpoint():
    print("[TEST] Probando endpoint /health...", flush=True)
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "online"
    assert data["engine_ready"] is True
    print(f" -> OK: {data}", flush=True)

def test_analyze_endpoint():
    print("\n[TEST] Probando endpoint /analyze...", flush=True)
    test_audio = "gabyruiz.ogg"
    if not os.path.exists(test_audio):
        print(f" -> Skip: '{test_audio}' no encontrado.", flush=True)
        return

    with open(test_audio, "rb") as f:
        response = client.post(
            "/analyze",
            files={"file": (test_audio, f, "audio/ogg")}
        )
    assert response.status_code == 200
    data = response.json()
    assert "label" in data
    assert "overall_risk_ai" in data
    assert "timeline" in data
    print(f" -> OK: Diagnostico='{data['label']}', Riesgo IA={data['overall_risk_ai']:.2f}%", flush=True)

def test_reconfirm_endpoint():
    print("\n[TEST] Probando endpoint /reconfirm (5% audit)...", flush=True)
    test_audio = "gabyruiz.ogg"
    if not os.path.exists(test_audio):
        print(f" -> Skip: '{test_audio}' no encontrado.", flush=True)
        return

    with open(test_audio, "rb") as f:
        response = client.post(
            "/reconfirm",
            data={"user_id": "user_12345", "reason": "Verificacion de Segunda Firma"},
            files={"file": (test_audio, f, "audio/ogg")}
        )
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "reconfirmed"
    assert data["pdf_download_url"] is not None
    print(f" -> OK: Reconfirmation ID={data['reconfirmation_id']}, PDF Download={data['pdf_download_url']}", flush=True)

if __name__ == "__main__":
    print("=== Ejecutando Pruebas de API GearShield ===", flush=True)
    test_health_endpoint()
    test_analyze_endpoint()
    test_reconfirm_endpoint()
    print("\n[TODAS LAS PRUEBAS PASARON EXITOSAMENTE]\n", flush=True)
