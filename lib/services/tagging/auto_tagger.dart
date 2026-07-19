/// Rule-based auto-tagging for lexicon entries.
///
/// Produces a small, consistent set of English tags in four families:
///   • register  — everyday / formal / informal / literary / slang / vulgar / dated
///   • type      — idiom / phrasal-verb / proverb / proper-noun / abbreviation / affix
///   • variant   — british / american
///   • domain    — law / medicine / technology / business / … (only when there is
///                 real evidence in the note or the definition)
///
/// Register/type/variant and explicit domains are read from the "note" field
/// (which already carries labels like "Formal (legal, BrE)"); a conservative
/// keyword pass over the English word + definition adds a domain for general
/// vocabulary only when a clear signal is present. Everything is high-precision
/// on purpose — a card with no clear domain simply keeps its register/type tags.
library;

final _parenRe = RegExp(r'\(([^)]+)\)');

String? _register(String noteHead) {
  final h = noteHead.toLowerCase();
  if (h.contains('vulgar')) return 'vulgar';
  if (h.contains('slang')) return 'slang';
  if (h.contains('informal')) return 'informal';
  if (h.contains('literary')) return 'literary';
  if (h.contains('dated')) return 'dated';
  if (h.contains('formal')) return 'formal';
  if (h.contains('neutral') || h.contains('everyday')) return 'everyday';
  return null;
}

List<String> _typeTags(String head, String note) {
  final n = note.toLowerCase();
  final out = <String>[];
  if (n.contains('idiom')) out.add('idiom');
  if (n.contains('phrasal verb')) out.add('phrasal-verb');
  if (n.contains('proverb')) out.add('proverb');
  if (n.contains('proper noun')) out.add('proper-noun');
  final t = head.trim();
  if (t.startsWith('-') || t.endsWith('-')) out.add('affix');
  final core = t.replaceAll(_parenRe, '').trim();
  if (RegExp(r'^[A-Z0-9&/\.]{2,}$').hasMatch(core) &&
      RegExp(r'[A-Z].*[A-Z]').hasMatch(core)) {
    out.add('abbreviation');
  }
  return out;
}

List<String> _variant(String noteHead) {
  final out = <String>[];
  final tokens = <String>[];
  for (final m in _parenRe.allMatches(noteHead)) {
    tokens.addAll(m.group(1)!.toLowerCase().split(RegExp(r'[,\s/]+')));
  }
  if (tokens.contains('bre') || tokens.contains('british')) out.add('british');
  if (tokens.contains('ame') || tokens.contains('american')) {
    out.add('american');
  }
  return out;
}

const _domainMap = {
  'technical': 'technology',
  'computing': 'technology',
  'architecture': 'technology',
  'legal': 'law',
  'medical': 'medicine',
  'geography': 'geography',
  'astronomy': 'science',
  'linguistics': 'science',
  'academic': 'academia',
  'finance': 'business',
  'commerce': 'business',
  'business': 'business',
  'insurance': 'business',
  'workplace': 'work',
  'industry': 'business',
  'religious': 'religion',
  'aviation': 'aviation',
  'military': 'military',
  'sport': 'sport',
  'nautical': 'nautical',
  'music': 'arts',
  'art': 'arts',
  'historical': 'history',
  'politics': 'politics',
  'cooking': 'food',
  'journalism': 'media',
};

const _topicKw = <String, List<String>>{
  'law': ['court', 'judge', 'lawsuit', 'plaintiff', 'defendant', 'verdict', 'statute', 'attorney', 'litigation', 'prosecut', 'jury', 'plead', 'liable', 'warrant', 'tribunal', 'bail'],
  'medicine': ['disease', 'illness', 'patient', 'symptom', 'diagnos', 'surgery', 'hospital', 'therapy', 'infection', 'tumour', 'tumor', 'vaccine', 'chronic', 'clinic'],
  'technology': ['computer', 'software', 'hardware', 'internet', 'digital', 'network', 'algorithm', 'server', 'circuit', 'electron'],
  'business': ['company', 'market', 'profit', 'invest', 'economy', 'economic', 'revenue', 'budget', 'shares', 'corporate'],
  'military': ['soldier', 'weapon', 'troop', 'combat', 'battle', 'artillery', 'warfare', 'ammunition', 'siege'],
  'aviation': ['aircraft', 'flight', 'pilot', 'airline', 'cockpit', 'fuselage', 'runway'],
  'nautical': ['sailing', 'nautical', 'harbour', 'harbor', 'vessel', 'naval', 'anchor'],
  'religion': ['prayer', 'church', 'sacred', 'worship', 'biblical', 'spiritual', 'divine'],
  'arts': ['music', 'painting', 'poetry', 'sculpture', 'melody', 'symphony', 'ballet'],
  'politics': ['election', 'parliament', 'democracy', 'minister', 'senate', 'diplomat', 'referendum'],
  'food': ['cooking', 'recipe', 'cuisine', 'flavour', 'flavor', 'seasoning'],
  'nature': ['animal', 'plant', 'forest', 'wildlife', 'insect', 'mammal'],
  'emotions': ['emotion', 'anxiety', 'grief', 'psycholog', 'depress', 'temperament'],
};

String? _inferTopic(String english, String def, String pl) {
  final s = '$english $def $pl'.toLowerCase();
  String? best;
  int bestN = 0;
  _topicKw.forEach((topic, kws) {
    int n = 0;
    for (final k in kws) {
      if (s.contains(k)) n++;
    }
    if (n > bestN) {
      bestN = n;
      best = topic;
    }
  });
  return bestN >= 1 ? best : null;
}

/// Compute the auto-tags for a single entry. Returns 1–4 tags (never empty:
/// falls back to `everyday` when nothing else is inferable).
List<String> computeTags({
  required String english,
  String polish = '',
  String? definition,
  String? note,
}) {
  final n = note ?? '';
  final head = n.split('.').first;
  final out = <String>{};

  final r = _register(head);
  if (r != null) out.add(r);
  out.addAll(_typeTags(english, n));
  out.addAll(_variant(head));

  String? dom;
  for (final m in _parenRe.allMatches(head)) {
    for (final tok in m.group(1)!.toLowerCase().split(RegExp(r'[,\s/]+'))) {
      if (_domainMap.containsKey(tok)) {
        dom = _domainMap[tok];
        break;
      }
    }
    if (dom != null) break;
  }
  dom ??= _inferTopic(english, definition ?? '', polish);
  if (dom != null) out.add(dom);

  if (out.isEmpty) out.add('everyday');
  return out.toList();
}

/// Merge freshly computed [computed] tags into an entry's existing tag string,
/// preserving the user's manual tags and their order, and de-duplicating
/// case-insensitively. Tags are stored semicolon-separated (matching the card
/// editor). Returns the new tag string.
String mergeTags(String existing, List<String> computed) {
  final result = <String>[];
  final seen = <String>{};
  void add(String tag) {
    final t = tag.trim();
    if (t.isEmpty) return;
    final key = t.toLowerCase();
    if (seen.add(key)) result.add(t);
  }

  for (final t in existing.split(';')) {
    add(t);
  }
  for (final t in computed) {
    add(t);
  }
  return result.join('; ');
}
