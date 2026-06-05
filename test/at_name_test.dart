import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/at_name.dart';

void main() {
  test('atName prefixes a real username with @', () {
    expect(atName('Sugaroro'), '@Sugaroro');
    expect(atName('emersonz'), '@emersonz');
  });

  test('atName leaves null and empty values unchanged', () {
    expect(atName(null), '');
    expect(atName(''), '');
    expect(atName('   '), '   ');
  });

  test('atName does not double-prefix an already-@ value', () {
    expect(atName('@Sugaroro'), '@Sugaroro');
  });

  test('atName leaves sentinel / system strings unchanged', () {
    expect(atName('You'), 'You');
    expect(atName('Anonymous'), 'Anonymous');
    expect(atName('???'), '???');
    expect(atName('Someone'), 'Someone');
    expect(atName('A friend'), 'A friend');
    expect(atName('A runner'), 'A runner');
    expect(atName('the leader'), 'the leader');
  });

  test('atName matches sentinels case-insensitively', () {
    expect(atName('you'), 'you');
    expect(atName('ANONYMOUS'), 'ANONYMOUS');
    expect(atName('The Leader'), 'The Leader');
    expect(atName('SOMEONE'), 'SOMEONE');
  });

  test('atName treats a real name resembling a sentinel substring normally', () {
    expect(atName('Youssef'), '@Youssef');
    expect(atName('Someones'), '@Someones');
  });
}
