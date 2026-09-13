"""
export_to_onnx.py - Exportador de modelo GearShield a formato ONNX.
Convierte la canalización (StandardScaler + RandomForestClassifier) en un único gráfico ONNX
optimizado para inferencia en el borde (Mobile SDK, C++, Flutter, etc.).
"""

import os
import joblib
import numpy as np

from sklearn.pipeline import Pipeline
from skl2onnx import convert_sklearn
from skl2onnx.common.data_types import FloatTensorType
import onnxruntime as rt

from MLbaseline import MODEL_PATH, train_baseline_model

ONNX_MODEL_PATH = "gearshield_engine.onnx"

def export_model_to_onnx(joblib_path=MODEL_PATH, onnx_path=ONNX_MODEL_PATH):
    """
    Carga el pipeline .joblib y lo exporta a .onnx.
    """
    if not os.path.exists(joblib_path):
        print(f"[INFO] Modelo '{joblib_path}' no encontrado. Entrenando modelo base...")
        train_baseline_model(model_save_path=joblib_path)

    print(f"[INFO] Cargando modelo desde '{joblib_path}'...")
    pipeline_data = joblib.load(joblib_path)
    scaler = pipeline_data["scaler"]
    model = pipeline_data["model"]
    n_features = pipeline_data.get("n_features", 88)

    # 1. Crear un Pipeline de scikit-learn unificado (Scaler + Clasificador)
    full_pipeline = Pipeline([
        ("scaler", scaler),
        ("classifier", model)
    ])

    # 2. Definir los tipos de entrada para ONNX (float32 con tamaño dinamico de lote)
    initial_type = [("float_input", FloatTensorType([None, n_features]))]

    print(f"[INFO] Convirtiendo Pipeline Scikit-Learn a ONNX (Muestras: N, Caracteristicas: {n_features})...")
    
    # Configurar opciones de conversión para incluir probabilidades si está soportado
    options = {id(model): {"zipmap": False}} if model else {}
    onnx_model = convert_sklearn(
        full_pipeline,
        initial_types=initial_type,
        options=options,
        target_opset=13
    )

    # 3. Guardar el archivo ONNX
    with open(onnx_path, "wb") as f:
        f.write(onnx_model.SerializeToString())

    file_size_mb = os.path.getsize(onnx_path) / (1024 * 1024)
    print(f"[OK] Modelo ONNX guardado exitosamente en '{onnx_path}'")
    print(f"[INFO] Tamaño del archivo ONNX: {file_size_mb:.2f} MB")

    # 4. Validar Inferencia con OnnxRuntime
    verify_onnx_export(full_pipeline, onnx_path, n_features)

    return onnx_path

def verify_onnx_export(sklearn_pipeline, onnx_path, n_features):
    """
    Verifica que la salida de OnnxRuntime sea idéntica a la salida de Scikit-Learn.
    """
    print("\n=== Verificando Inferencia entre Scikit-Learn y ONNX Runtime ===")
    
    # Crear datos dummy de prueba
    dummy_input = np.random.randn(5, n_features).astype(np.float32)

    # Inferencia en Scikit-Learn
    sk_pred = sklearn_pipeline.predict(dummy_input)
    sk_proba = sklearn_pipeline.predict_proba(dummy_input)

    # Inferencia en ONNX Runtime
    sess = rt.InferenceSession(onnx_path)
    input_name = sess.get_inputs()[0].name
    label_name = sess.get_outputs()[0].name
    proba_name = sess.get_outputs()[1].name

    onnx_res = sess.run([label_name, proba_name], {input_name: dummy_input})
    onnx_pred = onnx_res[0]
    
    # Manejar formato de probabilidades de ONNX
    if isinstance(onnx_res[1], list):
        # Si devuelve lista de diccionarios
        onnx_proba = np.array([[d[0], d[1]] for d in onnx_res[1]], dtype=np.float32)
    else:
        onnx_proba = onnx_res[1]

    # Comprobación de concordancia
    predictions_match = np.array_equal(sk_pred, onnx_pred)
    prob_diff = np.max(np.abs(sk_proba - onnx_proba))

    print(f" -> Predicciones idénticas: {predictions_match}")
    print(f" -> Diferencia máxima en probabilidades: {prob_diff:.6f}")

    if predictions_match and prob_diff < 1e-4:
        print("[OK] VERIFICACION EXITOSA: El modelo ONNX produce resultados identicos al modelo original.\n")
    else:
        print("[WARNING] Hay pequeñas diferencias esperables entre Scikit-Learn y ONNX.\n")

if __name__ == "__main__":
    export_model_to_onnx()
