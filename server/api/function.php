<?php
if (!isset($rewrite_done)) {
	die('Not rewritten yet');
}

require_once('config.php');
global $db;

global $user;

header('Content-Type: text/plain');

function login_failure($code) {
	header('WWW-Authenticate: Basic realm="DSO API"');
	header('HTTP/1.0 401 Unauthorized');
	die($code . '');

}

if (empty($_SERVER['PHP_AUTH_USER']) || empty($_SERVER['PHP_AUTH_PW'])) {
	login_failure('1002');
}

$stmt = $db->prepare("SELECT * FROM users WHERE username=? AND password=?");
$stmt->bind_param('ss', $_SERVER['PHP_AUTH_USER'], $_SERVER['PHP_AUTH_PW']);
$stmt->execute();
$res = $stmt->get_result();
$user = $res->fetch_array();

if (!$user) {
	// bad username or password
	login_failure('1002');
} else if ($user['active'] === 1) {
	// account is active
	$auth = '1001';
} else {
	// account disabled
	login_failure('1003');
}

function validIP($ip)
{
	global $db;
	$domain = explode('.', $ip);
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

function getDomainInfo($domain)
{
	global $db;
	$domain = explode('.', $domain);

	$result = null;

	if (sizeof($domain) == 2) {
		$stmt = $db->prepare("SELECT d.id, ipt.owner, d.subowners, d.filekeys FROM domain d, iptable ipt WHERE d.name=? AND d.ext=? AND d.id=ipt.id");
		$stmt->bind_param('ss', $domain[0], $domain[1]);
		$stmt->execute();
		$result = $stmt->get_result();
	} else if (sizeof($domain) == 3) {
		$stmt = $db->prepare("SELECT s.id, ipt.owner, d.subowners, s.filekeys FROM subdomain s, iptable ipt, domain d WHERE d.name=? AND d.ext=? AND d.id=s.hostid AND s.name=? AND s.id=ipt.id");
		$stmt->bind_param('sss', $domain[1], $domain[2], $domain[0]);
		$stmt->execute();
		$result = $stmt->get_result();
	} else if (sizeof($domain) == 4) {
		$ipdom = $domain[0] . '.' . $domain[1] . '.' . $domain[2] . '.' . $domain[3];
		$stmt = $db->prepare("SELECT id, owner, '', filekeys FROM iptable WHERE ip=?");
		$stmt->bind_param('s', $ipdom);
		$stmt->execute();
		$result = $stmt->get_result();
	}

	if ($result && $result->num_rows == 1) {
		return $result->fetch_row();
	} else {
		return array(-1, -1, '', '');
	}
}

function domain_exists($domain, $ext)
{
	global $db;
	$stmt = $db->prepare("SELECT id FROM domain WHERE name=? AND ext=?");
	$stmt->bind_param('ss', $domain, $ext);
	$stmt->execute();
	$result = $stmt->get_result();
	if ($result->num_rows == 1) {
		return true;
	} else {
		return false;
	}
}

function getDomainId($domain, $ext)
{
	global $db;
	$stmt = $db->prepare("SELECT id FROM domain WHERE name=? AND ext=?");
	$stmt->bind_param('ss', $domain, $ext);
	$stmt->execute();
	$result = $stmt->get_result();
	if ($result->num_rows == 1) {
		return $result->fetch_row()[0];
	} else {
		return -1;
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
	$vercode = rand(100, 999) . rand(100, 999) . rand(100, 999) . rand(100, 999) . rand(100, 999);

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
		if ($from_id == -1) {
			// Invalid from user id.
			$status = "INVALID-SENDER";
		} else if ($to_id == -1) {
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
	return $status == 'COMPLETE';
}
