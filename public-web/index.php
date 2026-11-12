<?php
declare(strict_types=1);

header('Content-Type: text/html; charset=UTF-8');
$site = require __DIR__ . '/content.php';
require_once __DIR__ . '/release-data.php';
$state = zifburn_latest_release();
$release = $state['release'];

function escape(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>ZIFburn — Chip programming for macOS</title>
<meta name="description" content="A native macOS front-end for minipro. Read, program and verify chips with searchable device databases, a hex buffer, socket diagrams, bank-switched adapters and 13 themes.">
<meta name="theme-color" content="#171c23"><link rel="icon" href="assets/icon.png"><link rel="stylesheet" href="style.css">
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
<header><a class="brand" href="#"><img src="assets/icon.png" alt="" width="40" height="40">ZIFburn</a><nav aria-label="Main navigation">
<?php foreach ($site['navigation'] as $link): ?>
<a href="#<?= escape($link['section']) ?>"<?= !empty($link['button']) ? ' class="nav-get"' : '' ?>><?= escape($link['label']) ?><?php if (!empty($link['button'])): ?> <span aria-hidden="true">↗</span><?php endif; ?></a>
<?php endforeach; ?>
</nav></header>
<main id="main">
<section class="hero"><p class="eyebrow">NATIVE macOS · MINIPRO FRONT-END · VERSION <?= escape($site['version']) ?></p><h1>Chip programming<br>for macOS.</h1><p class="intro">Read, program and verify your ROMs with a clear hex buffer, socket placement diagrams, and the minipro command behind every operation.</p><a class="button" href="#get">Get ZIFburn <span aria-hidden="true">↗</span></a><span class="requirements">macOS 14+ · Apple silicon &amp; Intel</span>
<figure><a href="assets/hex-buffer.jpg"><img src="assets/hex-buffer.jpg" alt="ZIFburn displaying a synthetic 64 KB image, checksums, a WS27C512L chip selection and socket placement diagram" width="2852" height="1650" fetchpriority="high"></a><figcaption>Hex, ASCII, checksums and socket placement in one window. Example image; no programmer connected.</figcaption></figure></section>
<section id="workflow"><p class="eyebrow">FROM IMAGE TO SOCKET</p><h2>A familiar workflow.<br>With the details in view.</h2><div class="steps"><article><span class="number">01 / SELECT</span><h3>Find your chip.</h3><p>Search minipro’s device databases, keep favorites close, and inspect package, memory size and programming defaults before you start.</p></article><article><span class="number">02 / INSPECT</span><h3>Know your image.</h3><p>Inspect hex and ASCII, check CRC32 and Sum16, find byte patterns, compare files, and trim or pad the buffer.</p></article><article><span class="number">03 / PROGRAM</span><h3>Burn with context.</h3><p>Confirm before writing. Blank-check, write and verify unless verification is disabled; follow progress in the console and see the exact command to reproduce.</p></article></div></section>
<section id="screenshots" class="gallery-section">
<div class="section-intro"><div><p class="eyebrow">A CLOSER LOOK</p><h2>Made for the workbench.</h2></div></div>
<div class="gallery">
<?php foreach ($site['screenshots'] as $shot): ?>
<figure<?= $shot['portrait'] ? ' class="themes-shot"' : '' ?>>
<a href="assets/<?= escape($shot['file']) ?>"><img src="assets/<?= escape($shot['file']) ?>" alt="<?= escape($shot['alt']) ?>" width="<?= (int) $shot['width'] ?>" height="<?= (int) $shot['height'] ?>" loading="lazy"></a>
<figcaption><span class="number"><?= escape($shot['label']) ?></span><h3><?= escape($shot['title']) ?></h3><p><?= escape($shot['description']) ?></p></figcaption>
</figure>
<?php endforeach; ?>
</div><p class="gallery-note">Screenshots from ZIFburn <?= escape($site['version']) ?> on macOS. Buffer views use example data; no programmer is connected.</p>
</section>
<section id="tools"><div class="section-intro"><div><p class="eyebrow">BEYOND A SINGLE CHIP</p><h2>Tools for the whole job.</h2></div><p>Keep the same buffer and familiar controls as you move from inspection to repeated programming.</p></div><dl class="tool-list"><div><dt>Burn ROM Set</dt><dd>Work through several images in order, with an insertion prompt for each chip. Useful for hi/lo ROM pairs.</dd></div><div><dt>Duplicate &amp; batch write</dt><dd>Read a master, make copies, or write the buffer repeatedly with Write Next, Retry and Stop controls.</dd></div><div><dt>Stability reads</dt><dd>Compare three reads, highlight changing bytes and inspect the per-byte majority result.</dd></div><div><dt>Options per chip</dt><dd>Remember memory pages, ID and size checks, programming voltages, pulse delay and ICSP settings for each device.</dd></div><div><dt>Commands &amp; progress</dt><dd>Follow minipro’s output, copy the exact command and cancel a running operation with <kbd>⌘</kbd> <kbd>.</kbd>.</dd></div><div><dt>Socket placement</dt><dd>See orientation and placement for the selected package, with adapter guidance for packages that do not fit directly.</dd></div></dl></section>
<section id="get" class="download-section"><p class="eyebrow">READY FOR YOUR WORKBENCH</p><h2>Get ZIFburn.</h2><p class="intro">Download the app, install minipro, and connect your programmer.</p><div class="release-meta"><span>macOS 14+</span><span>Apple silicon + Intel</span><span>Free · MIT licensed</span></div>
<div class="download-panel">
<div class="download-heading"><img src="assets/icon.png" alt="" width="80" height="80"><div><p class="eyebrow">UNIVERSAL MAC APP</p><h3>ZIFburn<?= $release ? ' ' . escape($release['tag']) : '' ?></h3><?php if ($release): ?><p>Published <?= escape(gmdate('j M Y', strtotime($release['published_at']))) ?></p><?php else: ?><p>Find the latest published release on GitHub.</p><?php endif; ?></div></div>
<?php if ($state['status'] === 'stale'): ?><p class="download-notice" role="status">GitHub is temporarily unavailable. These are the last confirmed release links; a newer release may be available.</p><?php endif; ?>
<?php if ($release && $release['downloads']): ?>
<div class="download-options">
<?php foreach ($release['downloads'] as $download): ?>
<div class="download-action"><a class="button<?= $download['format'] === 'ZIP' ? ' button-secondary' : '' ?>" href="<?= escape($download['url']) ?>"><?= $download['format'] === 'DMG' ? 'Download for macOS' : 'Download ZIP' ?> <span aria-hidden="true">↓</span></a><span class="download-filename"><?= escape($download['name']) ?></span><?php if ($download['checksum']): ?><a href="<?= escape($download['checksum']) ?>">SHA-256 checksum</a><?php endif; ?></div>
<?php endforeach; ?>
</div>
<p class="download-caption">Open the DMG and drag ZIFburn into Applications. For ZIP, extract the app and move it into Applications.</p>
<?php elseif ($release): ?><p>The latest release has no Mac download attached yet.</p><a class="button" href="<?= escape($release['url']) ?>">View release on GitHub ↗</a>
<?php elseif ($state['status'] === 'empty'): ?><p>The first stable download has not been published yet.</p><a class="button" href="<?= escape(ZIFBURN_REPOSITORY) ?>/releases">Browse GitHub releases ↗</a>
<?php else: ?><p>We couldn’t check the latest download right now. You can still get ZIFburn directly from GitHub.</p><a class="button" href="<?= escape(ZIFBURN_REPOSITORY) ?>/releases">Browse GitHub releases ↗</a>
<?php endif; ?>
<div class="release-links"><?php if ($release): ?><a href="<?= escape($release['url']) ?>">Release notes ↗</a><a href="<?= escape($release['source']) ?>">Source ZIP</a><?php endif; ?><a href="<?= escape(ZIFBURN_REPOSITORY) ?>/releases">All releases ↗</a><a href="<?= escape(ZIFBURN_REPOSITORY) ?>">Browse source ↗</a></div>
</div><p class="download-caption">Downloads follow the latest stable GitHub release automatically.</p>
<details class="setup-details"><summary>Installation and checksum verification</summary><div class="install"><div><h3>Install ZIFburn</h3><ol><li>Open the DMG and drag ZIFburn.app to Applications. If you choose ZIP, unzip it and move the app to Applications.</li><li>Install minipro using Homebrew:</li></ol><pre><code>brew install minipro</code></pre><p>Open ZIFburn, connect your programmer and select the exact chip. Check its orientation before starting. Custom minipro paths can be set in Settings.</p></div><div><h3>Verify your download</h3><p>Save the matching SHA-256 file alongside the DMG or ZIP. In Terminal, open that folder and run:</p><pre><code>shasum -a 256 -c ZIFburn-*-macOS-universal.dmg.sha256</code></pre><p>For ZIP, use the matching <code>.zip.sha256</code> filename instead. A matching download reports <code>OK</code>.</p></div></div></details>
</section>
<section id="build"><p class="eyebrow">MAKE IT YOUR OWN</p><h2>Build from source.</h2><p class="section-copy">Compile ZIFburn on macOS 14+ with Xcode 15+ or Swift 5.9+. minipro is installed separately.</p><details><summary>Requirements and build commands</summary><div class="install"><div><h3>Build and run</h3><p>Get the source from GitHub and run these commands from the project folder:</p><pre><code>brew install minipro
make app
open build/ZIFburn.app</code></pre><p>You can also open <code>Package.swift</code> in Xcode. Local builds are ad-hoc signed.</p></div><div><h3>Tests and universal builds</h3><pre><code>make test
make universal</code></pre><p>Full Xcode is required for Swift tests. The universal app includes Apple silicon and Intel executables.</p><a href="https://github.com/retrocs-org/zifburn#build-and-run">Build documentation ↗</a></div></div></details></section>
<section id="support" class="questions"><p class="eyebrow">HELP &amp; ANSWERS</p><h2>Support.</h2><p class="section-copy">Getting started, choosing a chip, and answers to common questions. The app’s Help menu covers workflows and shortcuts.</p><details class="faq-group"><summary>Frequently asked questions</summary><div class="faq-list">
<?php foreach ($site['questions'] as $question): ?>
<details><summary><?= escape($question['question']) ?></summary><p><?= escape($question['answer']) ?></p></details>
<?php endforeach; ?>
</div></details><div class="support-links"><a href="https://github.com/retrocs-org/zifburn/issues">Report an issue ↗</a><a href="https://github.com/retrocs-org/zifburn/releases">Changelog &amp; releases ↗</a><a href="https://gitlab.com/DavidGriffith/minipro">minipro project ↗</a></div></section>
</main><footer><span>ZIFburn · MIT licensed</span><span><a href="#support">Support</a> · <a href="https://github.com/retrocs-org/zifburn/releases">Release notes</a> · Not affiliated with XGecu.</span></footer>
</body></html>
