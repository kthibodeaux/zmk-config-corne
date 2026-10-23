# building firmware

requires docker. from the repo root:

```sh
./build.sh                # build every target in build.yaml
./build.sh --update       # re-fetch zmk/zephyr before building
./build.sh --pristine     # clean build
```

firmware is written to `firmware/`. the build runs in the `zmkfirmware/zmk-build-arm:stable` image and builds the targets listed in `build.yaml`.

# flashing zmk

`./flash.sh` walks through the steps below using the firmware already in `firmware/` (it does not build). it prompts for each reset, mounts the bootloader drive, copies the right file and waits for the half to reboot. `./flash.sh --no-reset` skips the settings reset, and `./flash.sh --keymap-only` only flashes the left half, which is all a keymap change needs.

to do it by hand:

1. build the firmware (see above)
2. make sure both halves are on for this the entire time
3. plug in the left half of the keyboard and press the physical reset button twice. this will put it in bootloader mode and mount a directory
4. copy `settings_reset-*` to the mounted directory
5. unplug left half and plug in the right half and press the reset button twice
6. copy the same settings file
7. unplug the right half and plug in the left half again and press the reset button twice
8. copy `corne_left*nice_view_adapter*.uf2` to the mounted directory
9. unplug and plug in the right half and press the reset button twice
10. copy `corne_right*nice_view_adapter*.uf2` to the mounted directory

[source](https://keyboard-hoarders.com/pages/guides-1)
