<?php

$rewrite_done = true;
require_once 'function.php';

$port = (int) $_REQUEST['port'];

if ($port < 1 || $port > 65536) {
	die ('not found');
}

$d = strtolower($_REQUEST['d']);
if (empty($d)) {
    die ('not found');
}

require_once('jwt/JWTExceptionWithPayloadInterface.php');
require_once('jwt/BeforeValidException.php');
require_once('jwt/ExpiredException.php');
require_once('jwt/SignatureInvalidException.php');
require_once('jwt/CachedKeySet.php');
require_once('jwt/Key.php');
require_once('jwt/JWK.php');
require_once('jwt/JWT.php');

use Firebase\JWT\JWT;

$start = time();
$payload = [
    'iss' => 'http://darksignsonline.com',
    'aud' => "http://$d:$port",
    'sub' => ''.$user['id'],
    'name' => $user['username'],
    'iat' => $start,
    'exp' => $start + (5 * 60),
];

echo JWT::encode($payload, $JWT_PRIVATE_KEY, 'RS256');
