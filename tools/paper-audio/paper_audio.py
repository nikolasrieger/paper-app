#!/usr/bin/env python3
"""Renders the PaperDaily reader's "Listen" audio on the Mac with Kokoro (local, free).

For every <id>.json in the papers folder it writes   <folder>/audio/<id>/<page>.m4a   (one file per reader page)
and   <folder>/audio/<id>/manifest.json.  Pages whose text, voice or speed did not change are skipped, so it is safe
to run as often as you like. Audio of papers that were deleted from the folder is removed.

    ./paper_audio.py                  # all papers that need audio
    ./paper_audio.py fluidgen         # only these ids
    ./paper_audio.py --force          # re-render everything
    ./paper_audio.py --voice bf_emma --speed 0.95
    ./paper_audio.py --print fluidgen # show the text that would be read, render nothing
"""
import argparse, fcntl, glob, hashlib, json, os, re, shutil, subprocess, sys, tempfile, time
from pathlib import Path

HERE = Path(__file__).resolve().parent
RENDER_VERSION = 1   # bump to re-render everything after changing the text rules below
DEFAULT_VOICE = "af_heart"
DEFAULT_SPEED = 1.0


# ---------------------------------------------------------------- folder

def find_folder(arg):
    if arg:
        return Path(arg).expanduser()
    if os.environ.get("PAPERDAILY_FOLDER"):
        return Path(os.environ["PAPERDAILY_FOLDER"]).expanduser()
    home = Path.home()
    for pattern in ("Library/CloudStorage/OneDrive*/PaperDaily", "Library/Mobile Documents/com~apple~CloudDocs/PaperDaily"):
        hits = sorted(glob.glob(str(home / pattern)))
        if hits:
            return Path(hits[0])
    sys.exit("Could not find the PaperDaily folder. Set PAPERDAILY_FOLDER or pass --folder.")


# ---------------------------------------------------------------- text

def page_keys(paper):
    return ["intro"] + [f"i{i}" for i in range(len(paper["insights"]))] + ["numbers", "limitations", "summary", "apply"]


def raw_text(paper, key):
    """Mirrors Paper.spoken(for:) in the app (Sources/Models/PaperPages.swift)."""
    ins = paper["insights"]
    if key == "intro":
        return f'{paper["title"]}. {paper["hook"]} This paper has {len(ins)} key insights.'
    if key.startswith("i"):
        i = int(key[1:])
        return f'Insight {i + 1}. {ins[i]["headline"]}. {ins[i]["body"]}'
    if key == "numbers":
        return "By the numbers. " + " ".join(f'{n["label"]}: {n["value"]}.' for n in paper["numbers"])
    if key == "limitations":
        return f'Limitations. {paper["limitations"]}'
    if key == "summary":
        return f'In a nutshell. {paper["summary"]}'
    if key == "apply":
        return f'Takeaway. {paper["lesson"]}'
    raise KeyError(key)


# Acronyms that are said as words rather than spelled out.
SAID_AS_WORDS = {
    "CLIP", "LIDAR", "RAG", "BLEU", "GAN", "GANS", "SAM", "NASA", "RAM", "BERT", "GPT", "LORA", "ROUGE", "SLAM",
    "SOTA", "PACE", "SCENE", "TRUE", "FALSE", "AI", "OK", "VR", "AR", "LLAMA", "MOE", "ADAM", "ADAMW", "SIGLIP",
    "NERF", "ELO", "BIT", "YOLO", "DINO", "LAION", "COCO", "MAE", "DDPM", "DDIM", "RLHF",
}
# Spoken forms that a letter-by-letter rule would get wrong.
REPLACEMENTS = [
    (r"\bet al\.?", "and colleagues"),
    (r"\be\.g\.", "for example"),
    (r"\bi\.e\.", "that is"),
    (r"\bvs\.?(?=\s)", "versus"),
    (r"\bw/o\b", "without"),
    (r"\bw/\b", "with"),
    (r"\bGPUs\b", "G P Us"),
    (r"\bRLHF\b", "R L H F"),
    (r"\bDDPM\b", "D D P M"),
    (r"\bDDIM\b", "D D I M"),
    (r"\bMAE\b", "M A E"),
    (r"\b3D\b", "three D"),
    (r"\b2D\b", "two D"),
    (r"\b4D\b", "four D"),
    (r"\bRL\b", "R L"),
]


