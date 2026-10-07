# Distribution metrics

Decision accepted on 6 October 2026.

Use GitHub Release asset download counts to measure interest in Phosphor.
Publish the downloadable app archive as a release asset when distribution is ready.
GitHub exposes each asset's `download_count` through its [release assets API](https://docs.github.com/en/rest/releases/assets).

Interpret these as download counts, including repeat downloads and any Sparkle updates fetched from the same assets.
They do not establish unique users, successful installations, or active usage.

Do not implement an app usage heartbeat or provision a reporting backend.
This decision replaces the usage heartbeat proposal.
