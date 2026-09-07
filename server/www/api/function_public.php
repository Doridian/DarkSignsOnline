<?php

// What every API endpoint needs before it knows who is calling: the database,
// the response headers, and the base64 the wire format is written in.
//
// `function.php` is this plus an account. The two are separate because not
// every endpoint has one to insist on -- reading chat is public, the way
// `chatlog.php` has always been -- and `function.php` authenticates at
// include time, so an endpoint that includes it has already paid for a
// password check it may not need. That check is bcrypt, and bcrypt is
// deliberately expensive.
//
// This is not the website's header. `_function_base.php` is what the pages
// use; anything that declares `text/plain` belongs here and not there.

require_once('function_base.php');

header('Content-Type: text/plain');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
// These have to be named rather than wildcarded. The `*` value does not
// cover Authorization -- the Fetch standard excludes it -- so a browser
// client sending Basic auth fails the preflight and never makes the call.
// DSO-Protocol-Version is a custom header, so it is not safelisted either.
header('Access-Control-Allow-Headers: Authorization, Content-Type, DSO-Protocol-Version');
header('Access-Control-Expose-Headers: *');
// Basic auth makes a preflight unavoidable for a cross-origin browser
// client, so let it cache the answer rather than asking before every call.
header('Access-Control-Max-Age: 86400');
// Deliberately no Access-Control-Allow-Credentials: a browser rejects it
// outright alongside a wildcard origin, and the clients send Authorization
// as an ordinary header rather than using credentials mode.
if (strtoupper($_SERVER['REQUEST_METHOD']) === 'OPTIONS') {
    // Preflight CORS request, just smile and 200
    exit;
}

// The wire format's base64: the URL-safe alphabet with the padding stripped.
$BASE64_DSO_ENCODE = array(
    '+' => '-',
    '/' => '_',
    '=' => '',
);
$BASE64_DSO_DECODE = array(
    '-' => '+',
    '_' => '/',
);

function dso_b64_decode($str) {
    global $BASE64_DSO_DECODE;
    return base64_decode(strtr($str, $BASE64_DSO_DECODE));
}

function dso_b64_encode($str) {
    global $BASE64_DSO_ENCODE;
    return strtr(base64_encode($str), $BASE64_DSO_ENCODE);
}
