<?php

// The headers every endpoint answers with, and nothing else.
//
// Split out of `function_public.php` for the one caller that cannot afford
// the rest of it: `time.php` is what the browser client measures its round
// trip with, so it is asked every few seconds by every player watching the
// title bar, and `function_public.php` pulls in `function_base.php` and a
// MySQL connection with it. A ping that opens a database handle to tell the
// client the time is a ping that costs more than the thing it is measuring.
//
// This is not the website's header. `_function_base.php` is what the pages
// use; anything that declares `text/plain` belongs here and not there.

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
