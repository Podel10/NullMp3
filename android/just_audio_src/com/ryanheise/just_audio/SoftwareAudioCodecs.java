package com.ryanheise.just_audio;

import androidx.media3.exoplayer.mediacodec.MediaCodecInfo;
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

/**
 * Prefer AOSP software decoders. Some vendor MP3/AAC hardware decoders
 * accept a file and then output silence.
 */
final class SoftwareAudioCodecs {
  static final MediaCodecSelector SELECTOR =
      (mimeType, requiresSecureDecoder, requiresTunnelingDecoder) -> {
        List<MediaCodecInfo> infos =
            MediaCodecSelector.DEFAULT.getDecoderInfos(
                mimeType, requiresSecureDecoder, requiresTunnelingDecoder);
        List<MediaCodecInfo> software = new ArrayList<>();
        List<MediaCodecInfo> other = new ArrayList<>();
        for (MediaCodecInfo info : infos) {
          String name = info.name.toLowerCase(Locale.US);
          if (name.startsWith("c2.android.")
              || name.startsWith("c2.google.")
              || name.startsWith("omx.google.")
              || name.contains(".sw.")) {
            software.add(info);
          } else {
            other.add(info);
          }
        }
        software.addAll(other);
        return software;
      };

  private SoftwareAudioCodecs() {}
}
