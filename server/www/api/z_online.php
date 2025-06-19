<?php

require_once('function.php');

if (empty($_REQUEST['version'])) {
    die('0000OK');
}

$version = strtolower(trim($_REQUEST['version']));
if (empty($version)) {
    die('0000OK');
}

if ($version === 'dev') {
    die('0000OK');
}

$release_track = 'stable';
if (strpos($version, '.') === false) {
    $release_track = 'nightly';
    die('0000OK'); // nightly doesn't auto-update for now
}

$releases = json_decode(file_get_contents('../releases.json'));
$release = @$releases->{$release_track};

$current = strtolower($release->name);

if ($version !== $current) {
    die('0002Client update available! Please download version ' . $release->name . ' at https://darksignsonline.com/download.php');
}

die('0000OK');
