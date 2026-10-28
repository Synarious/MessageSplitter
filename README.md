# MessageSplitter

MessageSplitter is a long-form chat composer for World of Warcraft Retail. It was built for the Midnight expansion and its stricter combat and chat-messaging restrictions. The goal is to let players draft, preview, and split longer messages when addon messaging is available, while handing control back to Blizzard's native chat when restrictions apply.

## Current behavior

- Draft in a movable, resizable composer and choose Say, emote, party, raid, guild, whisper, or a joined channel.
- Split long drafts into multiple messages while respecting the 255-byte chat limit, UTF-8 character boundaries, links, and supported roleplay formatting.
- Send each part with Enter. Automatic pacing is optional; local Say, Yell, and Emote parts remain manual.
- Use Shift+Enter for a new paragraph. Paragraphs are separate messages.
- Use `/msplit` or `/mse` to open the composer. `/mse on`, `/mse off`, and `/mse settings` manage it.
- Use `/mse restore` to restore the last draft submitted during this session if you need to retry it. A successful API call does not confirm server delivery, so restoring may cause a duplicate.

## Combat and chat lockdown

Combat lockdown and chat-messaging lockdown are related but separate. Midnight can restrict addon access to chat information and sending in encounters, challenge modes, PvP matches, and communication-restricted maps such as dungeons and raids. Restrictions can remain active after combat ends.

MessageSplitter checks combat, encounter state, and `C_ChatInfo.InChatMessagingLockdown()` before handling native-chat capture or sending. It checks again before each queued part. When combat starts, the composer hides while retaining the draft and pending queue; press Enter to open Blizzard's normal chat editor. If another chat restriction blocks sending outside combat, the composer reports the restriction and retains the draft. Sending can resume manually when the restriction clears.

The addon does not attempt to bypass Blizzard's protected chat path or simulate a hardware event. Its composer is an ordinary addon edit box; messages are sent through the chat API only when permitted. For commands that MessageSplitter cannot handle, use Default chat.

## Secret values

Midnight's secret-value system marks some API results as inaccessible to addon Lua during restricted states. Addons may store or pass some secret values, but cannot safely inspect them with ordinary comparisons, string matching, arithmetic, or formatting. `issecretvalue()` identifies a secret value when the client provides that API.

MessageSplitter only splits readable text authored in its own editor. Its native-chat capture path checks the chat type, target, language, and text for secret values before inspecting or importing them. If text is inaccessible, the addon avoids parsing or sending it and leaves native chat available. Optional spellcheck and roleplay-formatting integrations are treated as fallible; their errors should not prevent use of the plain draft.

Secret-value behavior and API restrictions can change between client patches. This addon does not read secret combat, unit, aura, or incoming-chat data. Please report errors with the client version, restriction context, and optional chat/roleplay addons enabled.

## Future direction

The project is intended to remain a drafting and formatting aid that works within Midnight's addon security model. Future work should prioritize preserving drafts and queue position across restriction changes, clear restriction status, reliable recovery after uncertain sends, and compatibility with new Retail API versions. It should not depend on reading secret data or circumventing protected chat actions.

## Optional integrations

Total RP 3 can provide roleplay text coloring. Misspelled can provide spell checking. Both are optional; MessageSplitter should continue to work without them.
