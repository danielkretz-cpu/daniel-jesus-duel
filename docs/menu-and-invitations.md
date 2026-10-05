# Menu and invitation flow

The native Godot interface is Swedish and uses physical viewport pixels for legible text and minimum 48-pixel action buttons. The gameplay canvas may scale independently.

## Player flow

- The start screen has **Spela online · 2–6 vänner** and **Lokal duell · samma skärm**. Local duels remain two-player; online rooms support two to six players.
- Online entry asks for a display name, then offers **Skapa ett rum** or **Gå med i rummet**. Join accepts either the eight-character room code or the full invitation URL.
- Opening an invitation skips the create action, prefills the code, and asks the visitor to choose a name and click Join. It never joins automatically or discloses a name on page load.
- In the waiting room, the six seats show display names, your own seat, the host and connection state. The host chooses the arena and explicitly starts once at least two reserved players are connected. A disconnected reserved seat blocks start: an inline explanation tells friends to reconnect in their open tabs and tells the host to leave and create a new room if someone will not return.
- **Bjud in vänner** requests the browser's native share sheet from that button press. If unavailable or denied, it attempts clipboard copy. **Kopiera länk** requests clipboard copy directly. A denied clipboard reveals a selectable URL; the visible eight-character room code is always a fallback. Cancelling the share sheet does not leave the room or claim success.
- A reserved room requires confirmation before leaving. Cancel preserves the session. A disconnected player can reconnect in the same open tab. Joining and starting are guarded against repeated taps.

## Privacy and validation

`FriendInvite.share_url()` generates only:

`https://danielkretz-cpu.github.io/daniel-jesus-duel/?room=ABCDEFGH`

It constructs this URL from the validated public room code and a fixed canonical base. It never copies the current browser location, display name, query parameters, or `NetSession.token`. Resume tokens stay in the current client's memory and are never included in invitations. The room alphabet excludes ambiguous characters; codes are exactly eight characters.

`FriendInvite` accepts a `room` query or hash parameter, encoded values and lowercase codes. Duplicate room parameters, invalid characters, and encoded parameter injection fail closed. `NetSession` owns display-name normalization and validation (1–20 Unicode codepoints, no controls/markup delimiters). UI labels display literal text, never rich markup.

Once a match starts, invitation actions are hidden: new players cannot join an active match. Existing players recover their seat from the same open tab. Explicitly leaving abandons the local resume credential; the slot remains reserved until the host creates a fresh room or the room expires.

## Integration

- `StartMenu`: `layout(view)`, `set_map(id)`; signals `local_requested(id)`, `online_requested(id)`, `map_changed(id)`.
- `OnlineLobby`: `layout(view)`, `set_map(id)`, `refresh(session)`, `open_invite(code_or_url)`, `request_leave()`; signals `create_requested(name)`, `join_requested(code, name)`, `start_requested(id)`, `map_changed(id)`, `leave_requested`, `leave_cancelled`, `reconnect_requested`. Connect `leave_cancelled` to the game overlay refresh so an unpaused match resumes immediately.
- Startup: read `FriendInvite.current_room()`, open the lobby, then call `open_invite(code)`. `--room=CODE` supplies an explicit native test invitation.
- The game must not process gameplay or old custom-drawn title targets while either menu is visible.
- Layout keeps Back and Start outside the scrollable body, so they remain reachable in short landscape windows. Deferred refitting prevents stale minimum widths after portrait/landscape rotation.

## Verification

Run `godot --headless --path . --script res://tests/test_menu.gd`.

The 99-check suite covers Unicode names, blank/markup name errors, direct and URL-based joins, no automatic join, explicit host start, guest restrictions, six-player roster, disconnected seats, repeated taps, leave/cancel/confirm, reconnection, invite encoding and privacy, clipboard-denied fallback, sharing cancellation, and seven viewports including 320×568 and 568×320. It also instantiates the actual Main.tscn to verify menu wiring, active-match confirmation surviving network refresh, immediate cancellation recovery, and chosen names reaching the fighters.

The headless suite cannot invoke an actual operating-system share sheet or verify mobile virtual keyboard behavior. Those need browser/device checks in addition to the native-rendering inspection.
