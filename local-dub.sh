#!/usr/bin/env bash
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <input_video>"
  exit 1
fi

INPUT="$1"
BASENAME="$(basename "$INPUT")"
STEM="${BASENAME%.*}"

# ---- Config (override via env vars) ----
: "${WHISPER_MODEL:=large-v3}"   # tiny/base/small/medium/large-v3
: "${WHISPER_DEVICE:=cpu}"       # cpu or auto
: "${LANG_SRC:=de}"              # source language
: "${VOICE_EN:=Samantha}"        # macOS voices you have installed
: "${VOICE_FR:=Thomas}"
: "${VOICE_IT:=Alice}"
: "${VOICE_PT:=Joana}"           # or Luciana for pt-BR

# --- Force Argos to use a local, writable folder ---
# You can override by exporting ARGOS_PACKAGES_DIR=/your/path before running.
: "${ARGOS_PACKAGES_DIR:=$PWD/argos_data}"
mkdir -p "$ARGOS_PACKAGES_DIR"
chmod -R u+rwX "$ARGOS_PACKAGES_DIR"
export ARGOS_PACKAGES_DIR

# Some setups make Argos consult XDG paths; keep those local too.
: "${XDG_DATA_HOME:=$PWD/.xdg}"
mkdir -p "$XDG_DATA_HOME"
export XDG_DATA_HOME

: "${XDG_CACHE_HOME:=$PWD/.cache}"
mkdir -p "$XDG_CACHE_HOME"
export XDG_CACHE_HOME

# ---- System deps (idempotent) ----
if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

brew install python@3.11 ffmpeg pkg-config cmake protobuf

# ---- Python env ----
deactivate 2>/dev/null || true
rm -rf .venv

python3.11 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip wheel setuptools

# Exact deps (no PyAV)
pip install \
  "faster-whisper==1.0.3" \
  "argostranslate==1.9.6" \
  "sentencepiece==0.2.0" \
  "ctranslate2==4.3.1" \
  "pydub==0.25.1" \
  "srt==3.5.3"

# ---- Ensure Argos DE→EN/FR/IT/PT models (downloaded once into $ARGOS_PACKAGES_DIR) ----
python - <<'PY'
import os
import argostranslate.package as pkg, argostranslate.translate as tr

print("Using ARGOS_PACKAGES_DIR =", os.environ.get("ARGOS_PACKAGES_DIR"))

pairs=[("de","en"),("en","fr"),("en","it"),("en","pt")]
pkg.update_package_index()
available=pkg.get_available_packages()
installed=tr.get_installed_languages()

def has_pair(s,d):
    for l in installed:
        if l.code==s:
            return any(t.code==d for t in l.translations)
    return False

to_install=[]
for s,d in pairs:
    if not has_pair(s,d):
        for p in available:
            if p.from_code==s and p.to_code==d:
                to_install.append(p); break

for p in to_install:
    path=p.download()
    pkg.install_from_path(path)
print("Argos models ready.")
PY

# ---- Write auto_dub.py if missing ----
if [ ! -f auto_dub.py ]; then
  cat > auto_dub.py <<'PY'
import os, sys, subprocess, srt, time
from datetime import timedelta
from pathlib import Path
from pydub import AudioSegment
from faster_whisper import WhisperModel

# Set up ArgosTranslate environment BEFORE importing it
# This must be done before any argostranslate imports
if 'ARGOS_PACKAGES_DIR' not in os.environ:
    argos_dir = Path.cwd() / "argos_data"
    argos_dir.mkdir(exist_ok=True)
    os.environ['ARGOS_PACKAGES_DIR'] = str(argos_dir)

if 'XDG_DATA_HOME' not in os.environ:
    xdg_dir = Path.cwd() / ".xdg"
    xdg_dir.mkdir(exist_ok=True)
    os.environ['XDG_DATA_HOME'] = str(xdg_dir)

if 'XDG_CACHE_HOME' not in os.environ:
    cache_dir = Path.cwd() / ".cache"
    cache_dir.mkdir(exist_ok=True)
    os.environ['XDG_CACHE_HOME'] = str(cache_dir)

# Now import argostranslate
import argostranslate.translate as artrans

if len(sys.argv) < 10:
    print("Usage: auto_dub.py <input> <stem> <whisper_model> <device> <src_lang> <voice_en> <voice_fr> <voice_it> <voice_pt>")
    sys.exit(1)

print("ARGOS_PACKAGES_DIR =", os.environ.get("ARGOS_PACKAGES_DIR"))
print("XDG_DATA_HOME =", os.environ.get("XDG_DATA_HOME"))
print("XDG_CACHE_HOME =", os.environ.get("XDG_CACHE_HOME"))

inp, stem, model_name, device, src_lang, vEN, vFR, vIT, vPT = sys.argv[1:10]
outdir = Path("out"); outdir.mkdir(exist_ok=True)
segments_dir = Path("segments"); segments_dir.mkdir(exist_ok=True)

print(f"Loading Whisper: {model_name}")
model = WhisperModel(model_name, device=device, compute_type="int8")
segments, info = model.transcribe(inp, language=src_lang, task="transcribe", vad_filter=True)
segments = list(segments)
print(f"Language: {info.language} | Duration: {info.duration:.1f}s | Segments: {len(segments)}")

def to_srt(segs):
    return [srt.Subtitle(
        index=i, 
        start=timedelta(seconds=s.start), 
        end=timedelta(seconds=s.end), 
        content=s.text.strip()
    ) for i,s in enumerate(segs, start=1)]

def write_srt(subs, path: Path):
    path.write_text(srt.compose(subs), encoding="utf-8")

# DE subtitles
de_subs = to_srt(segments)
write_srt(de_subs, outdir / f"{stem}.de.srt")

