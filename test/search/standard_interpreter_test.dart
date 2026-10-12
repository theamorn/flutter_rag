import 'package:flutter_rag/core/bangkok_time.dart';
import 'package:flutter_rag/core/payees.dart';
import 'package:flutter_rag/search/entities.dart';
import 'package:flutter_rag/search/rules/rule_parser.dart';
import 'package:flutter_rag/search/search_plan.dart';
import 'package:flutter_rag/search/standard_interpreter.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeEntities implements EntitySource {
  FakeEntities(this.result, {this.fail = false});

  final List<ExtractedEntity> result;
  final bool fail;

  @override
  Future<List<ExtractedEntity>> extract(String text) async {
    if (fail) throw StateError('model missing');
    return result;
  }

  @override
  Future<void> close() async {}
}

final parser = RuleParser(directory: PayeeDirectory(shops: const ['7-11'], people: const ['Mom']));

void main() {
  test('passes ML Kit entities to the rules', () async {
    final interpreter = StandardInterpreter(
      entities: FakeEntities([
        ExtractedDate(9, 22, 'two weeks ago',
            instant: DateTime.utc(2026, 9, 19, 5), granularity: DateGranularity.week),
      ]),
      parser: parser,
    );
    final plan = await interpreter.interpret('payments two weeks ago');
    expect(plan.dateRange, isNotNull);
  });

  test('ML Kit failure falls back to rules only, with a note', () async {
    final interpreter = StandardInterpreter(entities: FakeEntities(const [], fail: true), parser: parser);
    final plan = await interpreter.interpret('7-11 last month');
    expect(plan, SearchPlan(shopNames: const {'7-11'}, dateRange: bangkokMonth(2026, 9)));
    expect(plan.notes.last.text, contains('rules only'));
  });
}
