"""
generate_rich_dataset.py - Generación y Aumentación Acústica Simétrica para GearShield.
Aplica aumentación simétrica tanto a audios de IA como a voces Humanas (incluyendo notas de WhatsApp)
para que el modelo aprenda a ignorar artefactos de compresión y se enfoque únicamente en diferencias de voz real vs sintetizada.
"""

import os
import glob
import asyncio
import numpy as np
import librosa
import soundfile as sf
import edge_tts

AI_VOICES_RICH = [
    "es-MX-DaliaNeural",
    "es-MX-JorgeNeural",
    "es-ES-AlvaroNeural",
    "es-ES-ElviraNeural",
    "es-AR-TomasNeural",
    "es-AR-ElenaNeural",
    "es-CO-GonzaloNeural",
    "es-CO-SalomeNeural",
    "es-CL-LorenzoNeural",
    "es-PE-CamilaNeural",
    "en-US-JennyNeural",
    "en-US-GuyNeural",
    "en-US-AriaNeural",
    "en-GB-SoniaNeural",
    "en-GB-RyanNeural"
]

AI_TEXTS_RICH = [
    # Banca y Verificación General (proporción reducida a propósito: ver nota abajo)
    "Por favor, confirme su código de seguridad de seis dígitos.",
    "Estimado cliente, detectamos una transacción reciente en su cuenta. Por favor verifique la actividad.",
    "Buenas tardes, le llamamos del departamento de control de fraudes para confirmar su compra.",
    "Para completar el proceso de autenticación de dos factores, ingrese la clave dinámica enviada a su dispositivo.",
    "Su saldo disponible ha sido actualizado en la plataforma de banca en línea.",
    "Le recordamos que su tarjeta vencerá el próximo mes, puede solicitar la renovación desde la aplicación.",
    "Se ha generado un comprobante digital con el número de folio correspondiente a su operación.",
    "Gracias por comunicarse con nuestro departamento de atención a clientes, en un momento le atenderemos.",
    "Esta llamada puede ser grabada con fines de calidad y capacitación del servicio.",
    "Para ventas presione uno, para soporte técnico presione dos, para hablar con un operador presione cero.",
    "Entiendo su inquietud, permítame consultar el sistema para verificar el estado de su solicitud.",
    "Agradecemos su paciencia mientras procesamos la información en nuestra plataforma.",
    "Le informamos que su solicitud de crédito se encuentra en proceso de revisión.",
    "Recuerde actualizar sus datos de contacto para mantener activa su cuenta.",
    # Clima y Naturaleza
    "El informe meteorológico indica probabilidades de lluvia moderada para la tarde de hoy.",
    "Se espera un descenso considerable de la temperatura durante la madrugada.",
    "El sol brilló con fuerza toda la mañana en la costa del Pacífico.",
    "Los vientos del norte podrían intensificarse hacia el fin de semana.",
    "La sequía de este año ha afectado gravemente las cosechas de la región.",
    "Un arcoíris apareció justo después de la tormenta de esta tarde.",
    "Las montañas amanecieron cubiertas de nieve fresca esta semana.",
    "El bosque se llenó de un aroma húmedo después de la lluvia.",
    "La marea subió antes de lo previsto y sorprendió a los pescadores.",
    "Las ballenas migran por esta costa cada año entre junio y septiembre.",
    "El huracán perdió fuerza antes de tocar tierra firme.",
    "El otoño pintó de naranja las hojas de los árboles del parque.",
    # Comida y Cocina
    "Esta receta lleva cebolla, ajo y un toque de comino recién molido.",
    "El pan recién horneado inundó toda la casa con su aroma.",
    "Prefiero el café sin azúcar, pero con un poco de canela.",
    "La abuela siempre dice que el secreto está en dejar reposar la masa.",
    "Vamos a preparar tacos de pescado para la cena de esta noche.",
    "El postre quedó un poco dulce, pero de todas formas estuvo delicioso.",
    "¿Ya probaste el nuevo restaurante de comida tailandesa del centro?",
    "El arroz necesita hervir a fuego lento durante veinte minutos.",
    "Compré tomates, aguacate y cilantro para hacer guacamole fresco.",
    "La sopa quedó perfecta con ese toque de limón al final.",
    "Me encanta desayunar huevos revueltos con pan tostado los domingos.",
    "El chocolate caliente es lo mejor para las noches frías de invierno.",
    # Deportes
    "El equipo local ganó el partido con un gol en el último minuto.",
    "El maratón de este año atrajo a corredores de más de veinte países.",
    "La selección se clasificó al torneo después de una temporada difícil.",
    "El entrenador pidió más disciplina táctica para el próximo encuentro.",
    "Los aficionados llenaron el estadio a pesar de la lluvia.",
    "El nadador rompió el récord nacional en la prueba de doscientos metros.",
    "El ciclista lideró la carrera durante casi toda la etapa de montaña.",
    "El árbitro revisó la jugada varias veces antes de tomar una decisión.",
    "El equipo femenino de voleibol avanzó directo a la final.",
    "La final del torneo se jugará el próximo sábado por la noche.",
    # Viajes y Turismo
    "El vuelo hacia la costa salió con casi una hora de retraso.",
    "Reservamos un hotel pequeño cerca del centro histórico de la ciudad.",
    "La playa estaba prácticamente vacía a esa hora de la mañana.",
    "Recorrimos el museo completo en poco más de dos horas.",
    "El tren cruza varios túneles antes de llegar a la estación central.",
    "Nos perdimos un poco entre las calles angostas del pueblo.",
    "El mirador ofrece una vista increíble de todo el valle.",
    "Alquilamos bicicletas para recorrer la isla durante el fin de semana.",
    "El guía nos contó historias curiosas sobre la fundación del pueblo.",
    "La aerolínea canceló el vuelo por las condiciones del clima.",
    # Familia y Vida Cotidiana
    "Mi hermano llegó tarde otra vez porque se quedó dormido.",
    "Los niños jugaron en el patio hasta que anocheció por completo.",
    "Mi abuela cumple ochenta años el próximo mes y haremos una fiesta.",
    "Olvidé las llaves en la oficina y tuve que regresar por ellas.",
    "El perro no ha dejado de ladrar desde que empezó a llover.",
    "Vamos a pintar la sala este fin de semana, ya elegimos el color.",
    "Mi prima se muda de ciudad la próxima semana por su nuevo trabajo.",
    "El bebé finalmente durmió toda la noche sin despertarse.",
    "Quedamos en encontrarnos en la plaza a las siete de la noche.",
    "La reunión familiar se extendió hasta pasada la medianoche.",
    "Tuvimos que reparar la lavadora porque dejó de funcionar de repente.",
    "Mi vecino organizó una parrillada para celebrar el fin de semana.",
    # Salud y Bienestar
    "El médico recomendó descansar más y beber suficiente agua.",
    "Empecé a caminar todas las mañanas para mejorar mi condición física.",
    "La cita con el dentista quedó reprogramada para la próxima semana.",
    "Dormir bien es tan importante como llevar una alimentación balanceada.",
    "El dolor de cabeza desapareció después de tomar un poco de aire fresco.",
    "La farmacia del barrio ya no cierra los domingos.",
    "Practicar yoga por las mañanas me ayuda a bajar el estrés.",
    "El chequeo médico anual salió sin ninguna complicación.",
    "Es recomendable estirar antes y después de hacer ejercicio.",
    "La gripe lo mantuvo en cama durante casi toda la semana.",
    # Educación y Estudios
    "El examen final abarca todos los temas vistos durante el semestre.",
    "La maestra explicó el ejercicio de matemáticas paso a paso.",
    "La biblioteca amplió su horario durante la temporada de exámenes.",
    "Presenté mi proyecto de ciencias frente a todo el salón.",
    "El profesor pidió un ensayo de al menos tres páginas.",
    "Me inscribí a un curso de fotografía los fines de semana.",
    "La universidad anunció nuevas becas para estudiantes de intercambio.",
    "El grupo de estudio se reúne todos los martes por la tarde.",
    "Aprender un segundo idioma requiere práctica constante y paciencia.",
    "La conferencia sobre historia antigua duró casi dos horas.",
    # Tecnología General (sin temática de fraude)
    "La nueva actualización del sistema mejora considerablemente la duración de la batería.",
    "Los sistemas de inteligencia artificial analizan grandes volúmenes de datos en tiempo real.",
    "El nuevo teléfono incorpora una cámara con mejor estabilización de imagen.",
    "La conexión a internet se volvió mucho más estable después del cambio de router.",
    "Las nuevas herramientas digitales facilitan el trabajo colaborativo entre equipos remotos.",
    "El desarrollo de tecnologías avanzadas ha permitido optimizar procesos industriales complejos.",
    "La aplicación se actualizó automáticamente durante la noche.",
    "Los autos eléctricos ganan terreno cada año en el mercado global.",
    "La impresora tridimensional permitió fabricar la pieza en apenas unas horas.",
    "El nuevo procesador promete un rendimiento notablemente superior.",
    # Entretenimiento
    "La película ganó varios premios en el festival internacional de cine.",
    "El concierto se extendió casi tres horas y el público no dejó de cantar.",
    "La serie estrenó su temporada final este fin de semana.",
    "El músico presentó su nuevo álbum después de cuatro años de silencio.",
    "La obra de teatro combina comedia y drama de una forma muy original.",
    "El videojuego se volvió tendencia apenas unos días después de su lanzamiento.",
    "El documental explora la vida silvestre de la selva amazónica.",
    "La banda anunció una gira por varias ciudades del continente.",
    "El libro se convirtió en un éxito de ventas casi de inmediato.",
    "El festival de música reunió a miles de personas en el parque central.",
    # Trabajo y Oficina (neutral)
    "La reunión de equipo se movió para el jueves por la mañana.",
    "Terminé el reporte justo antes de la fecha límite.",
    "El nuevo proyecto requiere coordinación entre varios departamentos.",
    "Mi jefe pidió una actualización sobre el avance del proyecto.",
    "La oficina se mudará al piso de arriba el próximo mes.",
    "El equipo de diseño presentó tres propuestas distintas para el logotipo.",
    "Tuvimos una videollamada larga para revisar los pendientes de la semana.",
    "El nuevo compañero se integró rápido al equipo de trabajo.",
    "La capacitación de esta semana se enfocó en mejorar la comunicación interna.",
    "Aprobaron el presupuesto para renovar el mobiliario de la oficina.",
    # Mascotas y Animales
    "El gato se pasó toda la tarde durmiendo sobre el sofá.",
    "Llevamos al perro al veterinario para su revisión anual.",
    "Los pájaros construyeron un nido justo sobre la ventana de la cocina.",
    "Adoptamos un cachorro la semana pasada y ya se robó nuestro corazón.",
    "El acuario del centro comercial tiene una tortuga gigante.",
    "El caballo trotó tranquilo por todo el sendero del bosque.",
    "Mi hámster escapó de la jaula y lo encontramos detrás del refrigerador.",
    "Las abejas son fundamentales para la polinización de los cultivos.",
    # Compras Generales (no bancarias)
    "Encontré una oferta muy buena en la tienda de ropa del centro comercial.",
    "El supermercado amplió su sección de productos orgánicos.",
    "Compré unos zapatos nuevos para la boda del próximo mes.",
    "La tienda en línea ofrece envío gratis en compras mayores a cierto monto.",
    "Aproveché las rebajas de temporada para renovar todo el clóset.",
    "El mercado de artesanías abre solo los fines de semana.",
    "Cambié de opinión y devolví la lámpara que había comprado ayer.",
    "La librería tiene una promoción especial por su aniversario.",
    # Conversaciones Cotidianas y Small Talk
    "Hola, ¿cómo has estado? Hace mucho tiempo que no hablábamos.",
    "Espero que tengas un excelente fin de semana en compañía de tu familia.",
    "¿Podrías por favor repetirme tu dirección de correo electrónico?",
    "Muchas gracias por tu ayuda, de verdad lo aprecio mucho.",
    "Nos vemos mañana entonces, que descanses muy bien.",
    "Disculpa la demora en responder, tuve una semana bastante ocupada.",
    "¿Qué planes tienes para las vacaciones de este año?",
    "Fue un gusto verte de nuevo después de tanto tiempo.",
    "Avísame cualquier cosa que necesites, aquí estoy para ayudarte.",
    "¿Cómo te fue en la entrevista de trabajo de esta mañana?",
    "Qué buena idea, hace tiempo que no salimos todos juntos.",
    "Perdón por la tardanza, el tráfico estuvo terrible hoy.",
    # Noticias Generales (no financieras)
    "El ayuntamiento anunció la construcción de un nuevo parque público.",
    "Los científicos descubrieron una nueva especie de rana en la selva.",
    "El festival cultural de este año reunió a artistas de toda la región.",
    "La ciudad inaugurará una nueva línea de transporte público el próximo mes.",
    "Los bomberos controlaron el incendio antes de que se propagara más.",
    "El equipo de rescate localizó a los excursionistas sanos y salvos.",
    "La comunidad se organizó para limpiar la playa este fin de semana.",
    "El nuevo puente reducirá considerablemente el tiempo de traslado.",
    # English (varied topics, para las voces en-US/en-GB)
    "The weather forecast predicts light rain for most of the afternoon.",
    "She spent the whole weekend reading a new mystery novel.",
    "The concert was rescheduled due to unexpected technical issues.",
    "They just adopted a puppy from the local animal shelter.",
    "The new restaurant downtown has amazing homemade pasta.",
    "He finally finished painting the living room after two weekends.",
    "The museum added a new exhibit about ancient civilizations.",
    "Our flight got delayed because of heavy fog this morning.",
    "The kids built a huge sandcastle before the tide came in.",
    "The team celebrated their victory long into the night."
]
# Nota de diseño: antes esta lista estaba dominada por vocabulario de banca/call-center
# (~40% de las frases, más 12 comandos de una sola palabra como "Transferencia." o
# "Confirmado."). Como esas frases eran EXCLUSIVAS de la clase "IA" (la clase "humano"
# viene de fuentes con temática completamente distinta: notas de WhatsApp, LibriSpeech,
# llamadas Altur), el modelo terminó asociando el patrón MFCC/espectral de pronunciar esas
# palabras específicas con "sintético", sin importar quién las dijera -> falso positivo al
# oír "bancaria", "inmobiliaria" o "transferencia" en voz real. Ahora la banca es solo un
# tema más entre muchos (~8% del total) y se eliminaron los comandos de una sola palabra
# (peor caso: en una ventana de 3s, la palabra aislada ES el 100% de la señal analizada).

