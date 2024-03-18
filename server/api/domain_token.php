<?php

$rewrite_done = true;
require_once 'function.php';

echo '2000';

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

$payload = [
    'iss' => 'http://example.org',
    'aud' => 'http://example.com',
    'iat' => 1356999524,
    'nbf' => 1357000000
];

$jwt = JWT::encode($payload, $JWT_PRIVATE_KEY, 'RS256');
echo $jwt;
