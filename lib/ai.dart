import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'models.dart';

class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}

/// ИИ отказался оценивать (нет человека на фото, похоже на несовершеннолетнего и т.п.).
class AiRefused implements Exception {
  final String reason;
  AiRefused(this.reason);
  @override
  String toString() => reason;
}

class _TryNextModel implements Exception {
  final String message;
  _TryNextModel(this.message);
}

/// Тон оценки: 0 — мягко, 1 — честно, 2 — без пощады.
const toneNames = ['Мягко', 'Честно', 'Без пощады'];

/// Оценка через Google Gemini.
class Ai {
  static const _base = 'https://generativelanguage.googleapis.com/v1beta';

  static const fallbackModels = [
    'gemini-flash-latest',
    'gemini-3.8-flash',
    'gemini-3.6-flash',
    'gemini-3.5-flash-lite',
  ];

  // ---------- Публичные методы ----------

  static Future<SoloResult> rateSolo({
    required String apiKey,
    required String model,
    required Kind kind,
    required int tone,
    required Uint8List photo,
  }) async {
    final parts = <Map<String, dynamic>>[
      {'text': _soloPrompt(kind, tone)},
      {'text': 'Photo of the user:'},
      _img(photo),
    ];
    final j = await _run(apiKey, model, parts);
    _checkRefused(j);
    final r = SoloResult.fromJson(j);
    if (r.categories.isEmpty && r.summary.isEmpty) throw AiException('ИИ вернул пустую оценку. Попробуй ещё раз.');
    return r;
  }

  static Future<BattleResult> rateBattle({
    required String apiKey,
    required String model,
    required Kind kind,
    required int tone,
    required Uint8List photoA,
    required Uint8List photoB,
  }) async {
    final parts = <Map<String, dynamic>>[
      {'text': _battlePrompt(kind, tone)},
      {'text': 'Photo A (the user):'},
      _img(photoA),
      {'text': 'Photo B (the opponent):'},
      _img(photoB),
    ];
    final j = await _run(apiKey, model, parts);
    _checkRefused(j);
    final r = BattleResult.fromJson(j);
    if (r.categories.isEmpty && r.verdict.isEmpty) throw AiException('ИИ вернул пустую оценку. Попробуй ещё раз.');
    return r;
  }

  /// Проверка ключа: null — всё хорошо, иначе текст ошибки.
  static Future<String?> testKey(String apiKey) async {
    if (apiKey.trim().isEmpty) return 'Вставь ключ.';
    try {
      final res = await http.get(
        Uri.parse('$_base/models?pageSize=50'),
        headers: {'x-goog-api-key': apiKey.trim()},
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) return null;
      return 'Ключ не принят: ${_errMsg(res.bodyBytes)}';
    } on TimeoutException {
      return 'Сервер не ответил. Проверь интернет.';
    } catch (_) {
      return 'Нет соединения с интернетом.';
    }
  }

  // ---------- Промпты ----------

  static const _looksCats = [
    'Кожа',
    'Волосы и причёска',
    'Глаза и брови',
    'Черты лица и пропорции',
    'Линия челюсти и подбородок',
    'Улыбка и зубы',
    'Ухоженность',
    'Телосложение и осанка',
    'Подача на фото',
  ];

  static const _styleCats = [
    'Сочетание цветов',
    'Посадка и размер',
    'Силуэт и пропорции',
    'Цельность образа',
    'Обувь',
    'Аксессуары',
    'Состояние и качество вещей',
    'Актуальность и уместность',
  ];

  static const _synergyCats = [
    'Цвета одежды и цветотип',
    'Образ и черты лица',
    'Образ и причёска',
    'Одежда и фигура',
    'Возраст и вайб',
    'Цельность: человек + одежда',
    'Подача на фото',
  ];

  static List<String> _cats(Kind k) => switch (k) {
        Kind.looks => _looksCats,
        Kind.style => _styleCats,
        Kind.synergy => _synergyCats,
      };

  static String _what(Kind k) => switch (k) {
        Kind.looks =>
          'PHYSICAL APPEARANCE: facial aesthetics, skin, hair, grooming, harmony of features, physique and posture if visible, and how the person presents themselves in the photo. Ignore clothing except where it affects grooming.',
        Kind.style =>
          'CLOTHING STYLE ONLY: the outfit, color combination, fit, silhouette, footwear, accessories, condition of the items, coherence and appropriateness. Do not rate the face or body attractiveness.',
        Kind.synergy =>
          'SYNERGY OF APPEARANCE AND CLOTHING: how well the outfit suits this particular person — their color type (skin, hair and eye contrast), face shape and features, hairstyle, body proportions, age and overall vibe. Also give separate sub-scores for appearance and style.',
      };

  static String _tone(int t) => switch (t) {
        0 => 'TONE: gentle and encouraging. Start with strengths, phrase weaknesses softly, but still be specific.',
        2 => 'TONE: brutally honest and witty, like a roast — no sugarcoating, short punchy verdict. '
            'But never humiliating, never vulgar, never about identity traits, and always followed by concrete fixes.',
        _ => 'TONE: direct and objective, like a good friend who is a professional stylist. No flattery, no cruelty.',
      };