async def generate_diverse_ai_audio(output_dir="data/ai", count_target=45):
    """
    Genera audios sintéticos utilizando múltiples voces neurales, ritmos y tonos.
    """
    os.makedirs(output_dir, exist_ok=True)
    print(f"\n[INFO] Generando {count_target} audios de IA con alta variedad acústica en '{output_dir}'...", flush=True)

    generated_count = 0
    rates = ["-15%", "-10%", "-5%", "+0%", "+5%", "+10%", "+15%"]
    pitches = ["-15Hz", "-8Hz", "+0Hz", "+8Hz", "+15Hz"]

    idx = 0
    while generated_count < count_target:
        text = AI_TEXTS_RICH[idx % len(AI_TEXTS_RICH)]
        voice = AI_VOICES_RICH[idx % len(AI_VOICES_RICH)]
        rate = rates[idx % len(rates)]
        pitch = pitches[idx % len(pitches)]

        voice_clean = voice.replace("-", "_")
        filename = f"synth_ai_{generated_count+1:03d}_{voice_clean}.mp3"
        filepath = os.path.join(output_dir, filename)

        try:
            tts = edge_tts.Communicate(text, voice, rate=rate, pitch=pitch)
            await tts.save(filepath)
            generated_count += 1
            if generated_count % 15 == 0 or generated_count == count_target:
                print(f"   [+] Sintetizados {generated_count}/{count_target} audios de IA...", flush=True)
        except Exception:
            pass

        idx += 1

    print(f"[OK] Generación completada: {generated_count} audios sintéticos de IA en '{output_dir}'.", flush=True)

