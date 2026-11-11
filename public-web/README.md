# ZIFburn website

A PHP website with feature descriptions, application screenshots and build
instructions. PHP renders the navigation, version, screenshot gallery and FAQs
from `content.php`. No framework, database, Composer packages or JavaScript
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
archive contains `index.php`, `content.php`, `style.css`, `LICENSE` and the image assets.
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

After publishing a signed and notarized binary release, add its download and
checksum links to the Get started section.

## Screenshots

The gallery covers chip search, the hex buffer, bank-switched adapter settings
and the appearance picker. Buffer views use `Support/Examples/demo.bin`;
no programmer is connected. Screenshot links open full-size images.

When refreshing screenshots, use example files from a neutral folder so local
usernames and development workspace paths are not visible. Keep captions,
alternative text and image dimensions consistent with each capture.
