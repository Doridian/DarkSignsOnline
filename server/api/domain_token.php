<?php

$need_jwt_private_key = true;
require_once("function.php");

$d = strtolower($_REQUEST['d']);
if (empty($d)) {
    die_error('No domain specified');
}

$dInfo = getDomainInfo($d);
if ($dInfo === false) {
	die_error('not found', 404);
}

if (($user['id'] !== $dInfo['owner']) && ($_REQUEST['is_local_script'] === 'true')) {
    die_error('not owned', 403);
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
    'iss' => 'https://darksignsonline.com/api/domain_token.php',
    'aud' => $d,
    'sub' => ''.$user['id'],
    'name' => $user['username'],
    'info'=> ''.$_REQUEST['info'],
    'iat' => $start,
    'exp' => $start + (5 * 60),
];

echo JWT::encode($payload, $JWT_PRIVATE_KEY, 'RS256');
