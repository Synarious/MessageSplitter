# MessageSplitter

MessageSplitter is a long-form chat composer for World of Warcraft Retail. It was built for the Midnight expansion and its stricter combat and chat-messaging restrictions. The goal is to let players draft, preview, and split longer messages when addon messaging is available, while handing control back to Blizzard's native chat when restrictions apply.

## Current behavior

- Draft in a movable, resizable composer and choose Say, emote, party, raid, guild, whisper, or a joined channel.
- Split long drafts into multiple messages while respecting the 255-byte chat limit, UTF-8 character boundaries, links, and supported roleplay formatting.
- Send each part with Enter. Automatic pacing is optional; local Say, Yell, and Emote parts remain manual.
- Use Shift+Enter for a new paragraph. Paragraphs are separate messages.
- Hover the gear tab above the right edge for send, default chat, disable, settings, and close controls. The byte/part count and send status sit in an attached bottom-right badge; hover for full details or drag the badge to move the composer.
- Use `/msplit` or `/mse` to open the composer. `/mse on`, `/mse off`, and `/mse settings` manage it.
- Each submitted part stays in the draft until a matching, readable chat echo from your character arrives. Automatic pacing waits for that confirmation too. A failed send or a 10-second confirmation timeout stops sending and retains the text; there is no automatic retry.
- Use `/mse restore` to recover the unconfirmed and remaining parts of the last submission during this session. Confirmed parts are excluded. Retrying an unconfirmed part can duplicate it if its echo was delayed or unavailable; a chat echo does not guarantee every recipient saw it.

## Combat and chat lockdown

Combat lockdown and chat-messaging lockdown are related but separate. Midnight can restrict addon access to chat information and sending in encounters, challenge modes, PvP matches, and communication-restricted maps such as dungeons and raids. Restrictions can remain active after combat ends.

MessageSplitter checks combat, encounter state, `C_ChatInfo.InChatMessagingLockdown()`, and the current `C_RestrictedActions` Chat restriction state before handling native-chat capture or sending. It listens for `ADDON_RESTRICTION_STATE_CHANGED` to pause before Chat restrictions activate, with polling as a fallback. Combat and chat restrictions hide the composer while retaining the draft and remaining queue; press Enter to open Blizzard's normal chat editor. Any in-flight, unconfirmed part remains recoverable. Sending resumes only when you explicitly send again after restrictions clear.

The addon does not attempt to bypass Blizzard's protected chat path or simulate a hardware event. Its composer is an ordinary addon edit box; messages are sent through the chat API only when permitted. For commands that MessageSplitter cannot handle, use Default chat.

## Secret values

Midnight's secret-value system marks some API results as inaccessible to addon Lua during restricted states. Addons may store or pass some secret values, but cannot safely inspect them with ordinary comparisons, string matching, arithmetic, or formatting. `issecretvalue()` identifies a secret value when the client provides that API.

MessageSplitter only splits readable text authored in its own editor. Its native-chat capture path checks the chat type, target, language, and text for secret values before inspecting or importing them. If text is inaccessible, the addon avoids parsing or sending it and leaves native chat available. Optional spellcheck and roleplay-formatting integrations are treated as fallible; their errors should not prevent use of the plain draft.

Secret-value behavior and API restrictions can change between client patches. This addon does not inspect secret combat, unit, aura, or chat values. Send confirmation only compares accessible echoes against the expected channel and your character GUID, or the outgoing whisper recipient. Please report errors with the client version, restriction context, and optional chat/roleplay addons enabled.

## Future direction

The project is intended to remain a drafting and formatting aid that works within Midnight's addon security model. Future work should prioritize preserving drafts and queue position across restriction changes, clear restriction status, reliable recovery after uncertain sends, and compatibility with new Retail API versions. It should not depend on reading secret data or circumventing protected chat actions.

## Optional integrations

Total RP 3 can provide roleplay text coloring. Misspelled can provide spell checking. Both are optional; MessageSplitter should continue to work without them.

When Whisper Manager is loaded, MessageSplitter leaves native whisper activations (including chat-name clicks, the Whisper menu action, and replies) to Whisper Manager. Other chat channels still open MessageSplitter. Without Whisper Manager, whispers continue to use MessageSplitter.

## Releases

Pushes to `main`, `master`, or `dev` run tests, increment the final numeric part
of the TOC version, commit the version, create an annotated tag, and publish with
BigWigsMods/packager. For example, `121.10` becomes `121.11` / `v121.11`.
You can also run **Test and release** manually on those branches.

An `a` or `b` suffix selects alpha or beta: `121.10a` becomes `121.11a` /
`v121.11-alpha`, and `121.10b` becomes `121.11b` / `v121.11-beta`. These publish
as GitHub prereleases and the corresponding distribution channel. Plain versions
on `dev` default to alpha. Remove the suffix for stable releases. Long suffixes
(`-alpha`, `-beta`) and numbered suffixes (`a1`, `b2`) are also accepted.

The download is always `MessageSplitter.zip`, containing a `MessageSplitter/`
folder with only loaded addon files, runtime media, and LICENSE. README, changelog,
tests, and repository metadata are excluded. CHANGELOG.md supplies release notes.

For CurseForge, replace the placeholder by setting the GitHub repository variable
`CF_PROJECT_ID` to `YOUR_CURSEFORGE_PROJECT_ID` (your numeric project ID), and add
an upload token as the Actions secret `CF_API_KEY`. Until the project ID is set,
CurseForge uploads are disabled; GitHub releases still work. Existing optional
`WOWI_API_TOKEN` and `WAGO_API_TOKEN` secrets are supported when their project IDs
are configured in the TOC. Use one publishing path per service to avoid duplicates.

The workflow needs permission to write commits and tags through `GITHUB_TOKEN`;
branch/tag protections must permit those writes. To publish a manually created tag
or retry publication after a version commit/tag was pushed, run on a tag matching
the TOC (`v121.11`, `v121.11-alpha`, or `v121.11-beta`); tag builds do not bump again.
