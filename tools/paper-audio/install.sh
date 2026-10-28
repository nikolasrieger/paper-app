#!/bin/zsh
# One-time setup: venv, Kokoro model files, and a launchd agent that renders audio whenever the papers folder changes.
set -e
src="${0:A:h}"
# launchd jobs are blocked by macOS from reading ~/Documents, so the runtime lives in Application Support.
dest="$HOME/Library/Application Support/PaperDaily/audio-tool"
mkdir -p "$dest/models"
cp "$src/paper_audio.py" "$src/requirements.txt" "$dest/"
for f in kokoro-v1.0.onnx voices-v1.0.bin; do
  [ -f "$dest/models/$f" ] || { [ -f "$src/models/$f" ] && cp "$src/models/$f" "$dest/models/$f"; } || curl -L -o "$dest/models/$f" "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/$f"
done
cd "$dest"
[ -d .venv ] || uv venv --python 3.12 .venv
uv pip install -q --python .venv/bin/python -r requirements.txt

plist=~/Library/LaunchAgents/com.paperdaily.audio.plist
folder=$(ls -d ~/Library/CloudStorage/OneDrive*/PaperDaily 2>/dev/null | head -1)
[ -n "$folder" ] || folder=~/Library/Mobile\ Documents/com~apple~CloudDocs/PaperDaily
cat > $plist <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.paperdaily.audio</string>
  <key>ProgramArguments</key><array>
    <string>/usr/bin/caffeinate</string>
    <string>-i</string>
    <string>$dest/.venv/bin/python</string>
    <string>$dest/paper_audio.py</string>
  </array>
  <key>EnvironmentVariables</key><dict>
    <key>PAPERDAILY_FOLDER</key><string>$folder</string>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin</string>
  </dict>
  <key>WatchPaths</key><array><string>$folder</string></array>
  <key>StartInterval</key><integer>1800</integer>
  <key>RunAtLoad</key><true/>
  <key>StandardOutPath</key><string>$HOME/Library/Logs/paperdaily-audio.log</string>
  <key>StandardErrorPath</key><string>$HOME/Library/Logs/paperdaily-audio.log</string>
</dict></plist>
PLIST
launchctl bootout gui/$(id -u) $plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) $plist
echo "Installed. Log: ~/Library/Logs/paperdaily-audio.log"
