import 'package:flutter_test/flutter_test.dart';
import 'package:nullmp3/data/web_audio.dart';

void main() {
  test('parseWebAudioUrl ignores youtube links', () {
    expect(parseWebAudioUrl('https://www.youtube.com/watch?v=dQw4w9WgXcQ'), isNull);
    expect(parseWebAudioUrl('https://youtu.be/dQw4w9WgXcQ'), isNull);
    expect(parseWebAudioUrl('https://www.youtube.com/shorts/dQw4w9WgXcQ?feature=share'), isNull);
    expect(parseWebAudioUrl('https://music.youtube.com/watch?v=dQw4w9WgXcQ&list=PLabc'), isNull);
    expect(
      parseWebAudioUrl('https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf'),
      isNull,
    );
  });

  test('parseWebAudioUrl reads soundcloud tracks and sets', () {
    expect(
      parseWebAudioUrl('https://soundcloud.com/artist/track-name')?.kind,
      WebAudioKind.soundcloud,
    );
    expect(
      parseWebAudioUrl('https://on.soundcloud.com/abc123')?.kind,
      WebAudioKind.soundcloud,
    );
    expect(
      parseWebAudioUrl('//soundcloud.com/forss/flickermood')?.kind,
      WebAudioKind.soundcloud,
    );
    expect(
      parseWebAudioUrl('слушай https://soundcloud.com/forss/flickermood вот')?.kind,
      WebAudioKind.soundcloud,
    );
    expect(parseWebAudioUrl('https://soundcloud.com/'), isNull);
    expect(parseWebAudioUrl('not a url'), isNull);
    expect(parseWebAudioUrl('phonk drift'), isNull);
  });
}