  static String _rules(Kind kind, int tone) {
    final b = StringBuffer()
      ..writeln('You are the AI judge in the app "Mog Battle" — an honest, constructive appearance and style coach. '
          'Adults upload their own photos (and, for a battle, a photo of a friend who agreed to the battle) '
          'to get a detailed aesthetic rating and practical advice on how to improve.')
      ..writeln('WHAT TO RATE: ${_what(kind)}')
      ..writeln(_tone(tone))
      ..writeln('RULES:')
      ..writeln('- If there is no real person in a photo, or the main person in any photo looks younger than 18, '
          'set "refused": true, explain why in "refuseReason" and give no scores.')
      ..writeln('- Never treat race, ethnicity, skin color, nationality, disability or other unchangeable identity traits as flaws. '
          'Judge general aesthetics, harmony, grooming, style and presentation.')
      ..writeln('- Be specific: point to concrete visible details ("брови разной формы", "джинсы длинноваты и собираются гармошкой"), '
          'not generic phrases.')
      ..writeln('- Scores are 1.0–10.0 with one decimal. Use a realistic scale: 5–6 is average, 7 is clearly good, '
          '8+ is rare, 9+ is exceptional. Do not inflate scores to be nice.')
      ..writeln('- If a category is not visible in the photo, set its score to null and say so in the comment.')
      ..writeln('- Account for photo quality (light, angle, distance, filters). If it hurts the result, explain in "photoNote" '
          'and how to take a better photo; otherwise leave "photoNote" empty.')
      ..writeln('- Tips must be realistic, safe and actionable: haircut, skincare, beard and brows, teeth care, fitness and posture, '
          'sleep and water, clothing items, colors, fit and tailoring, accessories, photo angle and light. '
          'Each tip: what exactly to do and why it will help this person. '
          'Never recommend surgery, injections, steroids, extreme diets, "mewing", "bone smashing" or other risky methods.')
      ..writeln('- Do not use incel / looksmaxxing slang (subhuman, LTN, chad, etc.).')
      ..writeln('- Write ALL text in Russian. Address the user informally ("ты").')
      ..writeln('CATEGORIES (use exactly these names, in this order): ${_cats(kind).join('; ')}.');
    if (kind == Kind.synergy) {
      b.writeln('SUB-SCORES (use exactly these names): Внешность; Стиль; Синергия.');
    }
    return b.toString();
  }

  static String _soloPrompt(Kind kind, int tone) {
    final b = StringBuffer(_rules(kind, tone))
      ..writeln('TASK: rate the person in the photo.')
      ..writeln('"overall" — the final score. "potential" — a realistic score this person can reach in 3–6 months '
          'by following your tips.')
      ..writeln('"strengths" and "weaknesses" — 3–5 short points each. "tips" — 5–8 tips sorted by impact.')
      ..writeln('Answer with exactly one JSON object, no markdown:')
      ..writeln('{"refused":false,"refuseReason":"","overall":6.8,"potential":7.9,'
          '"summary":"2–3 sentences of overall verdict",'
          '${kind == Kind.synergy ? '"subScores":[{"name":"Внешность","score":7.0,"comment":"..."},{"name":"Стиль","score":6.0,"comment":"..."},{"name":"Синергия","score":6.5,"comment":"..."}],' : ''}'
          '"categories":[{"name":"<category>","score":7.0,"comment":"1–2 specific sentences"}],'
          '"strengths":["..."],"weaknesses":["..."],'
          '"tips":[{"title":"short title","text":"what exactly to do and why","impact":"high|medium|low"}],'
          '"photoNote":""}');
    return b.toString();
  }

  static String _battlePrompt(Kind kind, int tone) {
    final b = StringBuffer(_rules(kind, tone))
      ..writeln('TASK: a "mog battle". Photo A is the user, photo B is the opponent. Compare them category by category '
          'and decide who wins. Be fair — do not favor the user. A draw is allowed only if they are truly equal.')
      ..writeln('For each category give both scores, the winner ("a", "b" or "draw") and a comment explaining '
          'exactly WHERE and WHY one is better (name the people "ты" for A and "соперник" for B).')
      ..writeln('"aEdges" — 2–5 points where the user is better; "bEdges" — 2–5 points where the opponent is better.')
      ..writeln('"verdict" — 1–2 sentences, who mogs whom and why. '
          '"tips" — 4–7 tips for the user (A) on how to beat the opponent next time, sorted by impact.')
      ..writeln('Answer with exactly one JSON object, no markdown:')
      ..writeln('{"refused":false,"refuseReason":"",'
          '"a":{"overall":6.9,"summary":"1–2 sentences about the user"},'
          '"b":{"overall":7.3,"summary":"1–2 sentences about the opponent"},'
          '"winner":"a|b|draw","verdict":"...",'
          '"categories":[{"name":"<category>","a":7.0,"b":6.5,"winner":"a","comment":"..."}],'
          '"aEdges":["..."],"bEdges":["..."],'
          '"tips":[{"title":"short title","text":"what exactly to do and why","impact":"high|medium|low"}],'
          '"photoNote":""}');
    return b.toString();
  }

