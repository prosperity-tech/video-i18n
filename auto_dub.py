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

inp, stem, model_name, device, src_lang, vEN, vFR, vIT, vPT = sys.argv[1:10]
outdir = Path("out"); outdir.mkdir(exist_ok=True)
segments_dir = Path("segments"); segments_dir.mkdir(exist_ok=True)

print(f"ARGOS_PACKAGES_DIR = {os.environ.get('ARGOS_PACKAGES_DIR')}")
print(f"XDG_DATA_HOME = {os.environ.get('XDG_DATA_HOME')}")
print(f"XDG_CACHE_HOME = {os.environ.get('XDG_CACHE_HOME')}")
print(f"Input video: {inp}")
print(f"Source language: {src_lang}")
print(f"Target languages: en, fr, it, pt")

print(f"Loading Whisper: {model_name}")
print("⏳ Loading Whisper model (this may take a moment)...")
start_time = time.time()
model = WhisperModel(model_name, device=device, compute_type="int8")
load_time = time.time() - start_time
print(f"✅ Whisper model loaded successfully ({load_time:.1f}s)")

print(f"🎤 Starting transcription of {inp}...")
print(f"   Language: {src_lang}")
print(f"   Device: {device}")
print("⏳ Transcribing audio (this may take several minutes)...")
transcribe_start = time.time()
segments, info = model.transcribe(inp, language=src_lang, task="transcribe", vad_filter=True)
print("⏳ Converting segments to list...")
segments = list(segments)
transcribe_time = time.time() - transcribe_start
print(f"✅ Transcription complete! ({transcribe_time:.1f}s)")
print(f"   Language detected: {info.language}")
print(f"   Duration: {info.duration:.1f}s")
print(f"   Segments found: {len(segments)}")

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
print("📝 Creating German subtitles...")
de_subs = to_srt(segments)
write_srt(de_subs, outdir / f"{stem}.de.srt")
print(f"✅ German subtitles saved: {outdir / f'{stem}.de.srt'}")

# Translators
print("🌐 Setting up translation models...")
print("⏳ Getting installed languages...")
installed = artrans.get_installed_languages()
print(f"✅ Installed languages: {[l.code for l in installed]}")

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
print("🔄 Starting translation process...")
for tgt in targets:
    print(f"⏳ Translating to {tgt.upper()}...")
    tr = translator(src_lang, tgt)
    tgt_subs = []
    for i, s in enumerate(segments, start=1):
        if i % 10 == 0:  # Progress indicator every 10 segments
            print(f"   Progress: {i}/{len(segments)} segments")
        ttxt = tr.translate(s.text.strip())
        tgt_subs.append(srt.Subtitle(
            index=i, 
            start=timedelta(seconds=s.start), 
            end=timedelta(seconds=s.end), 
            content=ttxt
        ))
    write_srt(tgt_subs, outdir / f"{stem}.{tgt}.srt")
    print(f"✅ {tgt.upper()} subtitles saved: {outdir / f'{stem}.{tgt}.srt'}")

print("✅ All subtitle files ready!")

def say_to_aiff(text, voice, out_path):
    cmd = ["say", "-v", voice, "-o", str(out_path), text]
    subprocess.run(cmd, check=True)

def build_vo(lang_code, voice):
    print(f"🎙️  Generating TTS for {lang_code.upper()} with voice '{voice}'...")
    srt_path = outdir / f"{stem}.{lang_code}.srt"
    subs = list(srt.parse(srt_path.read_text(encoding="utf-8")))
    print(f"   Found {len(subs)} subtitle segments")
    track = AudioSegment.silent(duration=0, frame_rate=48000)
    cursor_ms = 0
    for i, sub in enumerate(subs, start=1):
        if i % 5 == 0:  # Progress indicator every 5 segments
            print(f"   TTS Progress: {i}/{len(subs)} segments")
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
    print(f"   Exporting audio to {wav}...")
    track.export(wav, format="wav", parameters=["-ar","48000"])
    print(f"✅ {lang_code.upper()} audio track complete")
    return wav

print("🎵 Starting audio generation...")
vo_wavs = []
for lc, voice in targets.items():
    vo_wavs.append((lc, build_vo(lc, voice)))

print("🎬 Creating final video with all tracks...")
print("⏳ Building FFmpeg command...")
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
print(f"⏳ Running FFmpeg to create final video: {out}")
print("   This may take several minutes...")
subprocess.run(ff + maps + codec + meta + [str(out)], check=True)
print(f"🎉 SUCCESS! Final video created: {out}")
print(f"   📁 Output directory: {outdir}")
print(f"   🎬 Video file: {out}")
print(f"   🎵 Audio tracks: Original + EN/FR/IT/PT dubs")
print(f"   📝 Subtitles: DE/EN/FR/IT/PT")