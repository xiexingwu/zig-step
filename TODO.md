# Generic
- [ ] Song offset -> add to chart/note, since it's invisible to rl.getMusicTimePlayed
- [ ] Audio/Visual offset -> add to chart/note, since it's invisible to rl.getMusicTimePlayed
- [ ] Holds
- [ ] Jumps
- [ ] Shocks
- [ ] Auto-generate ghost steps for stops
  - Consider adding a ghost-step []Note and process it when a stop is encountered while timing notes
- [ ] Correct/Accurate/Customised judgment
  - e.g. Jump holds that end at different times? Steps when other foot is frozen?

# Doubles
- [ ] Judgment (key press detection)

# Tech debt
## Robustness
- [ ] test note array is null-terminated after parsing

## Optimisation
- [ ] Don't load all notes textures at once

## Readability
- [ ] `fn timeNotes` is pretty long. Consider splitting out the note/gimmick logic into smaller functions that pass around a .{time, beatPrev, bpm} state.
- [ ] Judgment should be defined in the Note struct or Judgment enum?
- [ ] Should `Summary.gimms` include the inital BPM setting if it's not technically a Gimmick?
- [ ] Migrate `Summary.gimms` to `Chart.gimms` for ssc files.
