import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_voice/models/gearshield_result.dart';

void main() {
  test('parsea la respuesta real de /analyze (modo sentence_vad)', () {
    const body = '{"audio_path":"uploads/x.wav","label":"IA","risk_zone":"ZONA_ROJA","action_required":"BLOQUEO_ALERTA_DEEPFAKE","overall_risk_ai":91.0,"max_ai_prob":91.0,"avg_ai_prob":55.0,"ai_detected_intervals":[[2.1,4.6,91.0]],"timeline":[{"start_sec":0.0,"end_sec":2.0,"prob_human":80.0,"prob_ai":20.0,"is_ai":false,"segment_id":1},{"start_sec":2.1,"end_sec":4.6,"prob_human":9.0,"prob_ai":91.0,"is_ai":true,"segment_id":2}]}';
    final r = GearShieldResult.fromJson(jsonDecode(body));
    expect(r.riskZone, 'ZONA_ROJA');
    expect(r.timeline.length, 2);
    expect(r.timeline[1].isAi, isTrue);
    expect(r.timeline[1].probAi, 91.0);
  });

  test('tolera segmentos crudos VAD con fracciones 0-1 e is_synthetic', () {
    final item = TimelineItem.fromJson({
      'start_sec': 1.0, 'end_sec': 3.0, 'prob_ai': 0.85, 'prob_human': 0.15,
      'prob_ai_percentage': 85.0, 'is_synthetic': true,
    });
    expect(item.probAi, 85.0);
    expect(item.probHuman, 15.0);
    expect(item.isAi, isTrue);
  });
}
