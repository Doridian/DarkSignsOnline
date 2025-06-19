<?php

require_once('function.php');

$version = strtolower(trim($_REQUEST['version']));
if (empty($version)) {
    die('0000OK');
}

if ($version === 'dev') {
    die('0000OK');
}

$is_nightly = true;
if (strpos($version, '.') !== false) {
    $is_nightly = false;
}

foreach (json_decode(file_get_contents('../releases.json')) as $release) {
    $name = $release->name;

    $is_for_nightly = false;
    if ($name === 'main' || $name === 'latest') {
        $is_for_nightly = true;
        $name = file_get_contents('gitrev.txt');
    }

    if ($is_nightly !== $is_for_nightly) {
        continue;
    }

    $name = trim($name);
    if ($version !== strtolower($name)) {
        die('0002Client update available! Please download version ' . $name . ' at https://darksignsonline.com/download.php');
    }
}

die('0000OK');
