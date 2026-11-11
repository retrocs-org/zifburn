<?php
declare(strict_types=1);
header('Content-Type: text/html; charset=UTF-8');
require_once __DIR__ . '/release-data.php';
$state = zifburn_latest_release();
$release = $state['release'];
function escape(string $value): string { return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8'); }
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Get ZIFburn — Downloads for macOS</title>
<meta name="description" content="Download the latest stable ZIFburn release for Apple silicon and Intel Macs. Get checksums, source code and installation instructions.">
<meta name="theme-color" content="#171c23"><link rel="icon" href="assets/icon.png"><link rel="stylesheet" href="style.css">
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
<header><a class="brand" href="index.php"><img src="assets/icon.png" alt="" width="40" height="40">ZIFburn</a><nav aria-label="Main navigation"><a href="index.php#workflow">Workflow</a><a href="index.php#screenshots">Screenshots</a><a href="index.php#start">Build from source</a><a href="get.php" aria-current="page">Get ZIFburn</a></nav></header>
<main id="main">
<section class="download-hero"><p class="eyebrow">READY FOR YOUR WORKBENCH</p><h1>Get ZIFburn.</h1><p class="intro">A native Mac home for your ROMs. Download the app, install minipro, and connect your programmer.</p><div class="release-meta"><span>macOS 14+</span><span>Apple silicon + Intel</span><span>Free · MIT licensed</span></div>
<div class="download-panel">
<div class="download-heading"><img src="assets/icon.png" alt="" width="80" height="80"><div><p class="eyebrow">UNIVERSAL MAC APP</p><h2>ZIFburn<?= $release ? ' ' . escape($release['tag']) : '' ?></h2><?php if ($release): ?><p>Published <?= escape(gmdate('j M Y', strtotime($release['published_at']))) ?></p><?php else: ?><p>Find the latest published release on GitHub.</p><?php endif; ?></div></div>
<?php if ($state['status'] === 'stale'): ?><p class="download-notice" role="status">GitHub is temporarily unavailable. These are the last confirmed release links; a newer release may be available.</p><?php endif; ?>
<?php if ($release && $release['downloads']): ?>
<?php foreach ($release['downloads'] as $download): ?>
<div class="download-action"><a class="button" href="<?= escape($download['url']) ?>">Download for macOS <span aria-hidden="true">↓</span></a><span class="download-size">ZIP · <?= escape(number_format($download['size'] / 1048576, 1)) ?> MB</span><?php if ($download['checksum']): ?><a href="<?= escape($download['checksum']) ?>">SHA-256 checksum</a><?php endif; ?></div>
<?php endforeach; ?>
<p class="download-caption">One download for Apple silicon and Intel Macs. minipro is installed separately.</p>
<?php elseif ($release): ?><p>The latest release has no Mac download attached yet.</p><a class="button" href="<?= escape($release['url']) ?>">View release on GitHub ↗</a>
<?php elseif ($state['status'] === 'empty'): ?><p>The first stable download has not been published yet.</p><a class="button" href="<?= escape(ZIFBURN_REPOSITORY) ?>/releases">Browse GitHub releases ↗</a>
<?php else: ?><p>We couldn’t check the latest download right now. You can still get ZIFburn directly from GitHub.</p><a class="button" href="<?= escape(ZIFBURN_REPOSITORY) ?>/releases">Browse GitHub releases ↗</a>
<?php endif; ?>
<div class="release-links"><?php if ($release): ?><a href="<?= escape($release['url']) ?>">Release notes ↗</a><a href="<?= escape($release['source']) ?>">Source ZIP</a><?php endif; ?><a href="<?= escape(ZIFBURN_REPOSITORY) ?>/releases">All releases ↗</a><a href="<?= escape(ZIFBURN_REPOSITORY) ?>">Browse source ↗</a></div>
</div><p class="download-caption">Downloads follow GitHub’s latest stable release automatically. Drafts and prereleases are excluded.</p></section>
<section id="install"><p class="eyebrow">FROM DOWNLOAD TO SOCKET</p><h2>Up and running.</h2><div class="steps"><article><span class="number">01 / INSTALL THE APP</span><h3>Make it at home.</h3><p>Unzip the download, drag ZIFburn.app into Applications, then open it.</p></article><article><span class="number">02 / ADD MINIPRO</span><h3>Bring the driver.</h3><p>Install minipro using Homebrew:</p><pre><code>brew install minipro</code></pre><p>ZIFburn finds the usual Homebrew and MacPorts locations. A custom path can be set in Settings.</p></article><article><span class="number">03 / CONNECT</span><h3>Choose your chip.</h3><p>Connect your programmer, select the exact chip and check its orientation before starting. Open an image to inspect its bytes and checksums.</p></article></div></section>
<section class="install"><div><p class="eyebrow">CHECK YOUR DOWNLOAD</p><h2>Verify the ZIP.</h2><p>Download the matching SHA-256 file into the same folder as the ZIP. In Terminal, open that folder and run:</p><pre><code>shasum -a 256 -c ZIFburn-*-macOS-universal.zip.sha256</code></pre><p>A matching download reports <code>OK</code>.</p></div><div><p class="eyebrow">BUILD IT YOURSELF</p><h2>Start from source.</h2><p>Prefer to compile it? Get the tagged source from GitHub, then build with Xcode 15+ or Swift 5.9+:</p><pre><code>make app
open build/ZIFburn.app</code></pre><p>Local builds are ad-hoc signed. Full Xcode is needed to run the Swift tests.</p><a href="index.php#start">Build requirements ↗</a></div></section>
</main><footer><span>ZIFburn · MIT licensed</span><span>Independent software. Not affiliated with XGecu.</span></footer>
</body></html>
