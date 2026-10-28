# PaperDaily

An iPhone reading companion for research papers, with guided summaries, audio, highlights, and notes.

Good papers deserve more than an ever-growing reading list. PaperDaily makes it easier to understand a paper in small sessions and revisit what matters.

- Read summaries with equations, glossary terms, and source links.
- Listen with system speech or locally generated narration.
- Sync paper JSON files through a folder you choose in Files, with an offline cache.

Requires **iOS 17+** and Xcode to build. Open `PaperDaily.xcodeproj`, select your signing team and a unique bundle ID for your device, then run. `project.yml` is the XcodeGen source for regenerating the project.

In the app’s settings, choose a papers folder. Start with JSON files from [examples](tools/paper-summarize/examples), or use the Mac tools:

- [paper-summarize](tools/paper-summarize): generate summaries from arXiv PDFs using Anthropic’s API (sends PDFs to Anthropic; API usage is billed).
- [paper-audio](tools/paper-audio): generate narration locally with Kokoro.