def apply_acoustic_augmentations(audio_path, output_dir):
    """
    Aplica aumentación acústica simétrica (Telefonía 8kHz, Ruido de Fondo, Pitch Shift).
    """
    os.makedirs(output_dir, exist_ok=True)
    base_name = os.path.splitext(os.path.basename(audio_path))[0]

    try:
        y, sr = librosa.load(audio_path, sr=16000, mono=True)
        if len(y) < int(0.2 * sr):
            return

        # 1. Simulación Telefónica / Compresión (Resampling 8kHz -> 16kHz)
        y_phone = librosa.resample(y, orig_sr=16000, target_sr=8000)
        y_phone = librosa.resample(y_phone, orig_sr=8000, target_sr=16000)
        sf.write(os.path.join(output_dir, f"{base_name}_telephony.wav"), y_phone, 16000)

        # 2. Simulación Códec GSM (Cuantización Mu-Law de 8-bits)
        y_mulaw = librosa.mu_compress(y)
        y_gsm = librosa.mu_expand(y_mulaw)
        sf.write(os.path.join(output_dir, f"{base_name}_gsm.wav"), y_gsm, 16000)

        # 3. Simulación Compresión OPUS (Filtro Paso Bajo Telecom 4kHz)
        stft = librosa.stft(y)
        freqs = librosa.fft_frequencies(sr=16000)
        stft[freqs > 4000, :] *= 0.1  # Atenuación agresiva de altas frecuencias
        y_opus = librosa.istft(stft)
        sf.write(os.path.join(output_dir, f"{base_name}_opus.wav"), y_opus, 16000)

        # 4. Inyección de Ruido de Fondo sutil
        noise = np.random.normal(0, 0.005, len(y)).astype(np.float32)
        y_noisy = y + noise
        sf.write(os.path.join(output_dir, f"{base_name}_noisy.wav"), y_noisy, 16000)

        # 5. Variación de Tono (Pitch Shift)
        y_pitch_up = librosa.effects.pitch_shift(y, sr=16000, n_steps=2)
        sf.write(os.path.join(output_dir, f"{base_name}_pitch.wav"), y_pitch_up, 16000)

    except Exception as e:
        print(f"[ERROR] Error aumentando {audio_path}: {e}", flush=True)

