# ZIFburn website

A PHP website with feature descriptions, application screenshots and build
instructions. PHP renders the navigation, version, screenshot gallery and FAQs
from `content.php`. The homepage’s Get ZIFburn section lists the latest stable GitHub release automatically. No framework, database, Composer packages or JavaScript
build step is required.

## Requirements

Use PHP 8.2 or later, with Apache, Nginx + PHP-FPM, or another PHP-capable host.
The PHP CLI is also required for local previews and website checks.

## Preview

From the repository root:

```sh
php -S localhost:8080 -t public-web
```

Open http://localhost:8080. The built-in PHP server is for local development;
use a production web server for public hosting.

Run `make website-check` to lint every PHP file, render the page, and validate
its version, local links, section anchors and screenshot assets.

## Content

Edit `content.php` for the version, navigation links, gallery captions and FAQ
answers. Edit `index.php` for page structure and feature sections, and
`style.css` for layout. Text values are escaped when rendered.

## Publishing

Run `make website-package` to create `build/zifburn-website.tar.gz`. Extract it
into your PHP host’s document root, preserving the `assets/` directory. The
archive contains `index.php`, `get.php`, `release-data.php`, `content.php`, `style.css`,
`LICENSE` and the image assets.
Configure the host to use `index.php` as its directory index and execute PHP
files through the PHP runtime. Check the homepage and screenshot links after
deployment. Keep the application source and signing credentials outside the
web document root.

For Apache, enable PHP handling and include `index.php` in `DirectoryIndex`.
For Nginx, set `index index.php` and configure a PHP-FPM handler for existing
`.php` files. The exact PHP-FPM socket or upstream is host-specific.

GitHub Pages serves static files and cannot run this PHP website. The Website
checks workflow validates and packages the PHP site for upload to your host;
it does not deploy it to GitHub Pages.

## Automatic downloads

The `#get` section reads the public GitHub latest-release API for `retrocs-org/zifburn`.
Download and matching checksum links come from the returned release assets;
future stable tags need no website edit. Drafts and prereleases are excluded.
The release tag, date, source archive and release-notes links follow that release.
Only uploaded Mac universal ZIP assets from the same repository and tag are shown.

Allow outbound HTTPS to `api.github.com`. PHP cURL is preferred; HTTPS streams
with `allow_url_fopen` are supported as a fallback. No GitHub token is needed or
stored on the web server. Public metadata is cached for five minutes in PHP’s
system temporary directory, outside the document root. The web user should be
able to write there. If caching is unavailable the lookup still works, but
requests may reach GitHub’s unauthenticated rate limit sooner.

On API/network failure, recent cached links are labelled as last confirmed for
up to 24 hours; older data is discarded. Without cached data the page links to
GitHub releases. A 404 clears cached release links. Deployments need no cron job
or JavaScript. `ZIFBURN_RELEASE_OFFLINE=1` disables network lookups for offline
checks; do not set it on the production server. `make website-check` exercises
cache refresh, future tags, invalid responses and failures without networking.

## Screenshots

The gallery covers chip search, the hex buffer, bank-switched adapter settings
and the appearance picker. Buffer views use `Support/Examples/demo.bin`;
no programmer is connected. Screenshot links open full-size images.

When refreshing screenshots, use example files from a neutral folder so local
usernames and development workspace paths are not visible. Keep captions,
alternative text and image dimensions consistent with each capture.

## Page structure

All visitor content is on `index.php`: workflow, screenshots, tools, Get ZIFburn,
one Build from source section, and Support with an expandable FAQ. Navigation
uses scrolling section links. The outlined Get ZIFburn menu button leads to
`#get`. Changelog links point to GitHub releases. `get.php` redirects old download
page links to `index.php#get`.
