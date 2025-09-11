# XDele
Delete replies, retweets, and/or likes from your X (formerly Twitter) account using the official free API with built-in throttling.

A macOS SwiftUI app that works from your X data archive and official API tokens.

## [Download XDele App here](https://github.com/yourusername/XDele/releases)

---

## Requirements
- macOS 13 or later  
- X developer account with **OAuth 1.0a keys/tokens** (default, recommended)
- (Optional) OAuth 2.0 user access token if you prefer using OAuth 2.0
- Your X data archive (unzipped)
- Xcode 15 or later if building the source and not just running the app

![Screenshot](images/xd1.jpg)

---

## 1. Download Your X Archive
1. In X: **Settings & Privacy → Your account → Download an archive of your data**.
2. Wait for the email, download, and unzip the archive.
3. Inside you will find a data/ folder with files such as tweets.js and likes.js.

![Screenshot](images/xd2.jpg)

---

## 2. Authentication
1. Create a project and app in the [X Developer Portal](https://developer.twitter.com). (Products → X API → Free plan)
2. When prompted, save the **API Key**, **API Secret Key**, and **Bearer Token** (they are only shown once).
3. Open the app’s **Keys and Tokens** tab:
   - Generate an **Access Token** and **Access Token Secret** (user-specific).
4. Copy these four OAuth 1.0a values (API Key, API Secret Key, Access Token, Access Token Secret) plus your numeric User ID for use in the app.
   - OAuth 1.0a is the default and recommended mode.
   - OAuth 2.0 is also supported — if you already have a valid OAuth 2.0 user token, switch to it in the app and paste your token instead.
   - Password scraping or unofficial APIs are **not supported**.

![Screenshot](images/xd3.jpg)

---

## 3. Build the App 
(Skip if not building from source code, see [Releases](https://github.com/yourusername/XDele/releases) to just run the app.)  

1. Open the project in Xcode.  
2. Set the run target to **My Mac**.  
3. Select **Product → Build (⌘B)**.  
4. To locate the app: **Product → Show Build Folder in Finder → Build/Products/Debug/XDele.app**.  
   - For a distributable build: **Product → Archive → Distribute → Copy App**.  

![Screenshot](images/xd3.jpg)

---

## 4. First Run (Dry Run)
1. Launch 'XDele.app'.  
2. Fill in:  
   - For **OAuth 1.0a** (default): API Key, API Secret Key, Access Token, Access Token Secret, plus User ID  
   - For **OAuth 2.0**: switch Auth Mode to OAuth 2.0 and paste your user token plus User ID  
   - **Folder**: select the unzipped 'data/' folder  
   - **Max deletes per hour**: recommended 99 for the free API limits  
3. Leave **Dry Run** checked to test first.  
4. (Optional) Configure filters: include/exclude keywords, include retweets, unlike likes.  
5. Click **Start**.  
   - In Dry Run mode the app only logs actions:  
     "Would delete … / Would unlike …"

---

## 5. Real Run
1. Uncheck **Dry Run**.  
2. Click **Start**.  
3. The app deletes and/or unlikes in micro-batches (up to 99/hour), auto-sleeps on rate limits, and resumes each hour.  

---

## 6. Data Storage
App state is stored in:  
'~/Library/Application Support/XDele/'

- 'ids_to_delete.txt' — queue of tweet IDs  
- 'likes_to_unlike.txt' — queue of like IDs  
- 'x_delete_state.json' — progress and hourly window  

Click **Clear X data** to reset queues and state.  

---

## 7. Troubleshooting
- **No deletions happening**: confirm your token is user-scoped with write permissions, and your user ID is correct.  
- **Nothing to do**: ensure the correct 'data/' folder is selected and filters aren’t too restrictive.  
- **Progress stuck**: queues may be empty. Clear X data, re-select the folder, and restart.  
- **macOS Gatekeeper warning**: right-click the app → **Open** to approve.  

---

## License
You may redistribute and/or modify it under the terms of the AGPLv3 or later.  
See the [LICENSE](LICENSE) file for full details, or [https://www.gnu.org/licenses/agpl-3.0.html](https://www.gnu.org/licenses/agpl-3.0.html).  
