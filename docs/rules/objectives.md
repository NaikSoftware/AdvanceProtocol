# Objectives and victory

The detail behind §3.10 of CLAUDE.md — how a match is won.

[back to CLAUDE.md](../../CLAUDE.md)

A map carries up to 15 objective markers (villages, depots, bridges, crossroads). Each is owned or
neutral, and each is either intact or taken. An engineer adjacent to one flips it.

An objective is **revealed to an opponent only once they have seen it** — objectives obey fog like
everything else.

Victory, checked at end of turn:
- an opponent has no units left, **or**
- the map's objective condition is met (usually: hold N of M objectives)

Last player standing wins. In 3-player games an eliminated player is skipped in the turn order,
and the match continues between the remaining two.

**A map with no objective condition sets `hold_target` to 0**, and then only annihilation can end
the match. Most maps will set it; a pure annihilation map will not.

**When both conditions resolve on the same end of turn, elimination decides.** Not because it is
better, but because it is unconditional: a player with no units is out of the match whatever the
map says, whereas an objective hold is a condition the map opted into. In practice the two almost
always name the same winner — a player who has just lost their last unit is not holding anything —
so this rule exists to make the rare case deterministic rather than to express a preference.

**The objective condition is checked for one player only: the one whose turn just ended.**
Elimination is still checked globally — a player with no units is out whoever was playing — but an
objective win is claimed, not awarded, and you claim it on your own turn.

This closes what used to be an open question here. If two players both held enough objectives, the
lower player index won, which is loop order rather than a rule. Rather than pick a tie-break, the
tie is made unreachable: only one player can ever be the one whose turn just ended, so two players
can never claim on the same check.

The second effect is smaller but real: a player is no longer handed the match at *someone else's*
end of turn. A holding that was already sufficient — a map that starts a player above
`hold_target`, or an opponent demolishing their way below it — is now claimed by that player at
their own end of turn rather than announced during a turn they were not playing.

**What this change does *not* buy, stated because an earlier version of this document claimed it
did:** it does not make you survive a round to keep a captured objective. Capture is an engineer
action and engineers only act on their owner's turn, so the capture and the claim fall inside the
same turn — take the last objective and you win at the end of that turn, with no opponent
response. Making a victory something you have to survive would need a separate rule (an objective
not counting on the turn it changed hands), and that is a new mechanic, not a consequence of this
one. Left undone deliberately, pending playtest.
