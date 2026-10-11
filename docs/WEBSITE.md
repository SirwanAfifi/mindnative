# Landing page

The website is at https://sirwan.info/mindnative/.
The source is in `landing-page/`.
The page uses HTML, CSS, and JavaScript. It has no build step.

## Preview the page

Run this command from the repository root:

```sh
python3 -m http.server 8000 --directory landing-page
```

Open http://localhost:8000/ in a browser.
Stop the server with Control-C.

## Publish a change

Push a change in `landing-page/` to `main`.
The `Publish landing page` workflow publishes the folder through GitHub Pages.
You can also start the workflow from the Actions page.

Keep asset links relative to the page.
Do not put private files in `landing-page/`.

## Content

The main action links to the app source.
The page states that a packaged app is not yet available.
Change this text and the action when a signed app release is ready.

Use short sentences and clear control labels.
Use real app screenshots.
See `DESIGN.md` for website styles and interaction rules.

## Assets

The site uses the existing MindNative icon and three app screenshots.
Origin information is embedded in each image or in its sidecar.
Manrope is self-hosted under the SIL Open Font License.
See `landing-page/assets/ASSETS.md` and `landing-page/assets/fonts/OFL.txt`.
