<?php
declare(strict_types=1);

const ZIFBURN_REPOSITORY = 'https://github.com/retrocs-org/zifburn';
const ZIFBURN_RELEASE_API = 'https://api.github.com/repos/retrocs-org/zifburn/releases/latest';
const ZIFBURN_RELEASE_TTL = 300;
const ZIFBURN_RELEASE_MAX_STALE = 86400;
const ZIFBURN_RESPONSE_LIMIT = 1048576;

function zifburn_release_payload(array $raw): ?array
{
    $tag = $raw['tag_name'] ?? null;
    if (!is_string($tag) || $tag === '' || strlen($tag) > 128 || preg_match('/[\x00-\x20\x7f]/', $tag)
        || ($raw['draft'] ?? true) !== false || ($raw['prerelease'] ?? true) !== false
        || empty($raw['published_at']) || !is_string($raw['published_at'])
        || strtotime($raw['published_at']) === false) {
        return null;
    }
    $base = ZIFBURN_REPOSITORY . '/releases/download/' . rawurlencode($tag) . '/';
    if (isset($raw['assets']) && !is_array($raw['assets'])) { return null; }
    $assets = [];
    foreach ($raw['assets'] ?? [] as $asset) {
        if (!is_array($asset)) { continue; }
        $name = $asset['name'] ?? '';
        if (!is_string($name) || !preg_match('/\AZIFburn-[A-Za-z0-9_.-]+-macOS-universal\.(?:dmg|zip)(?:\.sha256)?\z/', $name)
            || ($asset['state'] ?? '') !== 'uploaded'
            || ($asset['browser_download_url'] ?? '') !== $base . rawurlencode($name)
            || isset($assets[$name]) || !is_int($asset['size'] ?? null) || $asset['size'] <= 0) {
            continue;
        }
        $assets[$name] = ['name' => $name, 'url' => $asset['browser_download_url'], 'size' => $asset['size']];
    }
    $downloads = [];
    foreach ($assets as $name => $asset) {
        if (str_ends_with($name, '.zip') || str_ends_with($name, '.dmg')) {
            $asset['format'] = str_ends_with($name, '.dmg') ? 'DMG' : 'ZIP';
            $asset['checksum'] = $assets[$name . '.sha256']['url'] ?? null;
            $downloads[] = $asset;
        }
    }
    usort($downloads, static fn(array $a, array $b): int => ($a['format'] === 'DMG' ? 0 : 1) <=> ($b['format'] === 'DMG' ? 0 : 1));
    return ['tag' => $tag, 'published_at' => $raw['published_at'], 'downloads' => $downloads,
            'url' => ZIFBURN_REPOSITORY . '/releases/tag/' . rawurlencode($tag),
            'source' => ZIFBURN_REPOSITORY . '/archive/refs/tags/' . rawurlencode($tag) . '.zip'];
}

function zifburn_fetch_release(): array
{
    $headers = ['User-Agent: ZIFburn-website', 'Accept: application/vnd.github+json', 'X-GitHub-Api-Version: 2022-11-28'];
    if (function_exists('curl_init')) {
        $handle = curl_init(ZIFBURN_RELEASE_API);
        $body = '';
        curl_setopt_array($handle, [CURLOPT_HTTPHEADER => $headers, CURLOPT_CONNECTTIMEOUT => 3,
            CURLOPT_TIMEOUT => 6, CURLOPT_FOLLOWLOCATION => false, CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2, CURLOPT_WRITEFUNCTION => static function ($handle, string $chunk) use (&$body): int {
                if (strlen($body) + strlen($chunk) > ZIFBURN_RESPONSE_LIMIT) { return 0; }
                $body .= $chunk;
                return strlen($chunk);
            }]);
        $ok = curl_exec($handle);
        $status = $ok === false ? 0 : (int) curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
        unset($handle);
        return ['status' => $status, 'body' => $body];
    }
    $context = stream_context_create(['http' => ['header' => implode("\r\n", $headers), 'timeout' => 6,
        'follow_location' => 0, 'ignore_errors' => true], 'ssl' => ['verify_peer' => true, 'verify_peer_name' => true]]);
    $http_response_header = [];
    $body = @file_get_contents(ZIFBURN_RELEASE_API, false, $context, 0, ZIFBURN_RESPONSE_LIMIT + 1);
    preg_match('/\s(\d{3})\s/', $http_response_header[0] ?? '', $match);
    return ['status' => $body !== false && strlen($body) <= ZIFBURN_RESPONSE_LIMIT ? (int) ($match[1] ?? 0) : 0,
            'body' => is_string($body) ? $body : ''];
}

