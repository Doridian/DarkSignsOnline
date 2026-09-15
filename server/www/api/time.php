<?php

// The server's clock, and the client's ping.
//
// This is the cheapest thing the site can be asked: no account, no database,
// no password check -- one process, one line, one number. That is what makes
// it the round trip the browser client measures in its title bar, asked
// every few seconds for as long as anyone is looking at it. `function_cors.php`
// rather than `function_public.php` for the same reason: the client is
// served cross-origin in development and needs the headers, but a ping that
// opens a MySQL connection to tell you the time is not a ping.

require_once('function_cors.php');

die('' . time());