def spell_acronyms(text):
    def sub(m):
        word, plural = m.group(1), m.group(2) or ""
        if word in SAID_AS_WORDS:
            return m.group(0)
        return " ".join(word) + ("'s" if plural else "")
    # 2-6 capital letters, optional plural s, not part of a longer mixed-case token.
    return re.sub(r"(?<![\w'])([A-Z]{2,6})(s?)(?![\w])", sub, text)


def normalize(text):
    t = text
    t = re.sub(r"https?://\S+", "", t)
    t = re.sub(r"[*_`]{1,3}", "", t)                      # markdown emphasis
    t = re.sub(r"\$([^$]*)\$", r"\1", t)                  # inline LaTeX delimiters
    for pat, rep in REPLACEMENTS:
        t = re.sub(pat, rep, t)
    t = re.sub(r"(\d)\s*[–—-]\s*(\d)", r"\1 to \2", t)   # ranges like 3-5
    t = re.sub(r"(?<=\d)\s*%", " percent", t)
    t = t.replace("%", " percent")
    t = re.sub(r"(\d(?:\.\d+)?)\s*[x×](?![\w])", r"\1 times", t)
    t = re.sub(r"(\d(?:\.\d+)?)B\b", r"\1 billion", t)
    t = re.sub(r"(\d(?:\.\d+)?)M\b", r"\1 million", t)
    t = re.sub(r"(\d(?:\.\d+)?)K\b", r"\1 thousand", t)
    t = re.sub(r"(\d),(\d{3})", r"\1\2", t)               # 1,000 -> 1000
    t = re.sub(r"≥|>=", " at least ", t)
    t = re.sub(r"≤|<=", " at most ", t)
    t = re.sub(r"(?<=\s)<(?=\s*\d)", " less than ", t)
    t = re.sub(r"(?<=\s)>(?=\s*\d)", " more than ", t)
    t = re.sub(r"\s*=\s*", " equals ", t)
    t = re.sub(r"\[\s*(-?[\d.]+)\s*,\s*(-?[\d.]+)\s*\]", r"\1 to \2", t)   # [0,1]
    t = re.sub(r"\s\+\s|(?<=\w)\+(?=\w)", " plus ", t)
    t = re.sub(r"(?<=\d)\+", " plus", t)
    t = re.sub(r"\s\^\s*-?|\^-", " to the power of minus " , t) if "^-" in t else t.replace("^", " to the power of ")
    t = re.sub(r"\s[-−]\s(?=[\w(])", " minus ", t)
    t = re.sub(r"(?<=[A-Za-z0-9])/(?=[A-Za-z0-9])", " slash ", t)
    t = re.sub(r"→|->", " to ", t)
    t = re.sub(r"±", " plus or minus ", t)
    t = re.sub(r"[\[\]{}|^&<>~#@\\]", " ", t)
    t = spell_acronyms(t)
    t = re.sub(r"\s*\(\s*\)", "", t)
    t = re.sub(r"\s+", " ", t)
    t = re.sub(r"\s+([.,;:!?])", r"\1", t)
    return t.strip()


def fingerprint(text, voice, speed):
    return hashlib.sha256(f"{RENDER_VERSION}|{voice}|{speed}|{text}".encode()).hexdigest()[:16]


# ---------------------------------------------------------------- rendering

