// Where the Download button sends people: the alias every release copies the
// newest DMG to, never the pinned name in release.json. The pinned name changes
// only when the site is rebuilt and deployed, and production goes out by hand,
// so a button on it offered whichever build the site was last deployed with.
// The alias is rewritten by every release (`scripts/publish-download.sh`), with
// a short cache and an invalidation, so the page always serves the newest build
// whether or not it has been redeployed since. `releases/latest.json` beside it
// names the build and its SHA-256 for anyone who wants to check what they got.
export const latestDownloadURL = 'https://zephra-assets.urandom.io/releases/Zephra-latest.dmg';
export const latestManifestURL = 'https://zephra-assets.urandom.io/releases/latest.json';
