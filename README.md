# Video I18n - Multilingual Video Dubbing

Automatically transcribe, translate, and dub videos with high-quality neural TTS.

## Features

- 🎤 **Speech Recognition**: Whisper transcription (German → text)
- 🌐 **Translation**: ArgosTranslate (DE → EN/FR/IT/PT)
- 🎙️ **Text-to-Speech**: Piper TTS with neural voices
- 🎬 **Video Output**: Multi-track MKV with original + 4 dubbed audio tracks + 5 subtitle tracks

## Quick Start

```bash
# Make executable and run
chmod +x local-dub.sh
./local-dub.sh your_video.mp4
```

## Output

Creates `out/your_video.multi.mkv` with:
- **6 Audio tracks**: Original + EN/FR/IT/PT dubs
- **5 Subtitle tracks**: DE/EN/FR/IT/PT

## Requirements

- macOS (uses `say` command as fallback)
- Python 3.11+
- FFmpeg
- ~2GB disk space for models

## Configuration

Edit `local-dub.sh` to customize:
- `WHISPER_MODEL`: `tiny`/`base`/`small`/`medium`/`large-v3`
- `WHISPER_DEVICE`: `cpu` or `auto`
- `LANG_SRC`: Source language (default: `de`)
- Voice names: `VOICE_EN`, `VOICE_FR`, `VOICE_IT`, `VOICE_PT`

## Models

- **Whisper**: Downloads automatically on first run
- **ArgosTranslate**: DE→EN, EN→FR/IT/PT models
- **Piper TTS**: High-quality neural voices (EN: Ryan, FR: Siwis)

## Performance

- **Base model**: ~7% real-time (CPU)
- **Large-v3**: ~3% real-time (CPU)
- **Memory**: ~2GB for large models

## Troubleshooting

- **Permission errors**: Script sets up local cache directories
- **Missing voices**: Falls back to macOS `say` command
- **Slow processing**: Use `base` model instead of `large-v3`

## Files

- `local-dub.sh` - Main setup and execution script
- `auto_dub.py` - Core dubbing logic
- `out/` - Output directory
- `piper_models/` - TTS voice models
- `argos_data/` - Translation models
