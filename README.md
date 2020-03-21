# Voice over Mumble

Use Android/iOS device as your PC's microphone, using Mumble + Plumble. Or use microphone of one PC on other PC.

Linux-only script, but steps can be replicated on other systems (e.g. using VoiceMeeter).

This is the lowest latency I've ever achieved (sounds almost like local loopback, theoretically 7ms WiFi delay + 2x 10ms codec delay = 27 ms).

## Installation

Install Mumble (desktop client) + Murmur (server) + Plumble (Android/iOS client). Set all 3 programs to use best quality and minimal latency. Set mobile client to always streaming.

To install Mumble + Murmur on Ubuntu, you can use:

```bash
sudo apt install mumble mumble-server
sudo systemctl stop mumble-server.service
sudo systemctl disable mumble-server.service
```

Copy `mic_over_mumble` anywhere - it will use `~/.mic_over_Mumble` as configuration directory.

Run `mic_over_mumble`, then connect your mobile device to LAN server.

Then, set up your programs to use monitor of Mumble as input device. E.g. in OBS:

![Screenshot of OBS configuration](obs_screenshot.png)

If for some reason the script messes up your audio config, you can use `pulseaudio -k` to reload PA.