  // ---------- Запрос ----------

  static Map<String, dynamic> _img(Uint8List b) => {
        'inlineData': {'mimeType': _mime(b), 'data': base64Encode(b)},
      };

  static String _mime(Uint8List b) {
    if (b.length > 4 && b[0] == 0x89 && b[1] == 0x50) return 'image/png';
    if (b.length > 12 && b[0] == 0x52 && b[1] == 0x49 && b[8] == 0x57 && b[9] == 0x45) return 'image/webp';
    return 'image/jpeg';
  }

  static void _checkRefused(Map<String, dynamic> j) {
    if (j['refused'] == true) {
      final r = (j['refuseReason'] ?? '').toString().trim();
      throw AiRefused(r.isEmpty ? 'ИИ не стал оценивать это фото. Попробуй другое.' : r);
    }
  }

  static Future<Map<String, dynamic>> _run(String apiKey, String model, List<Map<String, dynamic>> parts) async {
    final key = apiKey.trim();
    if (key.isEmpty) throw AiException('Добавь API-ключ Gemini во вкладке «Настройки».');
    final first = model.trim().isEmpty ? fallbackModels.first : model.trim();
    final models = <String>[first, ...fallbackModels.where((m) => m != first)];
    var lastError = 'Не удалось получить ответ от ИИ.';
    for (final m in models) {
      try {
        final text = await _post(key, m, parts);
        return _parseJson(text);
      } on _TryNextModel catch (e) {
        lastError = e.message;
      }
    }
    throw AiException(lastError);
  }

  static Map<String, dynamic> _parseJson(String text) {
    final s = text.indexOf('{');
    final e = text.lastIndexOf('}');
    if (s < 0 || e <= s) throw AiException('Не удалось разобрать ответ ИИ. Попробуй ещё раз.');
    try {
      final d = jsonDecode(text.substring(s, e + 1));
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
    throw AiException('Не удалось разобрать ответ ИИ. Попробуй ещё раз.');
  }

  static Future<String> _post(String key, String model, List<Map<String, dynamic>> parts) async {
    final body = jsonEncode({
      'contents': [
        {'role': 'user', 'parts': parts},
      ],
      'generationConfig': {'responseMimeType': 'application/json', 'temperature': 0.4},
    });

    final http.Response res;
    try {
      res = await http
          .post(
            Uri.parse('$_base/models/$model:generateContent'),
            headers: {'Content-Type': 'application/json', 'x-goog-api-key': key},
            body: body,
          )
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw AiException('ИИ слишком долго отвечает. Попробуй ещё раз.');
    } catch (_) {
      throw AiException('Нет соединения с интернетом.');
    }

    final code = res.statusCode;
    if (code == 404 || code >= 500) {
      throw _TryNextModel('Модель $model недоступна ($code). Попробуй позже.');
    }
    if (code == 429) {
      throw AiException('Превышен лимит запросов Gemini. Подожди минуту и попробуй снова.');
    }
    if (code != 200) {
      final msg = _errMsg(res.bodyBytes);
      final low = msg.toLowerCase();
      if (low.contains('api key') || low.contains('api_key')) {
        throw AiException('Неверный API-ключ. Проверь его во вкладке «Настройки».');
      }
      if (code == 400 && low.contains('model')) throw _TryNextModel('Модель $model не подходит: $msg');
      throw AiException('Ошибка запроса ($code): $msg');
    }

    final Map<String, dynamic> j;
    try {
      j = Map<String, dynamic>.from(jsonDecode(utf8.decode(res.bodyBytes)) as Map);
    } catch (_) {
      throw AiException('Сервер вернул непонятный ответ.');
    }
    final cands = j['candidates'];
    if (cands is! List || cands.isEmpty) {
      final fb = j['promptFeedback'];
      final reason = fb is Map ? fb['blockReason'] : null;
      throw AiException(reason != null
          ? 'Gemini заблокировал запрос ($reason). Попробуй другое фото.'
          : 'ИИ не вернул ответ. Попробуй ещё раз.');
    }
    final cand = cands.first as Map;
    final content = cand['content'];
    final rawParts = content is Map ? content['parts'] : null;
    final text = (rawParts is List ? rawParts : const [])
        .whereType<Map>()
        .where((p) => p['thought'] != true && p['text'] is String)
        .map((p) => p['text'] as String)
        .join();
    if (text.trim().isEmpty) {
      final fr = cand['finishReason'];
      throw AiException(fr == 'SAFETY'
          ? 'Gemini отказался оценивать это фото. Попробуй другое.'
          : 'ИИ вернул пустой ответ. Попробуй ещё раз.');
    }
    return text;
  }

  static String _errMsg(List<int> bytes) {
    try {
      final j = jsonDecode(utf8.decode(bytes));
      if (j is Map && j['error'] is Map) return (j['error'] as Map)['message']?.toString() ?? 'неизвестная ошибка';
    } catch (_) {}
    return 'неизвестная ошибка';
  }
}
