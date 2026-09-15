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
// The headers are `function_cors.php`, which is this without the database:
// `time.php` is asked every few seconds as the client's ping and cannot
// afford a MySQL connection to answer with the time.

require_once('function_base.php');
require_once('function_cors.php');

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
