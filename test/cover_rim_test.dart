import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nullmp3/data/cover_rim.dart';

void main() {
  test('CoverRimSequence.at walks frames by duration and loops', () {
    const red = Color(0xFFFF0000);
    const blue = Color(0xFF0000FF);
    const sequence = CoverRimSequence([
      CoverRimFrame(colors: [red], duration: Duration(milliseconds: 100)),
      CoverRimFrame(colors: [blue], duration: Duration(milliseconds: 50)),
    ]);

    expect(sequence.at(Duration.zero).single, red);
    expect(sequence.at(const Duration(milliseconds: 99)).single, red);
    expect(sequence.at(const Duration(milliseconds: 100)).single, blue);
    expect(sequence.at(const Duration(milliseconds: 149)).single, blue);
    expect(sequence.at(const Duration(milliseconds: 150)).single, red);
    expect(sequence.at(const Duration(milliseconds: 249)).single, red);
    expect(sequence.at(const Duration(milliseconds: 250)).single, blue);
  });

  test('sameRim compares by value', () {
    const a = [Color(0xFF112233), Color(0xFF445566)];
    const b = [Color(0xFF112233), Color(0xFF445566)];
    const c = [Color(0xFF112233), Color(0xFF000000)];
    expect(sameRim(a, b), isTrue);
    expect(sameRim(a, c), isFalse);
  });
}
