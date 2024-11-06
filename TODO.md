# Correctness
- [ ] Song offset -> add to chart/note, since it's invisible to rl.getMusicTimePlayed
- [ ] Audio/Visual offset -> add to chart/note, since it's invisible to rl.getMusicTimePlayed
- [ ] If BPM gimmick occurs between frames, correct beat in `updateBeat()`
- [ ] Holds
- [ ] Jumps
- [ ] Shocks
- [ ] Auto-generate ghost steps for stops
  - Consider adding a ghost-step []Note and process it when a stop is encountered while timing notes
- [ ] Correct/Accurate/Customised judgment
  - e.g. Jump holds that end at different times? Steps when other foot is frozen?

# Features
- [x] Autoplay
- [ ] Read .ssc files
- [ ] Assist-tick
- [ ] CONSTANT specified by % of equivalent scroll speed
- [ ] Doubles

# Tech debt
## Robustness
- [ ] test note array is null-terminated after parsing

## Optimisation
- [-] Don't load all notes textures at once. (On second thought, it kinda makes sense to preload all arrow textures at once)

## Readability
- [ ] `fn timeNotes` is pretty long. Consider splitting out the note/gimmick logic into smaller functions that pass around a .{time, beatPrev, bpm} state.
- [x] Judgment should be defined in the Note struct or Judgment enum?
- [ ] Should `Summary.gimms` include the inital BPM setting if it's not technically a Gimmick?
- [ ] Migrate `Summary.gimms` to `Chart.gimms` for ssc files.
