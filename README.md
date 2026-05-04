Just some random scripts I use sometimes.

zncreverse.py: Automates adding rDNS to bind9 for ZNC users.

spongebob.py: TrAnSfOrMS tEXT In tHe CLiPBOaRD

notify-user.sh: Send a desktop notification as root to a user running Xorg.

## share.sh

A simple grimshot wrapper for [rehome](https://github.com/lwatsondev/rehome) (private, sorry) with support for editing before upload.

### Dependencies

* notify-send
* [rehome-cli](https://github.com/lwatsondev/rehome/blob/main/scripts/rehome-cli.py)
* [grimshot](https://github.com/swaywm/sway/blob/master/contrib/grimshot)
* [wl-clipboard](https://github.com/bugaevc/wl-clipboard)

### Optional dependencies

* [mpv](https://mpv.io/) and [sound-theme-freedesktop](https://cgit.freedesktop.org/sound-theme-freedesktop/) - Plays a camera shutter sound on capture.
* [swappy](https://github.com/jtheoof/swappy) - Required for `--edit`.
* [oxipng](https://github.com/shssoichiro/oxipng) - Compresses and strips metadata from images before upload.
