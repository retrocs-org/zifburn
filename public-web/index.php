<?php
declare(strict_types=1);

header('Content-Type: text/html; charset=UTF-8');
$site = require __DIR__ . '/content.php';

function escape(string $value): string
{
    return htmlspecialchars($value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}
?>
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>ZIFburn — A native Mac home for your ROMs</title>
<meta name="description" content="A native macOS front-end for minipro. Read, program and verify chips with searchable device databases, a hex buffer, socket diagrams, bank-switched adapters and 13 themes.">
<meta name="theme-color" content="#171c23"><link rel="icon" href="assets/icon.png"><link rel="stylesheet" href="style.css">
</head>
<body>
<a class="skip" href="#main">Skip to content</a>
<header><a class="brand" href="#"><img src="assets/icon.png" alt="" width="40" height="40">ZIFburn</a><nav aria-label="Main navigation">
<?php foreach ($site['navigation'] as $link): ?>
<a href="#<?= escape($link['section']) ?>"><?= escape($link['label']) ?></a>
<?php endforeach; ?>
</nav></header>
<main id="main">
<section class="hero"><p class="eyebrow">NATIVE macOS · MINIPRO FRONT-END · VERSION <?= escape($site['version']) ?></p><h1>Old chips.<br>A native Mac home.</h1><p class="intro">Read, program and verify your ROMs with a clear hex buffer, socket placement diagrams, and the minipro command behind every operation.</p><a class="button" href="#start">Build ZIFburn <span aria-hidden="true">↗</span></a><span class="requirements">macOS 14+ · Apple silicon &amp; Intel</span>
<figure><a href="assets/hex-buffer.jpg"><img src="assets/hex-buffer.jpg" alt="ZIFburn displaying a synthetic 64 KB image, checksums, a WS27C512L chip selection and socket placement diagram" width="2852" height="1650" fetchpriority="high"></a><figcaption>Hex, ASCII, checksums and socket placement in one window. Example image; no programmer connected.</figcaption></figure></section>
<section id="workflow"><p class="eyebrow">FROM IMAGE TO SOCKET</p><h2>A familiar workflow.<br>With the details in view.</h2><div class="steps"><article><span class="number">01 / SELECT</span><h3>Find your chip.</h3><p>Search minipro’s device databases, keep favorites close, and inspect package, memory size and programming defaults before you start.</p></article><article><span class="number">02 / INSPECT</span><h3>Know your image.</h3><p>Inspect hex and ASCII, check CRC32 and Sum16, find byte patterns, compare files, and trim or pad the buffer.</p></article><article><span class="number">03 / PROGRAM</span><h3>Burn with context.</h3><p>Confirm before writing. Blank-check, write and verify unless verification is disabled; follow progress in the console and see the exact command to reproduce.</p></article></div></section>
<section id="screenshots" class="gallery-section">
<div class="section-intro"><div><p class="eyebrow">A CLOSER LOOK</p><h2>Made for the workbench.</h2></div><p>From choosing a device to setting an adapter’s switches, keep the next decision in view. Select a screenshot to see it at full size.</p></div>
<div class="gallery">
<?php foreach ($site['screenshots'] as $shot): ?>
<figure<?= $shot['portrait'] ? ' class="themes-shot"' : '' ?>>
<a href="assets/<?= escape($shot['file']) ?>"><img src="assets/<?= escape($shot['file']) ?>" alt="<?= escape($shot['alt']) ?>" width="<?= (int) $shot['width'] ?>" height="<?= (int) $shot['height'] ?>" loading="lazy"></a>
<figcaption><span class="number"><?= escape($shot['label']) ?></span><h3><?= escape($shot['title']) ?></h3><p><?= escape($shot['description']) ?></p></figcaption>
</figure>
<?php endforeach; ?>
</div><p class="gallery-note">Screenshots from ZIFburn <?= escape($site['version']) ?> on macOS. Buffer views use example data; no programmer is connected.</p>
</section>
<section id="updates"><p class="eyebrow">CURRENT IN <?= escape($site['version']) ?></p><h2>Clearer checks.<br>More useful feedback.</h2><div class="steps"><article><span class="number">CONFIRM BEFORE WRITING</span><h3>A deliberate Burn.</h3><p>Burn Buffer and Burn File ask for confirmation, including the keyboard shortcut. The dialog tells you when verification is disabled.</p></article><article><span class="number">REPORT WHAT RAN</span><h3>Verification stays explicit.</h3><p>Normal, ROM-set and adapter burns report when verification was skipped. Destructive retries return to the confirmation step.</p></article><article><span class="number">VALIDATE THE IMAGE</span><h3>Stricter HEX imports.</h3><p>Intel HEX imports check record structure, checksums, end records and address boundaries. Sparse images are limited to 64 MiB of expanded buffer data.</p></article></div></section>
<section id="tools"><div class="section-intro"><div><p class="eyebrow">BEYOND A SINGLE CHIP</p><h2>Tools for the whole job.</h2></div><p>Keep the same buffer and familiar controls as you move from inspection to repeated programming.</p></div><dl class="tool-list"><div><dt>Burn ROM Set</dt><dd>Work through several images in order, with an insertion prompt for each chip. Useful for hi/lo ROM pairs.</dd></div><div><dt>Duplicate &amp; batch write</dt><dd>Read a master, make copies, or write the buffer repeatedly with Write Next, Retry and Stop controls.</dd></div><div><dt>Stability reads</dt><dd>Compare three reads, highlight changing bytes and inspect the per-byte majority result.</dd></div><div><dt>Options per chip</dt><dd>Remember memory pages, ID and size checks, programming voltages, pulse delay and ICSP settings for each device.</dd></div><div><dt>Commands &amp; progress</dt><dd>Follow minipro’s output, copy the exact command and cancel a running operation with <kbd>⌘</kbd> <kbd>.</kbd>.</dd></div><div><dt>Socket placement</dt><dd>See orientation and placement for the selected package, with adapter guidance for packages that do not fit directly.</dd></div></dl></section>
<section id="start" class="start"><p class="eyebrow">GET STARTED</p><h2>Your programmer.<br>Your Mac. Your tools.</h2><div class="install"><div><h3>Build from source</h3><p>Install Xcode 15+ or Swift 5.9+ command-line tools and minipro. From the ZIFburn source folder:</p><pre><code>brew install minipro
make app
open build/ZIFburn.app</code></pre><p>The local build is ad-hoc signed. Build locally from source, or use the release packaging workflow to create a Developer ID signed and notarized universal app.</p></div><div><h3>Before your first burn</h3><p>Connect your supported XGecu programmer, choose the exact chip, and check orientation against your programmer’s printed diagram.</p><p>Buffer import supports binary and Intel HEX, with a 64 MiB Intel HEX expansion limit. Use direct Write File / Verify Against File for S-record images.</p><p>ZIFburn runs minipro as a separate program. Hardware and device support depend on your installed minipro version.</p><a href="https://gitlab.com/DavidGriffith/minipro">Visit the minipro project ↗</a></div></div></section>
<section id="questions" class="questions"><p class="eyebrow">GOOD TO KNOW</p><h2>Before the first chip.</h2><?php foreach ($site['questions'] as $question): ?>
<details><summary><?= escape($question['question']) ?></summary><p><?= escape($question['answer']) ?></p></details>
<?php endforeach; ?>
</section>
</main><footer><span>ZIFburn · MIT licensed</span><span>Independent software. Not affiliated with XGecu.</span></footer>
</body></html>
