# XDele
Purge replies, retweets, and likes from your X (formerly Twitter) account using the official free API with built-in throttling.

A macOS SwiftUI app that works from your X data archive and official API token.

---

## Requirements
- macOS 13 or later
- X (Twitter) developer account with OAuth2 user access token (write permissions)
- Your X data archive (unzipped)

- Xcode 15 or later if building the source and not just running the app.

---

## 1. Download Your X Archive
1. In X: **Settings & Privacy → Your account → Download an archive of your data**.
2. Wait for the email, download, and unzip the archive.
3. Inside you will find a data/ folder with files such as tweets.js and likes.js.

---

## 2. Get Your X Access Token
1. Create an X developer app at [https://developer.twitter.com](https://developer.twitter.com).
2. Generate a **User OAuth2 Bearer token** with write permissions (tweet delete and like delete).
3. Copy the token string for use in the app.
   - Note: password scraping or unofficial APIs are not supported.

---

## 3. Build the App
(Skip if not building from source code)
1. Open the project in Xcode.
2. Set the run target to **My Mac**.
3. Select **Product → Build (⌘B)**.
4. To locate the app: **Product → Show Build Folder in Finder → Build/Products/Debug/XDele.app**.
   - For a distributable build: **Product → Archive → Distribute → Copy App**.

---

## 4. First Run (Dry Run)
1. Launch XDele.app.
2. Fill in:
   - **Access Token**: your OAuth2 Bearer token
   - **User ID**: your numeric X user ID
   - **Folder**: the unzipped data/ folder
   - **Max deletes per hour**: recommended 99 for the free API limits
3. Leave **Dry Run** checked to test first.
4. (Optional) Configure filters: include/exclude keywords, include retweets, unlike likes.
5. Click **Start**.
   - In Dry Run mode the app only logs actions:
     "Would delete ... / Would unlike ..."

---

## 5. Real Run
1. Uncheck **Dry Run**.
2. Click **Start**.
3. The app deletes and/or unlikes in micro-batches (up to 99/hour), auto-sleeps on rate limits, and resumes each hour.

---

## 6. Data Storage
App state is stored in:
~/Library/Application Support/XDele/

- ids_to_delete.txt — queue of tweet IDs
- likes_to_unlike.txt — queue of like IDs
- x_delete_state.json — progress and hourly window

Click **Clear X data** to reset queues and state.

---

## 7. Troubleshooting
- **No deletions happening**: confirm your token is user-scoped with write permissions, and your user ID is correct.
- **Nothing to do**: ensure the correct data/ folder is selected and filters aren’t too restrictive.
- **Progress stuck**: queues may be empty. Clear X data, re-select the folder, and restart.  
- **macOS Gatekeeper warning**: right-click the app → Open to approve.

---

## License

You may redistribute and/or modify it under the terms of the AGPLv3 or later.  
See the [LICENSE](LICENSE) file for full details.
