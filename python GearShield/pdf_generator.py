"""
pdf_generator.py - Generador de Reportes Forenses en PDF para GearShield.
Crea un informe de auditoría de seguridad detallado para incidentes o reconfirmaciones.
"""

import os
from datetime import datetime
from reportlab.lib.pagesizes import letter
from reportlab.lib import colors
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer, Table, TableStyle, HRFlowable

def generate_forensic_pdf(analysis_result, output_pdf_path=None):
    """
    Genera un informe forense en formato PDF a partir de los resultados de análisis de GearShield.
    """
    if output_pdf_path is None:
        audio_name = os.path.basename(analysis_result.get("audio_path", "audio_sample.wav"))
        timestamp_str = datetime.now().strftime("%Y%m%d_%H%M%S")
        output_dir = "reports"
        os.makedirs(output_dir, exist_ok=True)
        output_pdf_path = os.path.join(output_dir, f"Reporte_GearShield_{timestamp_str}.pdf")

    doc = SimpleDocTemplate(
        output_pdf_path,
        pagesize=letter,
        rightMargin=36,
        leftMargin=36,
        topMargin=36,
        bottomMargin=36
    )

    styles = getSampleStyleSheet()

    # Estilos personalizados
    title_style = ParagraphStyle(
        'DocTitle',
        parent=styles['Heading1'],
        fontSize=20,
        leading=24,
        textColor=colors.HexColor('#0F172A'),
        fontName='Helvetica-Bold'
    )
    subtitle_style = ParagraphStyle(
        'DocSubtitle',
        parent=styles['Normal'],
        fontSize=10,
        leading=14,
        textColor=colors.HexColor('#64748B')
    )
    header_style = ParagraphStyle(
        'SectionHeader',
        parent=styles['Heading2'],
        fontSize=13,
        leading=17,
        textColor=colors.HexColor('#1E293B'),
        fontName='Helvetica-Bold',
        spaceBefore=10,
        spaceAfter=6
    )
    body_style = ParagraphStyle(
        'BodyTextCustom',
        parent=styles['Normal'],
        fontSize=9.5,
        leading=14,
        textColor=colors.HexColor('#334155')
    )

    story = []

    # 1. Encabezado del Reporte
    story.append(Paragraph("GEARSHIELD FORENSIC AUDIO REPORT", title_style))
    story.append(Paragraph(f"Auditoría de Inyección de IA y Detección de Sintetizadores de Voz | Generado: {datetime.now().strftime('%d/%m/%Y %H:%M:%S')}", subtitle_style))
    story.append(Spacer(1, 10))
    story.append(HRFlowable(width="100%", thickness=2, color=colors.HexColor('#0284C7'), spaceBefore=0, spaceAfter=15))

    # 2. Resumen Ejecutivo
    story.append(Paragraph("1. RESUMEN EJECUTIVO", header_style))

    risk_ai = analysis_result.get("overall_risk_ai", 0.0)
    label = analysis_result.get("label", "Desconocido")
    filename = os.path.basename(analysis_result.get("audio_path", "N/A"))

    # Color según el nivel de riesgo
    if risk_ai >= 70.0:
        status_color = colors.HexColor('#DC2626')  # Rojo
        risk_level = "CRÍTICO / DEEPFAKE ALTA PROBABILIDAD"
    elif risk_ai >= 50.0:
        status_color = colors.HexColor('#F59E0B')  # Naranja/Amarillo
        risk_level = "MODERADO / AUDIO MIXTO ALTERADO"
    else:
        status_color = colors.HexColor('#16A34A')  # Verde
        risk_level = "BAJO / VOZ HUMANA ORGANICA"

    summary_data = [
        [Paragraph("<b>Archivo Analizado:</b>", body_style), Paragraph(filename, body_style)],
        [Paragraph("<b>Diagnóstico Principal:</b>", body_style), Paragraph(f"<font color='{status_color.hexval()}'><b>{label}</b></font>", body_style)],
        [Paragraph("<b>Nivel Máximo de Riesgo IA:</b>", body_style), Paragraph(f"<b>{risk_ai:.2f}%</b> ({risk_level})", body_style)],
        [Paragraph("<b>Frecuencia de Muestreo Target:</b>", body_style), Paragraph("16,000 Hz (Sliding Window 3.0s)", body_style)]
    ]

    t_summary = Table(summary_data, colWidths=[160, 380])
    t_summary.setStyle(TableStyle([
        ('BACKGROUND', (0, 0), (-1, -1), colors.HexColor('#F8FAFC')),
        ('BOX', (0, 0), (-1, -1), 1, colors.HexColor('#E2E8F0')),
        ('INNERGRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#F1F5F9')),
        ('PADDING', (0, 0), (-1, -1), 6),
    ]))
    story.append(t_summary)
    story.append(Spacer(1, 15))

    # 3. Intervalos de Alerta Detectados
    story.append(Paragraph("2. INTERVALOS CON DETECCIONAL DE IA (Sintetizador o Deepfake)", header_style))
    intervals = analysis_result.get("ai_detected_intervals", [])

    if intervals:
        alert_data = [["Intervalo de Tiempo", "Duración", "Riesgo de IA", "Estado de Amenaza"]]
        for start, end, prob in intervals:
            dur = end - start
            alert_data.append([
                f"{start:.1f}s - {end:.1f}s",
                f"{dur:.1f} segundos",
                f"{prob:.1f}%",
                "AMENAZA DETECTADA"
            ])

        t_alerts = Table(alert_data, colWidths=[130, 110, 130, 170])
        t_alerts.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#EF4444')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#FCA5A5')),
            ('PADDING', (0, 0), (-1, -1), 5),
        ]))
        story.append(t_alerts)
    else:
        story.append(Paragraph("<i>No se detectaron inyecciones de voz sintética ni alteraciones en los intervalos analizados.</i>", body_style))

    story.append(Spacer(1, 15))

    # 4. Línea de Tiempo de Ventana Deslizante (Timeline)
    story.append(Paragraph("3. LÍNEA DE TIEMPO DETALLADA (VENTANA DESLIZANTE)", header_style))
    timeline = analysis_result.get("timeline", [])

    if timeline:
        timeline_data = [["Ventana", "Intervalo (Segundos)", "Probabilidad Humana", "Probabilidad IA", "Diagnóstico"]]
        for idx, item in enumerate(timeline, start=1):
            tag = "SINTÉTICO / IA" if item["is_ai"] else "HUMANO"
            tag_color = "#DC2626" if item["is_ai"] else "#16A34A"
            timeline_data.append([
                f"#{idx}",
                f"{item['start_sec']:.1f}s - {item['end_sec']:.1f}s",
                f"{item['prob_human']:.1f}%",
                f"{item['prob_ai']:.1f}%",
                Paragraph(f"<font color='{tag_color}'><b>{tag}</b></font>", body_style)
            ])

        t_timeline = Table(timeline_data, colWidths=[60, 130, 120, 110, 120])
        t_timeline.setStyle(TableStyle([
            ('BACKGROUND', (0, 0), (-1, 0), colors.HexColor('#1E293B')),
            ('TEXTCOLOR', (0, 0), (-1, 0), colors.white),
            ('FONTNAME', (0, 0), (-1, 0), 'Helvetica-Bold'),
            ('ALIGN', (0, 0), (-1, -1), 'CENTER'),
            ('GRID', (0, 0), (-1, -1), 0.5, colors.HexColor('#CBD5E1')),
            ('PADDING', (0, 0), (-1, -1), 4),
        ]))
        story.append(t_timeline)

    story.append(Spacer(1, 20))
    story.append(HRFlowable(width="100%", thickness=0.5, color=colors.HexColor('#CBD5E1'), spaceBefore=0, spaceAfter=10))
    story.append(Paragraph("<i>Este documento es un informe automatizado generado por el motor analítico GearShield Engine v1.0.</i>", subtitle_style))

    doc.build(story)
    print(f"[OK] Reporte PDF generado exitosamente en '{output_pdf_path}'")
    return output_pdf_path

if __name__ == "__main__":
    dummy_result = {
        "audio_path": "data/mixed_sample_50_50.wav",
        "label": "AUDIO MIXTO ALTERADO (Inyección de IA Detectada)",
        "overall_risk_ai": 98.4,
        "max_ai_prob": 98.4,
        "avg_ai_prob": 52.1,
        "ai_detected_intervals": [(3.0, 6.0, 98.4)],
        "timeline": [
            {"start_sec": 0.0, "end_sec": 3.0, "prob_human": 95.2, "prob_ai": 4.8, "is_ai": False},
            {"start_sec": 3.0, "end_sec": 6.0, "prob_human": 1.6, "prob_ai": 98.4, "is_ai": True}
        ]
    }
    generate_forensic_pdf(dummy_result)
