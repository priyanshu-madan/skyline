# Skyline Travel Log — published pages

This repository exists only to serve two pages:

- <https://priyanshu-madan.github.io/skyline/> — privacy policy
- <https://priyanshu-madan.github.io/skyline/support.html> — support

Both URLs are hardcoded into the shipped iOS app and registered with App Store
Connect, so the paths cannot change.

**Do not edit the HTML here.** It is generated output. The source is
`docs/privacy-policy.md` and `docs/support.md` in the private application
repository, rendered by `docs/build-privacy-page.mjs` and pushed here by
`scripts/publish-docs.sh`. An edit made in this repository will be overwritten
by the next publish, and worse, will make the published page disagree with the
policy the app was built against.