def augment_dataset_folder(source_dir, target_aug_dir, name="AI"):
    """
    Aumenta cualquier directorio de audio de forma simétrica.
    """
    extensions = ["*.wav", "*.mp3", "*.flac", "*.ogg"]
    audio_files = []
    for ext in extensions:
        audio_files.extend(glob.glob(os.path.join(source_dir, ext)))

    print(f"\n[INFO] Aplicando Aumentación Acústica Simétrica a {len(audio_files)} audios de {name} ('{source_dir}')...", flush=True)
    os.makedirs(target_aug_dir, exist_ok=True)

    for idx, filepath in enumerate(audio_files):
        apply_acoustic_augmentations(filepath, output_dir=target_aug_dir)
        if (idx + 1) % 25 == 0 or (idx + 1) == len(audio_files):
            print(f"   [+] Aumentados {idx + 1}/{len(audio_files)} archivos de {name}...", flush=True)

    print(f"[OK] Aumentación de {name} finalizada. Archivos guardados en '{target_aug_dir}'.", flush=True)

if __name__ == "__main__":
    print("=======================================================================", flush=True)
    print("  GENERADOR & AUMENTADOR ACÚSTICO SIMÉTRICO PARA GEARSHIELD", flush=True)
    print("=======================================================================", flush=True)
    
    # 1. Generar audios de IA
    asyncio.run(generate_diverse_ai_audio(count_target=120))

    # 2. Aumentar audios de IA (data/ai -> data/ai_augmented)
    augment_dataset_folder("data/ai", "data/ai_augmented", name="IA")

    # 3. Aumentar audios Humanos (data/human -> data/human_augmented)
    augment_dataset_folder("data/human", "data/human_augmented", name="HUMANOS (Incluye WhatsApp)")