class Renderer:
    def __init__(self, voice, speed):
        import numpy as np, soundfile as sf
        from kokoro_onnx import Kokoro
        models = HERE / "models"
        self.np, self.sf = np, sf
        self.kokoro = Kokoro(str(models / "kokoro-v1.0.onnx"), str(models / "voices-v1.0.bin"))
        self.voice, self.speed = voice, speed

    def render(self, text, dest: Path):
        samples, rate = self.kokoro.create(text, voice=self.voice, speed=self.speed, lang="en-us")
        dest.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory() as tmp:
            wav = Path(tmp) / "p.wav"
            self.sf.write(wav, samples, rate)
            part = dest.with_name("." + dest.name + ".part")
            subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(wav), "-ac", "1", "-c:a", "aac", "-b:a", "64k",
                            "-movflags", "+faststart", "-f", "ipod", str(part)], check=True)
            os.replace(part, dest)   # appears in one step, so the cloud client never uploads half a file
        return len(samples) / rate


def write_json_atomic(path: Path, obj):
    part = path.with_name("." + path.name + ".part")
    part.write_text(json.dumps(obj, indent=1))
    os.replace(part, path)


def process(folder, ids, voice, speed, force):
    audio_root = folder / "audio"
    papers = {}
    for f in sorted(folder.glob("*.json")):
        if f.name.startswith("."):
            continue
        try:
            d = json.loads(f.read_text())
            papers[d.get("id", f.stem)] = d
        except Exception as e:   # half-synced or hand-edited file: skip it, try again next run
            print(f"skip {f.name}: {e}")
    todo = [i for i in papers if not ids or i in ids]
    renderer = None
    rendered = 0

    for pid in todo:
        paper = papers[pid]
        out = audio_root / pid
        manifest_path = out / "manifest.json"
        try:
            old = json.loads(manifest_path.read_text()).get("pages", {})
        except Exception:
            old = {}
        pages, jobs = {}, []
        for key in page_keys(paper):
            text = normalize(raw_text(paper, key))
            fp = fingerprint(text, voice, speed)
            pages[key] = fp
            if force or old.get(key) != fp or not (out / f"{key}.m4a").exists():
                jobs.append((key, text))
        if not jobs:
            continue
        renderer = renderer or Renderer(voice, speed)
        t0, secs = time.time(), 0.0
        for key, text in jobs:
            secs += renderer.render(text, out / f"{key}.m4a")
        # drop pages that no longer exist (the insight count changed)
        for f in out.glob("*.m4a"):
            if f.stem not in pages:
                f.unlink()
        write_json_atomic(manifest_path, {"voice": voice, "speed": speed, "pages": pages})
        rendered += 1
        print(f"{pid}: {len(jobs)} page(s), {secs / 60:.1f} min of audio in {time.time() - t0:.0f}s")

    # Remove audio of papers that are gone (only on a full run).
    if not ids and audio_root.is_dir():
        for d in audio_root.iterdir():
            if d.is_dir() and d.name not in papers:
                shutil.rmtree(d, ignore_errors=True)
                print(f"removed audio of deleted paper {d.name}")
    if not rendered:
        print("audio is up to date")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("ids", nargs="*", help="paper ids (default: all)")
    ap.add_argument("--folder")
    ap.add_argument("--voice", default=DEFAULT_VOICE)
    ap.add_argument("--speed", type=float, default=DEFAULT_SPEED)
    ap.add_argument("--force", action="store_true", help="re-render even if unchanged")
    ap.add_argument("--print", action="store_true", dest="show", help="print the text that would be read and exit")
    args = ap.parse_args()
    folder = find_folder(args.folder)

    if args.show:
        for pid in args.ids:
            paper = json.loads((folder / f"{pid}.json").read_text())
            for key in page_keys(paper):
                print(f"[{key}] {normalize(raw_text(paper, key))}\n")
        return

    lock_dir = Path.home() / "Library/Application Support/PaperDaily"
    lock_dir.mkdir(parents=True, exist_ok=True)
    lock = open(lock_dir / "audio.lock", "w")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print("another run is in progress")
        return
    process(folder, set(args.ids), args.voice, args.speed, args.force)


if __name__ == "__main__":
    main()
