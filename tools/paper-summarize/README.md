# paper-summarize

Generates PaperDaily summaries on your Mac with Claude and drops them into a folder that syncs to your phone.

```
Mac:   paper_summarize.py 2005.14165   →   <folder>/gpt-3.json   →  (iCloud Drive / OneDrive)  →   iPhone app
Queue:  list arXiv ids in <folder>/queue.txt, one per line   →   Mac --queue / --watch
```

## One-time setup

1. **Pick a folder** called `PaperDaily` inside iCloud Drive or OneDrive (any folder the Files app can open works).
2. **Install the SDK** (Python 3.9+):
   ```
   cd tools/paper-summarize
   python3 -m venv .venv && source .venv/bin/activate
   pip install -r requirements.txt
   ```
3. **Give it your Anthropic credentials**, either an API key or a login profile:
   ```
   export ANTHROPIC_API_KEY=sk-ant-...        # or:  ant auth login
   ```
4. **Tell the script where the folder is.** It looks in `~/Library/CloudStorage/OneDrive*/PaperDaily` and
   `~/Library/Mobile Documents/com~apple~CloudDocs/PaperDaily`. For anywhere else:
   ```
   export PAPERDAILY_FOLDER="$HOME/path/to/PaperDaily"      # or pass --folder each time
   ```
5. **On the iPhone:** Home → gear icon → *Choose papers folder…* and pick the same folder.
   (OneDrive: install the OneDrive app and sign in so the folder shows up in Files. In the OneDrive app you can set
   the folder to *Always keep on device* so papers also load offline from the start. The app keeps its own offline copy
   after the first sync either way.)

## Everyday use

```
./paper_summarize.py 2005.14165                  # one or more arXiv ids or URLs
./paper_summarize.py --queue                     # process the arXiv ids listed in queue.txt (one per line)
./paper_summarize.py --watch                     # keep running and process the queue every 30 s
./paper_summarize.py --list                      # what is in the folder
```

Each paper takes a few minutes and two model calls: one to write the summary from the PDF, one to fact-check every
number against the paper. Expect roughly 0.3–1 USD per paper with the default model (`--model` to change,
`--no-review` to skip the second call, `--effort` to trade depth for cost).

**Fact-check.** The second call corrects the summary against the paper (unverifiable claims are removed or reworded).
Nothing about that check is stored in the paper file or shown in the app.

**Failures.** A paper that fails is removed from the queue and logged in `queue-errors.txt` in the same folder.

## Run it in the background

`--watch` keeps working while your Mac is awake. To start it at login, save this as
`~/Library/LaunchAgents/com.paperdaily.summarize.plist` (adjust the paths and key) and run
`launchctl load ~/Library/LaunchAgents/com.paperdaily.summarize.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.paperdaily.summarize</string>
  <key>ProgramArguments</key><array>
    <string>/ABSOLUTE/PATH/TO/tools/paper-summarize/.venv/bin/python</string>
    <string>/ABSOLUTE/PATH/TO/tools/paper-summarize/paper_summarize.py</string>
    <string>--watch</string>
  </array>
  <key>EnvironmentVariables</key><dict>
    <key>ANTHROPIC_API_KEY</key><string>sk-ant-...</string>
    <key>PAPERDAILY_FOLDER</key><string>/ABSOLUTE/PATH/TO/PaperDaily</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardErrorPath</key><string>/tmp/paper-summarize.log</string>
</dict></plist>
```

## File format

One JSON file per paper, named `<id>.json`. `paper.schema.json` is the full schema and `examples/` has finished
entries (the five papers that used to ship inside the app; drop any of them into your synced folder to bring it back). Formulas are LaTeX in the subset the app's renderer supports;
several lines go in one string separated by `||`. The optional `glossary` array adds terms that are underlined in the
text and open a definition card. You can write or edit these files by hand; the app shows a clear message for any file
it cannot read and carries on with the rest.

## Testing without the API

`./paper_summarize.py --mock examples/bert.json 2005.14165` downloads only the arXiv metadata and writes a placeholder
entry, which is handy for checking the sync path end to end.
