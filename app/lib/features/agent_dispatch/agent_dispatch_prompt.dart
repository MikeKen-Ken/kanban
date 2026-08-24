/// Assemble the Skill and the Worker-claimed card context into a single-card prompt.
///
/// YAML frontmatter (name/description, etc.) is for the Cursor skill catalog.
/// Leaving it in the session causes the model to look for SKILL.md on disk,
/// so it is stripped before send.
String buildSkillDispatchPrompt({
  required String skillMarkdown,
  required String projectId,
  String? cardContext,
  String? batchArchitectureText,
}) {
  final skill = stripSkillFrontmatter(skillMarkdown);
  final id = projectId.trim();
  final context = cardContext?.trim();
  final architecture = batchArchitectureText?.trim();

  return '''
You must strictly follow the injected process below.
The "Skill body" section is the complete instruction; it is not a path and not a file you need to open again.
Do not search, glob, grep, or read SKILL.md / the skills directory to "confirm the process" or "locate the Skill".
Do not read agent-transcripts or any historical conversation.
After this prompt the Worker continues by injecting the full user Rules, Architecture, and this card's only context; any clause that requires reading the Skill or Architecture again is already satisfied. Kanban tools, Git, verification, and the completion protocol follow the Skill body.

# Skill body

$skill

# This invocation

projectId:$id
${context == null || context.isEmpty ? '' : '\ncardContext:\n$context'}
${architecture == null || architecture.isEmpty ? '' : '\nbatchArchitecture:\n$architecture'}
''';
}

/// Strip YAML frontmatter from the start of SKILL.md, keeping only the body.
String stripSkillFrontmatter(String markdown) {
  final text = markdown.trim();
  if (!text.startsWith('---')) return text;
  final match = RegExp(r'^---\r?\n[\s\S]*?\r?\n---\r?\n?').firstMatch(text);
  return (match == null ? text : text.substring(match.end)).trim();
}