# Translators
print("Getting installed languages...")
installed = artrans.get_installed_languages()
print(f"Installed languages: {[l.code for l in installed]}")

def translator(src, dst):
    try:
        # Try direct translation first
        src_l = next(l for l in installed if l.code == src)
        dst_l = next(l for l in installed if l.code == dst)
        return src_l.get_translation(dst_l)
    except StopIteration:
        # If direct translation not available, try through English
        if src != 'en' and dst != 'en':
            try:
                print(f"   Direct {src}->{dst} not available, using {src}->en->{dst}")
                src_l = next(l for l in installed if l.code == src)
                en_l = next(l for l in installed if l.code == 'en')
                dst_l = next(l for l in installed if l.code == dst)
                
                # Create a two-step translator
                class TwoStepTranslator:
                    def __init__(self, src_to_en, en_to_dst):
                        self.src_to_en = src_to_en
                        self.en_to_dst = en_to_dst
                    def translate(self, text):
                        en_text = self.src_to_en.translate(text)
                        return self.en_to_dst.translate(en_text)
                
                src_to_en = src_l.get_translation(en_l)
                en_to_dst = en_l.get_translation(dst_l)
                return TwoStepTranslator(src_to_en, en_to_dst)
            except StopIteration:
                pass
        
        print(f"ERROR: Translation pair {src}->{dst} not found in installed languages")
        print(f"Available languages: {[l.code for l in installed]}")
        sys.exit(1)

targets = {
    "en": vEN,
    "fr": vFR,
    "it": vIT,
    "pt": vPT,
}

# Translate segment-wise
for tgt in targets:
    tr = translator(src_lang, tgt)
    tgt_subs = []
    for i, s in enumerate(segments, start=1):
        ttxt = tr.translate(s.text.strip())
        tgt_subs.append(srt.Subtitle(
            index=i, 
            start=timedelta(seconds=s.start), 
            end=timedelta(seconds=s.end), 
            content=ttxt
        ))
    write_srt(tgt_subs, outdir / f"{stem}.{tgt}.srt")

print("SRTs ready.")

def say_to_aiff(text, voice, out_path):
    cmd = ["say", "-v", voice, "-o", str(out_path), text]
    subprocess.run(cmd, check=True)

def build_vo(lang_code, voice):
    print(f"TTS {lang_code} with {voice}…")
    srt_path = outdir / f"{stem}.{lang_code}.srt"
    subs = list(srt.parse(srt_path.read_text(encoding="utf-8")))
    track = AudioSegment.silent(duration=0, frame_rate=48000)
    cursor_ms = 0
    for i, sub in enumerate(subs, start=1):
        start_ms = int(sub.start.total_seconds()*1000)
        if start_ms > cursor_ms:
            track += AudioSegment.silent(duration=(start_ms-cursor_ms), frame_rate=48000)
            cursor_ms = start_ms
        aiff_path = segments_dir / f"{stem}.{lang_code}.{i}.aiff"
        say_to_aiff(sub.content.replace("\n"," "), voice, aiff_path)
        seg = AudioSegment.from_file(aiff_path)
        track += seg
        cursor_ms += len(seg)
    wav = outdir / f"{stem}.{lang_code}.wav"
    track.export(wav, format="wav", parameters=["-ar","48000"])
    return wav

vo_wavs = []
for lc, voice in targets.items():
    vo_wavs.append((lc, build_vo(lc, voice)))

# Final MKV
ff = ["ffmpeg","-y","-i", inp]
for _, wav in vo_wavs:
    ff += ["-i", str(wav)]
for lang in ["de","en","fr","it","pt"]:
    ff += ["-i", str(outdir / f"{stem}.{lang}.srt")]

maps = ["-map","0:v:0","-map","0:a?"]
for i in range(len(vo_wavs)):
    maps += ["-map", f"{i+1}:a:0"]
for i in range(5):
    maps += ["-map", f"{len(vo_wavs)+1 + i}:s:0"]

codec = [
    "-c:v","copy",
    "-c:a","aac","-ac","2","-b:a","192k",
    "-c:s","srt",
]

lang_map = {"de":"deu","en":"eng","fr":"fra","it":"ita","pt":"por"}
meta = []
aidx = 1
for lc,_ in vo_wavs:
    meta += [f"-metadata:s:a:{aidx}","language="+lang_map[lc],
             f"-metadata:s:a:{aidx}","title="+lc.upper()+" Dub"]
    aidx += 1
sidx = 0
for lc in ["de","en","fr","it","pt"]:
    meta += [f"-metadata:s:s:{sidx}","language="+lang_map[lc],
             f"-metadata:s:s:{sidx}","title="+lc.upper()]
    sidx += 1

out = outdir / f"{stem}.multi.mkv"
subprocess.run(ff + maps + codec + meta + [str(out)], check=True)
print(f"Done → {out}")
PY
fi

# ---- Run ----
echo "Running dubbing process..."
echo "ARGOS_PACKAGES_DIR = $ARGOS_PACKAGES_DIR"
echo "XDG_DATA_HOME = $XDG_DATA_HOME"
echo "XDG_CACHE_HOME = $XDG_CACHE_HOME"
python auto_dub.py "$INPUT" "$STEM" "$WHISPER_MODEL" "$WHISPER_DEVICE" "$LANG_SRC" "$VOICE_EN" "$VOICE_FR" "$VOICE_IT" "$VOICE_PT"

echo ""
echo "✅ All set. Output: ./out/${STEM}.multi.mkv"
echo "   • Audio tracks: Original + EN/FR/IT/PT dubs"
echo "   • Subtitles: DE/EN/FR/IT/PT"