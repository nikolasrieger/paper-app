# paper-audio

Renders the reader's "Listen" narration on the Mac with [Kokoro](https://github.com/thewh1teagle/kokoro-onnx) (local, free)
and drops it into the synced PaperDaily folder, next to the summaries:

```
<PaperDaily>/fluidgen.json
<PaperDaily>/audio/fluidgen/{intro,i0,i1,…,numbers,limitations,summary,apply}.m4a + manifest.json
```

The iPhone app downloads a page's audio when you press Listen (and prefetches the next page). Pages without audio yet
are read with the best installed system voice instead.

## Setup (once)

```
./install.sh
```

Creates a venv and the model files (~350 MB) in `~/Library/Application Support/PaperDaily/audio-tool` (launchd jobs
cannot read `~/Documents`), then installs the launch agent `com.paperdaily.audio`. It runs at login, whenever the
PaperDaily folder changes (a new summary appears, from `paper_summarize.py` or OneDrive) and every 30 minutes.
Log: `~/Library/Logs/paperdaily-audio.log`. Re-run `install.sh` after editing `paper_audio.py` to deploy the change.
Remove with `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.paperdaily.audio.plist`.

## Manual use

```
.venv/bin/python paper_audio.py              # everything that needs audio (unchanged pages are skipped)
.venv/bin/python paper_audio.py fluidgen     # one paper
.venv/bin/python paper_audio.py --force      # re-render all
.venv/bin/python paper_audio.py --voice bf_emma --speed 0.95
.venv/bin/python paper_audio.py --print fluidgen   # show the text that is read (after cleaning), render nothing
```

Voices: `af_heart` (default), `af_bella`, `af_nicole`, `bf_emma`, `am_michael`, `bm_george`, …
Changing the voice or speed re-renders everything. Rendering takes about 4 minutes per paper on Apple Silicon.

Text cleaning (symbols, units, acronyms spelled letter by letter) is in `normalize()`. To say an acronym as a word
(e.g. "CLIP") add it to `SAID_AS_WORDS`; after changing the rules bump `RENDER_VERSION` so existing audio is redone.
