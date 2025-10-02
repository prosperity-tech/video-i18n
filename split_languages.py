#!/usr/bin/env python3
"""
Split multi-language MKV into individual language MP4 files.
Each output file contains: video + language-specific audio + language-specific subtitles.
"""

import os
import sys
import subprocess
from pathlib import Path

def main():
    if len(sys.argv) != 2:
        print("Usage: python split_languages.py <input_mkv>")
        print("Example: python split_languages.py out/gipfel.multi.mkv")
        sys.exit(1)
    
    input_file = Path(sys.argv[1])
    if not input_file.exists():
        print(f"Error: Input file not found: {input_file}")
        sys.exit(1)
    
    basename = input_file.stem
    outdir = Path("out/split")
    outdir.mkdir(exist_ok=True)
    
    print(f"🎬 Splitting multi-language video: {input_file}")
    print(f"📁 Output directory: {outdir}")
    
    # Language configuration
    languages = {
        "de": {"code": "deu", "audio_track": 0, "subtitle_track": 0, "name": "German"},
        "en": {"code": "eng", "audio_track": 1, "subtitle_track": 1, "name": "English"},
        "fr": {"code": "fra", "audio_track": 2, "subtitle_track": 2, "name": "French"},
        "it": {"code": "ita", "audio_track": 3, "subtitle_track": 3, "name": "Italian"},
        "pt": {"code": "por", "audio_track": 4, "subtitle_track": 4, "name": "Portuguese"},
    }
    
    # Generate individual language videos
    for lang, config in languages.items():
        print(f"\n🎬 Creating {config['name']} version...")
        
        audio_track = config["audio_track"]
        subtitle_track = config["subtitle_track"]
        lang_code = config["code"]
        
        output_file = outdir / f"{basename}.{lang}.mp4"
        
        print(f"   Audio track: {audio_track}")
        print(f"   Subtitle track: {subtitle_track}")
        print(f"   Output: {output_file}")
        
        # FFmpeg command
        cmd = [
            "ffmpeg", "-y",
            "-i", str(input_file),
            "-map", "0:v:0",                    # Video stream
            "-map", f"0:a:{audio_track}",       # Audio stream
            "-map", f"0:s:{subtitle_track}",    # Subtitle stream
            "-c:v", "copy",                     # Copy video (no re-encoding)
            "-c:a", "aac", "-b:a", "192k",      # Re-encode audio to AAC
            "-c:s", "mov_text",                 # Convert subtitles to MP4 format
            f"-metadata:s:a:0", f"language={lang_code}",
            f"-metadata:s:s:0", f"language={lang_code}",
            f"-metadata:s:s:0", f"title={lang.upper()}",
            str(output_file)
        ]
        
        try:
            subprocess.run(cmd, check=True, capture_output=True)
            print(f"✅ {config['name']} version complete: {output_file}")
        except subprocess.CalledProcessError as e:
            print(f"❌ Error creating {config['name']} version:")
            print(f"   Command: {' '.join(cmd)}")
            print(f"   Error: {e.stderr.decode()}")
            sys.exit(1)
    
    print(f"\n🎉 All language versions created!")
    print(f"📁 Check the {outdir} directory for individual MP4 files:")
    for lang, config in languages.items():
        print(f"   • {basename}.{lang}.mp4 - {config['name']} (audio + subtitles)")

if __name__ == "__main__":
    main()
