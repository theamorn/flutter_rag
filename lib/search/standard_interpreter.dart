import 'entities.dart';
import 'rules/rule_parser.dart';
import 'search_plan.dart';

/// Standard search: ML Kit entities (if available) + Dart rules. Never
/// touches Gemma.
class StandardInterpreter {
  StandardInterpreter({required this.entities, required this.parser});

  final EntitySource entities;
  final RuleParser parser;

  Future<SearchPlan> interpret(String query) async {
    List<ExtractedEntity> found;
    String? warning;
    try {
      found = await entities.extract(query);
    } catch (_) {
      found = const [];
      warning = 'English entity model unavailable; interpreted with rules only.';
    }
    final plan = parser.parse(query, entities: found);
    return warning == null
        ? plan
        : plan.copyWith(notes: [...plan.notes, PlanNote(PlanNoteKind.assumption, warning)]);
  }
}
