# flashing zmk

1. download the artifact from the github action
2. make sure both halves are on for this the entire time
3. plug in the left half of the keyboard and press the physical reset button twice. this will put it in bootloader mode and mount a directory
4. copy `settings_reset-*` to the mounted directory
5. unplug left half and plug in the right half and press the reset button twice
6. copy the same settings file
7. unplug the right half and plug in the left half again and press the reset button twice
8. copy `*_left_nice_view_adapter*.uf2` to the mounted directory
9. unplug and plug in the right half and press the reset button twice
10. copy `*_right_nice_view_adapter*.uf2` to the mounted directory

[source](https://keyboard-hoarders.com/pages/guides-1)
