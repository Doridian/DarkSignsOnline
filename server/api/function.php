<?php

require_once('function_base.php');

header('Content-Type: text/plain');

function login_failure($code) {
	header('WWW-Authenticate: Basic realm="DSO API"');
	header('HTTP/1.0 401 Unauthorized');
	die($code . '');

}

if (empty($_SERVER['PHP_AUTH_USER']) || empty($_SERVER['PHP_AUTH_PW'])) {
	login_failure('1002');
}

$stmt = $db->prepare("SELECT * FROM users WHERE username=?");
$stmt->bind_param('s', $_SERVER['PHP_AUTH_USER']);
$stmt->execute();
$res = $stmt->get_result();
$user = $res->fetch_assoc();

if (!$user || !password_verify($_SERVER['PHP_AUTH_PW'], $user['password'])) {
	// bad username or password
	login_failure('1002');
} else if ($user['active'] <= 0) {
	// account disabled
	login_failure('1003');
}

unset($user['password']);

function validIP($ip)
{
	global $db;
	$domain = explode('.', $ip);
	if (sizeof($domain) !== 4) {
		return false;
	}

	$domain[0] = intval($domain[0]);
	$domain[1] = intval($domain[1]);
	$domain[2] = intval($domain[2]);
	$domain[3] = intval($domain[3]);

	if ($domain[0] > 0 && $domain[0] < 256 && $domain[1] > 0 && $domain[1] < 256 && $domain[2] > 0 && $domain[2] < 256 && $domain[3] > 0 && $domain[3] < 256) {
		return true;
	} else {
		return false;
	}
}

function getDomainInfo($domain) {
	global $db;

	$stmt = $db->prepare('SELECT id, owner, keycode, ip, time FROM domains WHERE ip=? OR host=?');
	$stmt->bind_param('ss', $domain, $domain);
	$stmt->execute();
	$result = $stmt->get_result();
	if ($result->num_rows == 1) {
		return $result->fetch_assoc();
	}
	return false;
}

function getDomainById($id) {
	global $db;

	$stmt = $db->prepare('SELECT id, owner, keycode, ip, time FROM domains WHERE id=?');
	$stmt->bind_param('i', $id);
	$stmt->execute();
	$result = $stmt->get_result();
	if ($result->num_rows == 1) {
		return $result->fetch_assoc();
	}
	return false;
}

function getIpDomain($ip)
{
	global $db;

	$stmt = $db->prepare("SELECT ip, host FROM domains WHERE ip=? OR host=?");
	$stmt->bind_param('ss', $ip, $ip);
	$stmt->execute();
	$result = $stmt->get_result();
	$row = $result->fetch_assoc();
	if (empty($row))  {
		return '';
	}

	if (empty($row['host'])) {
		return $row['ip'];
	} else {
		return $row['host'];
	}
}

function getCash($user_id)
{
	global $db;
	$stmt = $db->prepare("SELECT cash FROM users WHERE id=?");
	$stmt->bind_param('i', $user_id);
	$stmt->execute();
	$result = $stmt->get_result();
	if ($result->num_rows === 1) {
		return $result->fetch_row()[0];
	} else {
		return 0;
	}
}

function transaction($from_id, $to_id, $description, $amount, $returnkeycodeinstead = 0)
{
	global $db;
	$vercode = make_keycode();

	if ($from_id > 0 && $to_id > 0 && $from_id != $to_id) {
		if ($amount > 0) {
			$from_cash = getCash($from_id);
			//$to_cash = getCash($to_id);

			if ($from_cash < $amount) {
				// Insufficient Funds
				$status = 'INSUFFICIENT';
			} else {
				$neg_amount = -$amount;

				$stmt = $db->prepare('UPDATE users SET cash=cash+? WHERE id=?');
				$stmt->bind_param('ii', $neg_amount, $from_id);
				$stmt->execute();

				$stmt->bind_param('ii', $amount, $to_id);
				$stmt->execute();

				$status = 'COMPLETE';
			}
		} else {
			// Cant send negative DSD.
			$status = 'INVALID-AMOUNT';
		}
	} else {
		if ($from_id <= 0) {
			// Invalid from user id.
			$status = "INVALID-SENDER";
		} else if ($to_id <= 0) {
			// Invalid to user id.
			$status = "INVALID-RECEIVER";
		} else {
			// Cant send money to yourself.
			$status = "INVALID-USER";
		}
	}

	$time = time();
	$ip = $_SERVER['REMOTE_ADDR'];

	$stmt = $db->prepare("INSERT INTO transactions (fromid, toid, amount, description, vercode, `time`, status, ip) VALUES (?, ?, ?, ?, ?, ?, ?, ?)");
	$stmt->bind_param('iissssss', $from_id, $to_id, $amount, $description, $vercode, $time, $status, $ip);
	$stmt->execute();

	if ($returnkeycodeinstead == 1) {
		return $vercode;
	}
	return $status;
}

function idToUser($id) {
	global $db;
	$stmt = $db->prepare('SELECT username FROM users WHERE id=?');
	$stmt->bind_param('i', $id);
	$stmt->execute();
	$res = $stmt->get_result();
	$row = $res->fetch_assoc();
	if (empty($row)) {
		return '';
	}
	return $row['username'];
}

function userToId($username) {
	global $db;
	$stmt = $db->prepare('SELECT id FROM users WHERE username=?');
	$stmt->bind_param('s', $username);
	$stmt->execute();
	$res = $stmt->get_result();
	$row = $res->fetch_assoc();
	if (empty($row)) {
		return -1;
	}
	return $row['id'];
}

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

function line_endings_to_dos($str) {
	return preg_replace("/(\r\n|\r|\n)/", "\r\n", $str);
}