function zifburn_write_release_cache(string $path, array $value): void
{
    // Cache only public metadata, outside the document root. Cache failures
    // must not prevent visitors from opening the page.
    if (is_link($path) || !is_dir(dirname($path))) { return; }
    $temp = @tempnam(dirname($path), 'zifburn-release-');
    if ($temp === false) { return; }
    @chmod($temp, 0600);
    if (@file_put_contents($temp, json_encode($value, JSON_UNESCAPED_SLASHES), LOCK_EX) !== false) {
        @rename($temp, $path);
    }
    if (is_file($temp)) { @unlink($temp); }
}

function zifburn_latest_release(?callable $fetch = null, ?string $cachePath = null, ?int $now = null): array
{
    if ($fetch === null && getenv('ZIFBURN_RELEASE_OFFLINE') === '1') {
        return ['status' => 'unavailable', 'release' => null];
    }
    $now ??= time();
    $cachePath ??= sys_get_temp_dir() . '/zifburn-release-' . hash('sha256', __DIR__) . '.json';
    $cache = null;
    if (!is_link($cachePath) && is_file($cachePath) && filesize($cachePath) <= ZIFBURN_RESPONSE_LIMIT * 2) {
        $bytes = @file_get_contents($cachePath);
        $cache = is_string($bytes) ? json_decode($bytes, true) : null;
    }
    $cachedRelease = is_array($cache['raw'] ?? null) ? zifburn_release_payload($cache['raw']) : null;
    $age = $now - (int) ($cache['fetched_at'] ?? 0);
    $usable = $cachedRelease !== null && $age >= 0 && $age < ZIFBURN_RELEASE_MAX_STALE;
    $checkedAge = $now - (int) ($cache['checked_at'] ?? 0);
    if (is_array($cache) && $checkedAge >= 0 && $checkedAge < ZIFBURN_RELEASE_TTL) {
        if ($usable) { return ['status' => empty($cache['failed']) ? 'ready' : 'stale', 'release' => $cachedRelease]; }
        if (($cache['status'] ?? null) === 404) { return ['status' => 'empty', 'release' => null]; }
        if (($cache['status'] ?? null) === 0) { return ['status' => 'unavailable', 'release' => null]; }
    }
    try { $response = ($fetch ?? 'zifburn_fetch_release')(); }
    catch (Throwable $error) { $response = ['status' => 0, 'body' => '']; }
    $raw = json_decode($response['body'] ?? '', true);
    $release = is_array($raw) ? zifburn_release_payload($raw) : null;
    if (($response['status'] ?? 0) === 200 && $release !== null) {
        zifburn_write_release_cache($cachePath, ['checked_at' => $now, 'fetched_at' => $now, 'status' => 200, 'raw' => $raw]);
        return ['status' => 'ready', 'release' => $release];
    }
    if (($response['status'] ?? 0) === 404) {
        zifburn_write_release_cache($cachePath, ['checked_at' => $now, 'status' => 404]);
        return ['status' => 'empty', 'release' => null];
    }
    if ($usable) {
        $cache['checked_at'] = $now;
        $cache['failed'] = true;
        zifburn_write_release_cache($cachePath, $cache);
        return ['status' => 'stale', 'release' => $cachedRelease];
    }
    zifburn_write_release_cache($cachePath, ['checked_at' => $now, 'status' => 0]);
    return ['status' => 'unavailable', 'release' => null];
}
