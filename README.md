# NOVA6
Retro TV broadcast screen. Hosted by GitHub Pages; transmissions are committed to this repo by `sender/send.bat`.

## Setup (once)
1. Repo must be public. Settings -> Pages -> Deploy from branch `main`, folder `/ (root)`.
2. Create a fine-grained token (GitHub -> Settings -> Developer settings -> Fine-grained tokens): only this repo, permission "Contents: Read and write". Paste it into `sender/sender.cfg`. Keep that file private (do not commit it).
3. Drag an .mp3/.mp4 (max 50 MB) onto `sender/send.bat`.

Open screens poll every 15 s, so a transmission shows up ~15-30 s after sending.
