# daccord Documentation

Documentation for daccord users, server operators, and extension creators. This content is designed to be pulled by external services (static site generators, help portals, etc.) to produce website documentation.

## Structure

```
docs/
  README.md              # This file
  index.md               # Documentation home page
  getting-started/       # First-time setup and onboarding
  messaging/             # Sending, replying, editing, and managing messages
  navigation/            # Spaces, channels, and the sidebar
  voice-and-video/       # Voice channels, video, and screen sharing
  customization/         # Themes, settings, and profiles
  administration/        # Server and space management for admins
  developer/             # Arcade extension creation and local MCP APIs
  experiences/           # Arcade host API and platform validation references
  troubleshooting/       # Common issues and solutions
```

## Conventions

- **Audience:** Keep user and administration guides accessible to non-technical users. Developer and experience reference pages may include code, APIs, and implementation details needed by creators.
- **Tone:** Friendly, concise, and direct. Second person ("you").
- **Format:** Standard Markdown with YAML front matter for metadata.
- **Front matter fields:**
  - `title` -- Page title (used in navigation and `<title>` tags)
  - `description` -- Short summary for SEO and link previews
  - `order` -- Sort order within the section (lower numbers first)
  - `section` -- Parent section slug (matches directory name)
- **Images:** Place in an `images/` subdirectory next to the markdown file. Use relative paths.
- **Links:** Use relative markdown links between pages (e.g., `../messaging/sending-messages.md`).
- **Headings:** Each page starts with an H1 matching the `title`. Use H2 and H3 for subsections. Avoid H4+.
