<?php
declare(strict_types=1);
require __DIR__ . '/../../public-web/release-data.php';
function check(bool $value, string $message): void { if (!$value) { throw new RuntimeException($message); } }
function sample(string $tag = '0.1'): array {
    $name = 'ZIFburn-' . $tag . '-macOS-universal.zip';
    $base = ZIFBURN_REPOSITORY . '/releases/download/' . rawurlencode($tag) . '/';
    return ['tag_name' => $tag, 'draft' => false, 'prerelease' => false, 'published_at' => '2026-11-11T12:00:00Z',
        'assets' => [['name' => $name, 'state' => 'uploaded', 'size' => 1600000, 'browser_download_url' => $base . $name],
                     ['name' => $name . '.sha256', 'state' => 'uploaded', 'size' => 98, 'browser_download_url' => $base . $name . '.sha256']]];
}
$folder = sys_get_temp_dir() . '/zifburn-website-test-' . bin2hex(random_bytes(8));
mkdir($folder, 0700);
try {
    $payload = sample();
    $parsed = zifburn_release_payload($payload);
    check($parsed !== null && count($parsed['downloads']) === 1, 'Expected Mac download');
    check(str_ends_with($parsed['downloads'][0]['checksum'], '.zip.sha256'), 'Expected exact matching checksum');
    $both = $payload;
    foreach ($payload['assets'] as $asset) {
        $asset['name'] = str_replace('.zip', '.dmg', $asset['name']);
        $asset['browser_download_url'] = str_replace('.zip', '.dmg', $asset['browser_download_url']);
        $both['assets'][] = $asset;
    }
    $downloads = zifburn_release_payload($both)['downloads'];
    check(count($downloads) === 2 && $downloads[0]['format'] === 'DMG' && $downloads[1]['format'] === 'ZIP', 'DMG first with ZIP alternative');
    check(str_ends_with($downloads[0]['checksum'], '.dmg.sha256'), 'DMG checksum matches image');
    foreach (['draft', 'prerelease'] as $field) {
        $bad = $payload; $bad[$field] = true;
        check(zifburn_release_payload($bad) === null, 'Excluded unpublished/prerelease');
    }
    $bad = $payload; $bad['tag_name'] = '';
    check(zifburn_release_payload($bad) === null, 'Reject empty tags');
    $bad = $payload; $bad['assets'][0]['browser_download_url'] = 'https://evil.invalid/app.zip';
    check(zifburn_release_payload($bad)['downloads'] === [], 'Reject unrelated download host');
    $bad = $payload; $bad['assets'][0]['browser_download_url'] = ZIFBURN_REPOSITORY . '/releases/download/old/app.zip';
    check(zifburn_release_payload($bad)['downloads'] === [], 'Reject download from another tag');
    $bad = $payload; array_pop($bad['assets']);
    check(zifburn_release_payload($bad)['downloads'][0]['checksum'] === null, 'Do not invent missing checksum');
    $future = zifburn_release_payload(sample('1.2.3'));
    check($future['tag'] === '1.2.3' && str_contains($future['downloads'][0]['url'], '/1.2.3/'), 'Future releases need no code edits');
    $path = $folder . '/cache.json'; $now = 2000000000; $calls = 0;
    $fetch = static function () use (&$calls, $payload): array { $calls++; return ['status' => 200, 'body' => json_encode($payload)]; };
    check(zifburn_latest_release($fetch, $path, $now)['status'] === 'ready', 'Fresh API success');
    check(zifburn_latest_release($fetch, $path, $now + 10)['status'] === 'ready' && $calls === 1, 'Cache avoids repeated API calls');
    $fail = static fn(): array => ['status' => 403, 'body' => 'rate limited'];
    check(zifburn_latest_release($fail, $path, $now + 301)['status'] === 'stale', 'Use labelled recent cache after API failure');
    check(zifburn_latest_release($fail, $path, $now + 90000)['status'] === 'unavailable', 'Expire old cached releases');
    $empty = static fn(): array => ['status' => 404, 'body' => '{}'];
    check(zifburn_latest_release($empty, $folder . '/empty.json', $now)['status'] === 'empty', 'No releases yet');
    check(zifburn_latest_release($fail, $folder . '/new.json', $now)['status'] === 'unavailable', 'Graceful first-request API failure');
    $invalid = static fn(): array => ['status' => 200, 'body' => '<html>Bad gateway</html>'];
    check(zifburn_latest_release($invalid, $folder . '/bad.json', $now)['status'] === 'unavailable', 'Graceful malformed response');
    $throw = static function (): array { throw new RuntimeException('timeout'); };
    check(zifburn_latest_release($throw, $folder . '/timeout.json', $now)['status'] === 'unavailable', 'Graceful transport exception');
    $next = static fn(): array => ['status' => 200, 'body' => json_encode(sample('0.2'))];
    $nextState = zifburn_latest_release($next, $path, $now + 91000);
    check($nextState['release']['tag'] === '0.2', 'Cache refresh discovers a later release');
    check(zifburn_latest_release($empty, $path, $now + 92000)['status'] === 'empty', 'Deleted releases do not stay cached');
    echo "Download metadata, URL validation, future releases, cache refresh and failure tests passed.\n";
} finally {
    foreach (glob($folder . '/*') as $file) { unlink($file); }
    rmdir($folder);
}
