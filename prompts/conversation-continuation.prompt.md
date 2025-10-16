---
mode: agent
description: Summarize the conversation for easy resumption later.
tools: ['search/codebase', 'edit/editFiles', 'fetch', 'runCommands', 'runTasks', 'search', 'search/searchResults', 'runCommands/terminalLastCommand', 'runCommands/terminalSelection']
---

I would like you to summarize the current conversation I’ve been having with you.
The summary should include:
* A clear overview of the main topics discussed.
* Key questions I’ve asked and the answers you’ve provided.
* Any outstanding items, open questions, or decisions that were postponed.
* Relevant assumptions or context that would help me pick up the conversation later.

Please format the output as:
1. Summary of the conversation
2. Key decisions and takeaways
3. Open questions or next steps
4. Context needed to resume

Make it concise but complete enough for me to easily remember what was discussed and where we left off.
