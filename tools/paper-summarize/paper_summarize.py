#!/usr/bin/env python3
"""paper-summarize: turn arXiv papers into PaperDaily summaries.

    paper_summarize.py 2005.14165 1706.03762      summarise these papers
    paper_summarize.py --queue                    process queue.txt (filled from the phone's Feed tab)
    paper_summarize.py --watch                    keep processing the queue every 30 s
    paper_summarize.py --list                     show the papers in the folder

Each paper is downloaded from arXiv, sent to Claude as a PDF, written as <id>.json into the synced
folder, and then fact-checked in a second pass. The notes from that check are stored with the paper.
"""
from __future__ import annotations

import argparse
import base64
import glob
import json
import os
import re
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT_MODEL = "claude-opus-5-5"
USER_AGENT = "paper-summarize/1.0 (personal reading app)"
TOPICS = ["architectures", "language", "reasoning", "alignment", "vision", "learning", "other"]
# The app ships no papers any more; prerequisites may only point at papers already in the folder.
BUILTIN_PAPERS: dict[str, str] = {}
ARXIV_ID = re.compile(r"(\d{4}\.\d{4,5}|[a-z\-]+(?:\.[A-Z]{2})?/\d{7})(?:v\d+)?", re.IGNORECASE)


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------- folder

def find_folder(explicit: str | None) -> Path:
    candidates: list[str] = []
    if explicit:
        candidates.append(explicit)
    if os.environ.get("PAPERDAILY_FOLDER"):
        candidates.append(os.environ["PAPERDAILY_FOLDER"])
    home = str(Path.home())
    candidates += sorted(glob.glob(f"{home}/Library/CloudStorage/OneDrive*/PaperDaily"))
    candidates += sorted(glob.glob(f"{home}/OneDrive*/PaperDaily"))
    candidates.append(f"{home}/Library/Mobile Documents/com~apple~CloudDocs/PaperDaily")
    for candidate in candidates:
        path = Path(candidate).expanduser()
        if path.is_dir():
            return path
    sys.exit(
        "Could not find the PaperDaily folder.\n"
        "Create a folder called PaperDaily in iCloud Drive or OneDrive, or pass --folder /path/to/folder\n"
        "(or set PAPERDAILY_FOLDER). Choose the same folder in the app under Settings."
    )


