# SkyLine — Privacy Policy

**Last updated: 30 August 2026**

SkyLine logs the flights you have taken and draws them on a globe. This policy
describes exactly what the app does with your information. It is written against
the app's actual behaviour, not a template.

---

## The short version

- Your flights are stored in **your own iCloud account**, not on our servers. We
  cannot read them.
- When you scan a boarding pass, the app first tries to read the **barcode on
  your device**. Nothing leaves your phone when that works.
- If there is no readable barcode, **the image is sent to an AI service to be
  read**. A boarding pass image can contain your name and booking reference.
- We do not use analytics, advertising, or tracking of any kind.

---

## What we collect, and where it goes

### Your flights

Flights you add — by scanning or by typing them in — are written to the
**private database of your own iCloud account** (CloudKit container
`iCloud.com.skyline.flighttracker`). This is storage that belongs to you. The
developer has no access to it, and it is covered by
[Apple's iCloud privacy terms](https://www.apple.com/legal/privacy/).

Deleting the app does not delete this data. To remove it, use **Settings →
Delete Account** inside SkyLine.

### Boarding pass and confirmation images

When you scan a pass, SkyLine tries three things in order:

1. **Barcode, on your device.** Most printed boarding passes carry a PDF417
   barcode holding the flight details in a standard format. This is decoded
   entirely on your phone. **Nothing is transmitted.**
2. **If no barcode can be read, the image is uploaded.** This happens with
   booking confirmations, emailed itineraries, screenshots that crop the
   barcode out, and passes issued before check-in. The image travels to a
   Cloudflare Worker operated by the developer, and from there to
   [OpenRouter](https://openrouter.ai/privacy), which passes it to
   **OpenAI's GPT-4o** to be read. Alongside the image we send an identifier
   derived from your Sign in with Apple account, used only to rate-limit abuse
   of that endpoint.
3. **On-device text recognition**, as a last resort. Nothing is transmitted.

**What that image can contain.** A boarding pass typically shows your name, the
booking reference (PNR), flight number, route, date, seat, and sometimes a
frequent-flyer number. If you would rather none of that leave your device, do
not scan documents without a barcode — use **Enter manually** instead, which
transmits nothing.

Images are sent for the sole purpose of reading the flight out of them. They are
not stored by us after the response is returned. We do not control OpenRouter's
or OpenAI's retention; see their policies, linked above.

### Airport and airline lookups

To draw a route we need coordinates for an airport code. When a code is not in
the table bundled with the app, SkyLine asks
[API Ninjas](https://api-ninjas.com/) for it, and
[RapidAPI](https://rapidapi.com/) for an airline's name from its flight number.
**Only the three-letter airport code or the flight number is sent.** No
information about you accompanies these requests.

### Sign in with Apple

SkyLine requires an account. Apple gives the app a stable identifier for you,
and your name and email if you choose to share them. These are held on your
device and in your own iCloud record. The identifier is also sent with image
scans, as described above, for rate limiting.

You can delete your account at any time from **Settings → Delete Account**. This
removes your flights from iCloud, clears the app's local data, and revokes the
Sign in with Apple credential.

### Photos

SkyLine uses the system photo picker. It receives only the single image you
choose. **The app has no access to the rest of your photo library** and never
requests it.

---

## What we do not do

- No analytics or crash-reporting SDKs. There are none in the app.
- No advertising, and no advertising identifiers.
- No tracking across apps or websites. Nothing is shared with data brokers.
- No selling of data. There is no data on our servers to sell.

---

## Children

SkyLine is not directed at children under 13 and does not knowingly collect
their information.

## Changes

If this policy changes, the date at the top changes with it, and the updated
version will be published at this address.

## Contact

Questions about this policy, or a request about your data:
**pmadan.illinois@gmail.com**
