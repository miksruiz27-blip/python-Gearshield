"""
MLbaseline.py - Entrenamiento y evaluación del modelo optimizado para GearShield.
Entrena un clasificador de alta precisión (Random Forest optimizado)
con validación cruzada (5-Fold Stratified K-Fold) y exportación directa a ONNX.
"""

import os
import joblib
import numpy as np
from sklearn.model_selection import GroupShuffleSplit, StratifiedGroupKFold, cross_val_score
from sklearn.preprocessing import StandardScaler
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix, accuracy_score, roc_auc_score, f1_score

from DataSet import load_dataset_from_directory, create_dummy_dataset

MODEL_PATH = "gearshield_baseline.joblib"

def train_baseline_model(data_dir="data", model_save_path=MODEL_PATH):
    """
    Carga el dataset de audios, entrena el modelo de clasificación optimizado,
    ejecuta validación cruzada de 5 pliegues y guarda el modelo entrenado.
    El split y la CV se agrupan por archivo fuente (`groups`) para que ningún
    fragmento del mismo audio aparezca a la vez en train y test (evita leakage).
    """
    print("=== Iniciando Entrenamiento del Modelo Avanzado (GearShield) ===")

    # 1. Cargar el dataset completo (Humano, IA y IA Aumentada)
    X, y, groups = load_dataset_from_directory(data_dir)

    # Si el dataset está vacío, generar datos de prueba automáticamente
    if len(X) == 0:
        print("[INFO] No se encontró dataset existente. Generando datos de prueba...")
        create_dummy_dataset(data_dir, samples_per_class=25)
        X, y, groups = load_dataset_from_directory(data_dir)

    print(f"[INFO] Dataset cargado: {X.shape[0]} muestras totales, {X.shape[1]} características por muestra, {len(set(groups))} archivos fuente.")
    print(f"[INFO] Distribución de clases -> Humanos (0): {np.sum(y == 0)}, IA Sintética/Aumentada (1): {np.sum(y == 1)}")

    # 2. Dividir en conjuntos de entrenamiento y prueba (75% train / 25% test),
    #    agrupado por archivo fuente para que no haya fuga entre fragmentos del mismo audio.
    gss = GroupShuffleSplit(n_splits=1, test_size=0.25, random_state=42)
    train_idx, test_idx = next(gss.split(X, y, groups=groups))
    X_train, X_test = X[train_idx], X[test_idx]
    y_train, y_test = y[train_idx], y[test_idx]
    groups_train = groups[train_idx]

    # 3. Normalización de características
    scaler = StandardScaler()
    X_train_scaled = scaler.fit_transform(X_train)
    X_test_scaled = scaler.transform(X_test)

    # 4. Construcción del Clasificador Optimizado
    print("[INFO] Entrenando Clasificador Random Forest Optimizado...")
    model = RandomForestClassifier(n_estimators=250, max_depth=14, random_state=42, class_weight="balanced")
    model.fit(X_train_scaled, y_train)

    # 5. Validación Cruzada Estratificada de 5 Pliegues agrupada por archivo (5-Fold Group CV)
    print("[INFO] Ejecutando Validación Cruzada Estratificada Agrupada (5-Fold Group CV)...")
    sgkf = StratifiedGroupKFold(n_splits=5, shuffle=True, random_state=42)
    cv_scores = cross_val_score(model, X_train_scaled, y_train, cv=sgkf, groups=groups_train, scoring='accuracy')
    print(f" -> Resultados 5-Fold Group CV Accuracy: {cv_scores.mean()*100:.2f}% (+/- {cv_scores.std()*100:.2f}%)")

    # 6. Evaluación en el Conjunto de Prueba
    y_pred = model.predict(X_test_scaled)
    y_proba = model.predict_proba(X_test_scaled)[:, 1]

    acc = accuracy_score(y_test, y_pred)
    f1 = f1_score(y_test, y_pred)
    try:
        auc = roc_auc_score(y_test, y_proba)
    except Exception:
        auc = 0.0

    print("\n" + "=" * 65)
    print("      EVALUACION DE CALIDAD EN CONJUNTO DE PRUEBA (TEST SET)")
    print("=" * 65)
    print(f" Exactitud (Accuracy):             {acc * 100:.2f}%")
    print(f" Puntaje F1 (F1-Score):           {f1 * 100:.2f}%")
    if auc > 0:
        print(f" Área Bajo la Curva (ROC-AUC):     {auc:.4f}")
    
    print("\n Reporte de Clasificación Detallado:")
    print(classification_report(y_test, y_pred, target_names=["Humano", "IA Sintética"]))

    print(" Matriz de Confusión:")
    cm = confusion_matrix(y_test, y_pred)
    print(f"   [Verdaderos Humanos: {cm[0,0]:3d} | Falsos IA:      {cm[0,1]:3d}]")
    print(f"   [Falsos Humanos:     {cm[1,0]:3d} | Verdaderos IA:  {cm[1,1]:3d}]")
    print("=" * 65 + "\n")

    # 7. Guardar el modelo y el escalador juntos
    pipeline_data = {
        "scaler": scaler,
        "model": model,
        "n_features": X.shape[1]
    }
    joblib.dump(pipeline_data, model_save_path)
    print(f"[OK] Modelo optimizado guardado exitosamente en '{model_save_path}'.")

    # 8. Re-exportar automáticamente a ONNX para mantener el SDK listo
    try:
        from export_to_onnx import export_model_to_onnx
        print("[INFO] Re-exportando modelo a formato ONNX para Edge SDK...")
        export_model_to_onnx(joblib_path=model_save_path)
    except Exception as e:
        print(f"[WARN] No se pudo re-exportar a ONNX automáticamente: {e}")

    return model, scaler

if __name__ == "__main__":
    train_baseline_model()
