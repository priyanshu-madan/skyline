# Sign in with Google — setup

Sign in with Google is fully implemented in `SkyLine/Services/GoogleSignInService.swift`.
What is missing is the one thing that cannot live in this repository: an **OAuth
client ID**, which has to be created in *your* Google Cloud account.

Until it is present, the Google button on the sign-in screen renders **disabled**,
with the reason printed under it. That is deliberate — an unconfigured build should
say so on the button, not open a browser that dead-ends.

There is **no SDK to install**. Do not add `GoogleSignIn` or any Swift package; the
flow is hand-rolled OAuth 2.0 + PKCE against Google's public endpoints.

---

## 1. Create the iOS OAuth client

1. Go to <https://console.cloud.google.com/>.
2. Create a project (or select an existing one).
3. **APIs & Services → OAuth consent screen**. Fill in the app name, your support
   email and a developer contact email. For a personal build, `External` +
   `Testing` is fine; add your own Google account under **Test users** or sign-in
   will be refused.
   - Scopes: `openid`, `email`, `profile` are non-sensitive and need no review.
4. **APIs & Services → Credentials → Create credentials → OAuth client ID**.
5. Application type: **iOS**. This matters — pick "Web application" by mistake and
   Google will issue a client *secret* and reject the PKCE-only token request.
6. **Bundle ID**: must match the app's `PRODUCT_BUNDLE_IDENTIFIER` exactly. Check
   it in Xcode under the SkyLine target → Signing & Capabilities.
7. Create. Google shows you two values:
   - **Client ID** — `123456789012-abcdefghijklmnop.apps.googleusercontent.com`
   - **iOS URL scheme** (the "reversed client ID") —
     `com.googleusercontent.apps.123456789012-abcdefghijklmnop`

   The second is just the first with its dot-separated parts reversed. There is
   **no client secret** for an iOS client. If you are looking at one, you created
   the wrong client type — an iOS app ships its bundle to the world, so anything
   inside it is public. PKCE is what replaces the secret.

---

## 2. Paste the client ID into `SkyLine/Info.plist`

Add a `GIDClientID` key with the **client ID** (the long one ending in
`.apps.googleusercontent.com`):

```xml
<key>GIDClientID</key>
<string>123456789012-abcdefghijklmnop.apps.googleusercontent.com</string>
```

## 3. Register the URL scheme in `SkyLine/Info.plist`

Add the **reversed client ID** as a custom URL scheme. `Info.plist` already has a
`LSApplicationQueriesSchemes` array; `CFBundleURLTypes` is a different key and
needs adding:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>com.skyline.googlesignin</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.123456789012-abcdefghijklmnop</string>
        </array>
    </dict>
</array>
```

`GoogleSignInService` checks this at launch and refuses to start the flow if the
scheme is missing, rather than sending the user through a real Google sign-in and
then having nowhere for iOS to deliver the redirect.

---

## 4. The redirect URI

Nothing to paste anywhere — an iOS OAuth client has no redirect-URI allowlist in
the console. The shape the app uses is:

```
com.googleusercontent.apps.123456789012-abcdefghijklmnop:/oauth2redirect
```

That is: **reversed client ID**, colon, **single** slash, then the path. One slash,
not two — this is an RFC 8252 private-use-scheme redirect, so there is no host
component. The value is built once in `GoogleSignInConfiguration.redirectURI` and
used for both the authorization request and the token request, which is required:
they must match byte for byte or Google returns `redirect_uri_mismatch`.

---

## 5. Verify

Build and run. On the sign-in screen:

- **Google button enabled** → configuration was read successfully.
- **Google button disabled, with a reason under it** → one of:

  | Message | Fix |
  | --- | --- |
  | `Info.plist has no GIDClientID key` | Step 2 |
  | `GIDClientID is still a placeholder` | Step 2 — the value still contains `YOUR_`, `TODO`, `PLACEHOLDER`, `REPLACE` or `XXXX` |
  | `GIDClientID doesn't look like a Google client ID` | Step 2 — must end in `.apps.googleusercontent.com` |
  | `the URL scheme … is missing from Info.plist` | Step 3 |

The same reason is printed to the console at launch, prefixed `⚠️ GoogleSignIn:`.

Note that `DebugFlags.bypassAuthentication` is currently `true`, so a DEBUG build
skips the sign-in screen entirely. Set it to `false` in
`SkyLine/Configuration/DebugFlags.swift` to see it.

---

## The caveat you should read before shipping this

**Signing in with Google does not give the user anywhere to store data.**

SkyLine persists every place, visit and trip to the **CloudKit private database**,
which belongs to the **device's iCloud account**. It has nothing to do with whoever
the app thinks is signed in. A Google identity is a display name, an email and an
avatar on the profile screen — it is not a storage account.

So a user who signs in with Google on a device with no iCloud account has nowhere
to persist anything. `AuthenticationService.signInWithGoogle()` handles this: after
a successful sign-in it calls `CloudKitService.shared.checkAccountStatus()`, and if
iCloud is unavailable it holds the sign-in in `pendingSignIn` instead of completing
it. `AuthenticationView` presents a sheet stating plainly what will and will not
work, and the user chooses whether to continue.

If you ever want Google users to get real, portable, cross-device storage, that
needs a backend keyed to the Google account — not a change to this file.

---

## Notes for whoever maintains this

- **No client secret, ever.** See step 1.6.
- **The `id_token` signature is not verified**, and that is safe *only* because the
  token comes straight back from a TLS request to `oauth2.googleapis.com` inside
  the same flow. The long comment on `decodeIDTokenPayload` explains where this
  stops being true. Do not copy that function anywhere a token arrives from
  somewhere else.
- **`sub`, not email, is the user identity.** Google email addresses can be
  reassigned within a Workspace domain; `sub` is stable.
- **No refresh token is requested or stored.** The app has no server and a refresh
  token in `UserDefaults` is a long-lived credential in plaintext. The consequence
  is that a cached Google session is trusted until the user signs out — see the
  comment in `AuthenticationService.checkExistingAuthentication()`.
- **Sign in with Apple must stay.** App Review guideline 4.8 requires it wherever a
  third-party sign-in is offered. Both buttons share one component in
  `AuthenticationView` so neither can be visually demoted by accident.
- **Google's brand guidelines** ask for their own "G" mark on the button. The app
  currently uses the SF Symbol `g.circle`, because the real mark is a four-colour
  asset and this codebase forbids hardcoded colours in views. Before shipping to
  the App Store, add Google's official asset to the asset catalogue (an image asset
  is not a hardcoded colour) and swap the `systemImage` for it.
