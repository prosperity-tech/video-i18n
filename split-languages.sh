#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <input_mkv>"
  echo "Example: $0 out/gipfel.multi.mkv"
  exit 1
fi

INPUT="$1"
BASENAME="$(basename "$INPUT")"
STEM="${BASENAME%.*}"
OUTDIR="out/split"

# Create output directory
mkdir -p "$OUTDIR"

echo "🎬 Splitting multi-language video: $INPUT"
echo "📁 Output directory: $OUTDIR"

# Language mappings
declare -A LANG_MAP=(
  ["de"]="deu"
  ["en"]="eng" 
  ["fr"]="fra"
  ["it"]="ita"
  ["pt"]="por"
)

# Audio track indices (0=original, 1=EN, 2=FR, 3=IT, 4=PT)
declare -A AUDIO_TRACKS=(
  ["de"]="0"
  ["en"]="1"
  ["fr"]="2"
  ["it"]="3"
  ["pt"]="4"
)

# Subtitle track indices (0=DE, 1=EN, 2=FR, 3=IT, 4=PT)
declare -A SUBTITLE_TRACKS=(
  ["de"]="0"
  ["en"]="1"
  ["fr"]="2"
  ["it"]="3"
  ["pt"]="4"
)

# Generate individual language videos
for lang in de en fr it pt; do
  echo ""
  echo "🎬 Creating ${lang.upper()} version..."
  
  audio_track="${AUDIO_TRACKS[$lang]}"
  subtitle_track="${SUBTITLE_TRACKS[$lang]}"
  lang_code="${LANG_MAP[$lang]}"
  
  output_file="$OUTDIR/${STEM}.${lang}.mp4"
  
  echo "   Audio track: $audio_track"
  echo "   Subtitle track: $subtitle_track"
  echo "   Output: $output_file"
  
  # FFmpeg command to extract video + specific audio + specific subtitles
  ffmpeg -y \
    -i "$INPUT" \
    -map 0:v:0 \
    -map 0:a:$audio_track \
    -map 0:s:$subtitle_track \
    -c:v copy \
    -c:a aac -b:a 192k \
    -c:s mov_text \
    -metadata:s:a:0 language="$lang_code" \
    -metadata:s:s:0 language="$lang_code" \
    -metadata:s:s:0 title="${lang.upper()}" \
    "$output_file"
  
  echo "✅ ${lang.upper()} version complete: $output_file"
done

echo ""
echo "🎉 All language versions created!"
echo "📁 Check the $OUTDIR directory for individual MP4 files:"
echo "   • ${STEM}.de.mp4 - German (original audio + subtitles)"
echo "   • ${STEM}.en.mp4 - English (dubbed audio + subtitles)"
echo "   • ${STEM}.fr.mp4 - French (dubbed audio + subtitles)"
echo "   • ${STEM}.it.mp4 - Italian (dubbed audio + subtitles)"
echo "   • ${STEM}.pt.mp4 - Portuguese (dubbed audio + subtitles)"
