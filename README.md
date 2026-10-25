# PocketFind

A mobile-first web app to see your close ones on a live map. Each person opens the app, enters a name and gets a 6-character code and a QR code. Adding someone's code makes you mutual friends: you both see each other's position.

Your position is sent while the app is open (when you move, and every 30 seconds while still). When you close it, your friends keep seeing your last position with the time elapsed since it was sent.

## Features

- Name and colour chosen once, remembered on the device (anonymous account, no email)
- Personal code and QR code, in-app QR scanner, share sheet
- Live map with every friend's avatar, name and time since the last update
- "Now" indicator for friends who currently have the app open
- Friend list sorted by distance, detail card with approximate address, distance, time and accuracy
- Directions to a friend in Apple Maps (Google Maps on other devices)
- Ghost mode to hide your position from everyone
- Light, dark and automatic theme
- Installable on the iPhone home screen as a standalone app

## Setup

1. Create a Supabase project (or reuse an existing one: every table and function is prefixed with `pf_`).
2. In the SQL Editor, run the whole `supabase.sql` file.
3. In the Authentication settings, enable anonymous sign-ins.
4. In the project API settings, copy the Project URL and the anon (or publishable) key into `config.js`.
5. Push all files to a GitHub repository and enable GitHub Pages on it.
6. On the iPhone, open the Pages address in Safari, then Share and Add to Home Screen. Open the app from the home screen.

## Files

- `index.html` the whole app
- `config.js` Supabase URL and public key
- `supabase.sql` tables, row level security, functions and realtime
- `manifest.webmanifest`, `sw.js`, `icon-*.png` home screen app setup

## Notes

- A web app cannot track location in the background on iPhone; positions are only sent while the app is open.
- The account lives on the phone. Removing the app from the home screen or clearing website data deletes the link to it; the person then creates a new account and friends add the new code.
- If the location prompt appears at each launch, set location access for Safari websites to Allow in the iPhone privacy settings.
- Free Supabase projects pause after a week without activity.
- Map tiles by CARTO, map data by OpenStreetMap contributors, addresses by Nominatim.

## Version

1.0
