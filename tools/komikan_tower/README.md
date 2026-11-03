# Komikan tower check

Can the dogs ever beat a puma that stays inside the tower (the triangle)?

**Under the locked rules (dogs step forward only): no.** The tower has one way in, its apex. Dogs that can only go forward reach it one at a time, can't spread sideways around the puma and can't back out. The puma never has to leave, and it eats any dog that comes in without a second dog behind it. Since forward-only dogs have a limited number of moves, they eventually can't move and lose. The puma wins with correct play, whoever moves first.

If the dogs may also step sideways (never back), the same check finds that 6 dogs can force a trap in the tower.

## How it's checked
`tower.c` solves an abstract game that is deliberately generous to the dogs:
- only the tower and its apex are modelled
- the dogs may pass whenever they like
- any dog still outside the tower may appear on the empty apex in one move

The puma only moves inside the tower. Both sides then play perfectly over every position, about 700,000 for each side to move. If the dogs can't force a trap even with these advantages, they can't force one in the real game. `--simulate=N` also plays N real games on the full board, with the puma following the tower strategy, against random or tower-rushing dogs. In 100,000 games it was never trapped.

## Running it
```
cc -O2 -o /tmp/tower tools/komikan_tower/tower.c
/tmp/tower                      # forward-only dogs (the locked rules)
/tmp/tower --sideways           # dogs may also step sideways
/tmp/tower --simulate=100000    # real games, puma in the tower
```
If the board changes, regenerate the header first:
```
godot --headless --path . -s res://tools/komikan_tower/dump_board.gd
python3 tools/komikan_tower/make_header.py
```
See also `tools/komikan_balance.gd` (AI self-play) and the Komikan section of the dev handoff doc.