def load_folder_papers(folder: Path) -> dict[str, dict]:
    papers = {}
    for path in sorted(folder.glob("*.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(data, dict) and "id" in data:
            papers[data["id"]] = data
    return papers


def write_json_atomic(path: Path, data: dict) -> None:
    """Write via a temp file so the sync client never uploads a half-written paper."""
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, ensure_ascii=False, indent=2)
            handle.write("\n")
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


# --------------------------------------------------------------------------- queue

def read_queue(folder: Path) -> list[str]:
    path = folder / "queue.txt"
    if not path.exists():
        return []
    ids: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        found = parse_arxiv_id(line)
        if found and found not in ids:
            ids.append(found)
    return ids


def remove_from_queue(folder: Path, arxiv_id: str) -> None:
    path = folder / "queue.txt"
    if not path.exists():
        return
    keep = [line for line in path.read_text(encoding="utf-8").splitlines() if parse_arxiv_id(line) != arxiv_id and line.strip()]
    path.write_text("".join(line + "\n" for line in keep), encoding="utf-8")


def record_error(folder: Path, arxiv_id: str, reason: str) -> None:
    with open(folder / "queue-errors.txt", "a", encoding="utf-8") as handle:
        handle.write(f"{time.strftime('%Y-%m-%d %H:%M')}  {arxiv_id}  {reason}\n")


# --------------------------------------------------------------------------- arXiv

def parse_arxiv_id(text: str) -> str | None:
    match = ARXIV_ID.search(text.strip())
    return match.group(1) if match else None


def http_get(url: str, timeout: int = 60) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def fetch_metadata(arxiv_id: str) -> dict:
    url = "https://export.arxiv.org/api/query?" + urllib.parse.urlencode({"id_list": arxiv_id})
    root = ET.fromstring(http_get(url))
    ns = {"a": "http://www.w3.org/2005/Atom"}
    entry = root.find("a:entry", ns)
    if entry is None or entry.find("a:title", ns) is None:
        raise RuntimeError(f"arXiv has no paper with id {arxiv_id}")
    clean = lambda text: re.sub(r"\s+", " ", text or "").strip()
    return {
        "title": clean(entry.findtext("a:title", namespaces=ns)),
        "authors": [clean(a.findtext("a:name", namespaces=ns)) for a in entry.findall("a:author", ns)],
        "abstract": clean(entry.findtext("a:summary", namespaces=ns)),
        "year": int((entry.findtext("a:published", namespaces=ns) or "0000")[:4]),
    }


def download_pdf(arxiv_id: str) -> bytes:
    time.sleep(3)  # arXiv asks automated clients to stay polite
    data = http_get(f"https://arxiv.org/pdf/{arxiv_id}", timeout=120)
    if not data.startswith(b"%PDF"):
        raise RuntimeError("arXiv did not return a PDF")
    if len(data) > 30 * 1024 * 1024:
        raise RuntimeError("PDF is larger than the 32 MB API limit")
    return data


# --------------------------------------------------------------------------- prompts

def known_glossary_terms() -> list[str]:
    swift = HERE.parent.parent / "Sources" / "Data" / "Glossary.swift"
    if not swift.exists():
        return []
    return re.findall(r'\.init\(term: "([^"]+)"', swift.read_text(encoding="utf-8"))


def system_prompt(known: dict[str, str]) -> str:
    example = (HERE / "examples" / "bert.json").read_text(encoding="utf-8")
    known_list = "\n".join(f"- {pid}: {title}" for pid, title in known.items()) or "(none)"
    terms = ", ".join(known_glossary_terms()) or "(none)"
    return f"""You write study summaries of research papers for PaperDaily, an iPhone reading app for technical readers
(graduate students in machine learning). The reader wants the mechanics, not an overview: equations, architecture,
training setup, hyperparameters, exact numbers, ablations and limitations. Think of a careful lecture note.

Rules:
- Every number, name and claim must come from the paper. If the paper does not state something, leave it out. Never estimate.
- Write 5 to 6 insights in the order a reader needs them (problem, core mechanism, details, training, results, analysis).
  Each body is 3 to 6 dense sentences. Prefer concrete figures with units over adjectives.
- Add a LaTeX `formula` to an insight only when an equation really carries the idea. Use plain LaTeX that SwiftMath renders:
  \\frac, \\sqrt, \\sum, \\prod, \\text{{...}}, \\mathcal, subscripts and superscripts, \\left( \\right), Greek letters.
  Use \\ldots (never \\dots), no \\begin environments, no \\label, no \\tag. Put several lines in one string separated by "||".
- `numbers`: 4 to 7 facts a practitioner wants at a glance (sizes, data, headline benchmark results, compute).
- `limitations`: honest weaknesses, from the paper and the obvious ones; mention what later work changed only if you are sure.
- `prerequisites`: ids chosen only from this list of papers the reader may already have (empty list if none apply):
{known_list}
- `glossary`: up to 6 technical terms that appear in your text and are NOT already defined in the app. Already defined: {terms}.
  Definitions are one or two sentences. Each term must appear verbatim in one of your insight bodies, summary, limitations or lesson.
- `topic` is one of: {", ".join(TOPICS)} ("learning" = training methods and reinforcement learning, "other" if nothing fits).
- `id` is a lowercase kebab-case slug of the short title. `url` is the arXiv abs link.
- Write in British or American English consistently, no marketing language, no emojis.

Here is an example of the expected style and shape (a finished entry for a different paper):

{example}
"""


def user_prompt(arxiv_id: str, meta: dict) -> str:
    return (
        f"Summarise the attached paper (arXiv:{arxiv_id}).\n"
        f"Title: {meta['title']}\nAuthors: {', '.join(meta['authors'])}\nYear: {meta['year']}\n"
        f"URL: https://arxiv.org/abs/{arxiv_id}\n\nReturn the entry as JSON."
    )


REVIEW_SYSTEM = """You are a meticulous fact-checker for study summaries of research papers.
You get the paper (PDF) and a candidate summary as JSON. For every number, hyperparameter, dataset name, benchmark
result, equation and claim in the summary, find the supporting passage in the paper and check it.
- Fix anything that is wrong or unsupported in `corrected` (keep the same structure, style and length otherwise).
- Remove claims that the paper does not support, or rewrite them to what the paper says.
- Do not add new content except corrections.
- If a statement cannot be verified from the paper, remove it or rewrite it to what the paper does say. Never keep a claim
  with a caveat, and do not add any notes, flags or comments: return only the corrected summary."""


# --------------------------------------------------------------------------- Claude

def load_schema() -> dict:
    return json.loads((HERE / "paper.schema.json").read_text(encoding="utf-8"))


def ask_claude(client, model: str, system: str, pdf_b64: str, text: str, schema: dict, effort: str) -> tuple[dict, object]:
    """One request with the PDF attached. Uses structured outputs; falls back to plain JSON if the schema is rejected."""
    import anthropic

    content = [
        {"type": "document", "source": {"type": "base64", "media_type": "application/pdf", "data": pdf_b64}},
        {"type": "text", "text": text},
    ]
    base = dict(model=model, max_tokens=32000, system=system, messages=[{"role": "user", "content": content}])

    def run(**extra):
        with client.messages.stream(**base, **extra) as stream:
            return stream.get_final_message()

    try:
        message = run(output_config={"effort": effort, "format": {"type": "json_schema", "schema": schema}})
    except anthropic.BadRequestError as error:
        if "schema" not in str(error).lower() and "output_config" not in str(error).lower():
            raise
        log("  (structured output schema was rejected; asking for plain JSON instead)")
        message = run(output_config={"effort": effort})

    if message.stop_reason == "refusal":
        raise RuntimeError("Claude declined to summarise this paper")
    if message.stop_reason == "max_tokens":
        raise RuntimeError("the response was cut off (max_tokens)")
    text_out = "".join(block.text for block in message.content if block.type == "text").strip()
    text_out = re.sub(r"^```(?:json)?\s*|\s*```$", "", text_out)
    try:
        return json.loads(text_out), message
    except json.JSONDecodeError as error:
        raise RuntimeError(f"the response was not valid JSON ({error})") from error


# --------------------------------------------------------------------------- validation

def slugify(text: str) -> str:
    return re.sub(r"-+", "-", re.sub(r"[^a-z0-9]+", "-", text.lower())).strip("-")[:60] or "paper"


def clean_formula(latex: str) -> str:
    return latex.replace("\\dots", "\\ldots").strip()


def validate(summary: dict, known_ids: set[str]) -> list[str]:
    """Returns problems; an empty list means the entry is acceptable for the app."""
    problems: list[str] = []
    schema = load_schema()

    for key in schema["required"]:
        if key not in summary and key != "glossary":   # an empty glossary is dropped before saving
            problems.append(f"missing field: {key}")
    if problems:
        return problems

    for key in ("id", "title", "shortTitle", "authors", "aboutAuthors", "venue", "url", "hook",
                "whoShouldRead", "limitations", "summary", "lesson"):
        if not isinstance(summary[key], str) or not summary[key].strip():
            problems.append(f"{key} must be a non-empty string")
    for key in ("year", "readMinutes"):
        if not isinstance(summary[key], int):
            problems.append(f"{key} must be an integer")
    if summary["topic"] not in TOPICS:
        problems.append(f"topic must be one of {TOPICS}")
    if not isinstance(summary["insights"], list) or not 4 <= len(summary["insights"]) <= 8:
        problems.append("insights must have 4 to 8 entries")
    else:
        for i, insight in enumerate(summary["insights"]):
            if len(insight.get("body", "")) < 150:
                problems.append(f"insight {i + 1} body is too short")
            for line in insight.get("formula", "").split("||") if insight.get("formula") else []:
                if line.count("{") != line.count("}"):
                    problems.append(f"insight {i + 1} formula has unbalanced braces")
                if "\\begin" in line or "\\dots" in line:
                    problems.append(f"insight {i + 1} formula uses an unsupported command")
    if not isinstance(summary["numbers"], list) or len(summary["numbers"]) < 3:
        problems.append("numbers must have at least 3 entries")
    for pid in summary["prerequisites"]:
        if pid not in known_ids:
            problems.append(f"unknown prerequisite: {pid}")
    return problems


def finalize(summary: dict, arxiv_id: str, meta: dict, known_ids: set[str]) -> dict:
    summary = dict(summary)
    summary["id"] = slugify(summary.get("id") or summary.get("shortTitle") or meta["title"])
    summary["url"] = f"https://arxiv.org/abs/{arxiv_id}"
    summary["arxivID"] = arxiv_id
    summary["year"] = summary.get("year") or meta["year"]
    summary["prerequisites"] = [p for p in summary.get("prerequisites", []) if p in known_ids and p != summary["id"]]
    words = sum(len(i["body"].split()) for i in summary["insights"]) + len(summary["summary"].split()) + len(summary["limitations"].split())
    summary["readMinutes"] = max(3, round(words / 190))
    for insight in summary["insights"]:
        if insight.get("formula"):
            insight["formula"] = clean_formula(insight["formula"])
        elif "formula" in insight:
            del insight["formula"]
    for entry in summary.get("glossary", []):
        if entry.get("formula"):
            entry["formula"] = clean_formula(entry["formula"])
        else:
            entry.pop("formula", None)
        if not entry.get("aliases"):
            entry.pop("aliases", None)
    if not summary.get("glossary"):
        summary.pop("glossary", None)
    return summary


# --------------------------------------------------------------------------- pipeline

def summarise(arxiv_id: str, folder: Path, args, client) -> Path:
    existing = load_folder_papers(folder)
    for data in existing.values():
        if data.get("arxivID") == arxiv_id and not args.force:
            log(f"{arxiv_id}: already summarised as {data['id']} (use --force to redo)")
            return folder / f"{data['id']}.json"

    log(f"{arxiv_id}: fetching metadata")
    meta = fetch_metadata(arxiv_id)
    log(f"  {meta['title']}")
    known = dict(BUILTIN_PAPERS)
    known.update({pid: d.get("title", pid) for pid, d in existing.items()})
    known_ids = set(known)

    if args.mock:
        summary = json.loads(Path(args.mock).read_text(encoding="utf-8"))
        summary["id"] = f"mock-{arxiv_id.replace('/', '-')}"
        summary["title"] = f"[mock] {meta['title']}"
        summary["shortTitle"] = f"Mock {arxiv_id}"
    else:
        log("  downloading the PDF")
        pdf_b64 = base64.standard_b64encode(download_pdf(arxiv_id)).decode("ascii")
        schema = load_schema()
        log(f"  summarising with {args.model} (this takes a few minutes)")
        summary, message = ask_claude(client, args.model, system_prompt(known), pdf_b64, user_prompt(arxiv_id, meta), schema, args.effort)
        log(f"  tokens: {message.usage.input_tokens} in, {message.usage.output_tokens} out")

        if not args.no_review:
            log("  fact-checking against the paper")
            review_schema = {
                "type": "object", "additionalProperties": False,
                "required": ["corrected"],
                "properties": {"corrected": schema},
            }
            prompt = "Candidate summary:\n\n" + json.dumps(summary, ensure_ascii=False, indent=2)
            reviewed, message = ask_claude(client, args.model, REVIEW_SYSTEM, pdf_b64, prompt, review_schema, args.effort)
            log(f"  tokens: {message.usage.input_tokens} in, {message.usage.output_tokens} out")
            summary = reviewed["corrected"]

    summary = finalize(summary, arxiv_id, meta, known_ids)
    problems = validate(summary, known_ids)
    if problems:
        raise RuntimeError("the generated entry is invalid: " + "; ".join(problems))

    target = folder / f"{summary['id']}.json"
    write_json_atomic(target, summary)
    log(f"  wrote {target.name}")
    return target


def process_ids(ids: list[str], folder: Path, args, client, from_queue: bool) -> int:
    failures = 0
    for arxiv_id in ids:
        try:
            summarise(arxiv_id, folder, args, client)
            if from_queue:
                remove_from_queue(folder, arxiv_id)
        except Exception as error:  # noqa: BLE001 - report and continue with the next paper
            failures += 1
            log(f"{arxiv_id}: FAILED: {error}")
            if from_queue:
                record_error(folder, arxiv_id, str(error))
                remove_from_queue(folder, arxiv_id)
    return failures


def list_papers(folder: Path) -> None:
    for pid, data in load_folder_papers(folder).items():
        print(f"{pid:40} {data.get('year', '')}  {data.get('title', '')}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("papers", nargs="*", help="arXiv ids or URLs")
    parser.add_argument("--folder", help="synced PaperDaily folder (default: auto-detect iCloud Drive / OneDrive)")
    parser.add_argument("--queue", action="store_true", help="process queue.txt once")
    parser.add_argument("--watch", action="store_true", help="process the queue every 30 seconds")
    parser.add_argument("--list", action="store_true", help="list papers in the folder")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--effort", default="high", choices=["low", "medium", "high", "xhigh", "max"])
    parser.add_argument("--no-review", action="store_true", help="skip the fact-check pass")
    parser.add_argument("--force", action="store_true", help="redo papers that already have a summary")
    parser.add_argument("--mock", metavar="JSON", help="testing: use this JSON instead of calling Claude")
    args = parser.parse_args()

    folder = find_folder(args.folder)
    log(f"folder: {folder}")

    if args.list:
        list_papers(folder)
        return 0
    if not (args.papers or args.queue or args.watch):
        parser.print_help()
        return 2

    client = None
    if not args.mock:
        try:
            import anthropic
        except ImportError:
            sys.exit("Install the SDK first:  pip install -r requirements.txt")
        client = anthropic.Anthropic()  # ANTHROPIC_API_KEY, or the profile from `ant auth login`

    ids = []
    for item in args.papers:
        found = parse_arxiv_id(item)
        if not found:
            log(f"not an arXiv id: {item}")
            return 2
        ids.append(found)
    failures = process_ids(ids, folder, args, client, from_queue=False) if ids else 0

    if args.queue or args.watch:
        while True:
            queued = read_queue(folder)
            if queued:
                log(f"queue: {len(queued)} paper(s)")
                failures += process_ids(queued, folder, args, client, from_queue=True)
            if not args.watch:
                break
            time.sleep(30)
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(130)
